import 'dart:async';

import 'package:meta/meta.dart';

import 'msg.dart';
import 'pure.dart';
import 'store.dart';

/// One LAUNCH — the element of a guard's verdict. A guard at index x may
/// target exactly TWO indices, the only two that preserve the system's
/// theorem (no row ever sees a message that skipped a guard above it):
///
///  * [Judgment.forward] — index x+1: judged by every guard above, the
///    message continues THIS round;
///  * [Judgment.mint]    — index 0: a DERIVED fact, its own round after the
///    current one completes, re-judged by every guard. Minted facts are
///    NEVER journaled — they re-derive on replay, so the journal stays
///    inputs-only. Sibling mints must COMMUTE (`replay([…,a,b]) ==
///    replay([…,b,a])`) — a mint is a fact the fold already implies,
///    restatable as a law about state; sequencing over time belongs to
///    effects, never to mints.
sealed class Judgment {
  const factory Judgment.forward(Msg msg) = ForwardJudgment;
  const factory Judgment.mint(Msg msg) = MintJudgment;
}

/// Continue [msg] at the next row — judged by everything above this guard.
final class ForwardJudgment implements Judgment {
  const ForwardJudgment(this.msg);
  final Msg msg;
}

/// Derive [msg] as a NEW round from the top of the queue, after the current
/// round completes. Unjournaled: re-derived on replay.
final class MintJudgment implements Judgment {
  const MintJudgment(this.msg);
  final Msg msg;
}

/// A PURE judge standing at its row of the queue: every traversing message
/// of the [M] family is submitted to [judge], whose returned set IS its
/// verdict — one verb for every shape of judgment:
///
///  * `{.forward(msg)}`   — PASS it unchanged;
///  * `const {}`          — DROP it (the walk stops for every row below;
///                           rows above have already folded);
///  * `{.forward(other)}` — REWRITE it;
///  * `{.forward(a), .forward(b)}` — FAN OUT below, in set order;
///  * `{.mint(b)}`        — DERIVE: b runs as its own round from index 0.
///
/// Non-[M] messages pass untouched. The journal always keeps the ORIGINAL
/// fact — guards shape the admitted feed, never the record — so a replay
/// reproduces every branch AND every mint deterministically from the
/// source fact. Set insertion order is execution order, always.
///
/// THE LOCALITY AXIOM: a judge is a pure function of (message, current
/// state) — never of why the cursor arrived, what round this is, or what
/// minted what. Stores transform state and nothing else; guards enqueue
/// cursors (at 0 or x+1) and nothing else. The world is readable only
/// through [read] — the OWN ledger's state, by regent identity — so a
/// guard is replayable by construction and table-testable with
/// (state, msg) pairs alone: judgments are VALUES.
abstract base class Guard<M extends Msg> extends Regent
    implements At<GuardMemory<M>> {
  const Guard();

  @pure
  Set<Judgment> judge(M msg, ReadStore read);

  @override
  Null mount(LedgerRows ledger) {
    ledger.guard<M>(this);
    return null;
  }
}

/// One judgment's full story, emitted AFTER the verdict ran: the submitted
/// message and what the guard launched for it, atomically — for a [Veto],
/// an empty [verdict] IS the block. Observation only (`ledger.at(spec)`);
/// the flow itself never depends on it.
@immutable
final class GuardEvent<M extends Msg> {
  const GuardEvent({required this.msg, required this.verdict});

  final M msg;
  final Set<Judgment> verdict;

  /// Nothing continued below this row — the drop, as a question.
  bool get dropped => verdict.isEmpty;
}

/// The live handle at a guard's row (`ledger.at(const CachedGate())`):
/// the judged input and the verdict, observable — a judge holds no state,
/// so its memory is pure story. Plural members are streams, all derived
/// from the atomic [events]:
final class GuardMemory<M extends Msg> {
  final StreamController<GuardEvent<M>> _events =
      StreamController<GuardEvent<M>>.broadcast();

  /// One event per judged message: (input, verdict) atomically — the
  /// PRIMITIVE the branches below derive from.
  Stream<GuardEvent<M>> get events => _events.stream;

  /// The [T]-typed messages that reached this judge.
  Stream<T> msgs<T extends M>() =>
      events.where((e) => e.msg is T).map((e) => e.msg as T);

  /// The messages whose verdict was EMPTY — the veto's bool, as a feed.
  Stream<M> get dropped =>
      events.where((e) => e.dropped).map((e) => e.msg);

  /// What continued below this row (rewrites and fan-outs included).
  Stream<Msg> get forwarded => events.expand(
      (e) => [for (final j in e.verdict.whereType<ForwardJudgment>()) j.msg]);

  /// The derivations this judge launched as new rounds.
  Stream<Msg> get minted => events.expand(
      (e) => [for (final j in e.verdict.whereType<MintJudgment>()) j.msg]);

  void add(GuardEvent<M> event) => _events.add(event);

  void dispose() {
    _events.close();
  }
}

/// The refusing specialization — a guard that only ever passes or drops.
/// TRUE from [block] drops the message.
abstract base class Veto<M extends Msg> extends Guard<M> {
  const Veto();

  bool block(M msg, ReadStore read);

  @override
  Set<Judgment> judge(M msg, ReadStore read) =>
      block(msg, read) ? const {} : {.forward(msg)};
}
