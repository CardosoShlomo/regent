import 'envelope.dart';
import 'msg.dart';
import 'pure.dart';
import 'store.dart';

/// A PURE judge standing at its row of the queue: every traversing message
/// of the [M] family is submitted to [judge], which may PASS it (return it
/// unchanged), DROP it (return null — the walk stops for every row below;
/// rows above have already folded), or REWRITE it (return a different
/// message, which is what the rows below see). Non-[M] messages pass
/// untouched. The journal always keeps the ORIGINAL fact — guards shape the
/// admitted feed, never the record.
///
/// The world is readable only through [S] — the app-generated read-only
/// stores facade — so a guard is replayable by construction: same journal,
/// same verdicts.
abstract base class Guard<M extends Msg, S> extends Regent {
  const Guard();

  @pure
  Msg? judge(Envelope env, M msg, S stores);

  @override
  Null mount(LedgerRows ledger, Object? stores) {
    ledger.guard<M, S>(this, stores as S);
    return null;
  }
}

/// The refusing specialization — a guard that only ever passes or drops.
/// TRUE from [block] drops the message.
abstract base class Veto<M extends Msg, S> extends Guard<M, S> {
  const Veto();

  bool block(Envelope env, M msg, S stores);

  @override
  Msg? judge(Envelope env, M msg, S stores) =>
      block(env, msg, stores) ? null : msg;
}
