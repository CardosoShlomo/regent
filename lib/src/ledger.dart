import 'dart:async';

import 'package:identifiable/identifiable.dart';

import 'envelope.dart';
import 'guard.dart';
import 'msg.dart';
import 'store.dart';

/// The cohesive entry point: a JOURNAL (the complete, ungated record every
/// message lands in) and POSTING (guards decide what the ledger ADMITS).
/// Stores reduce the admitted feed and [on] taps the same feed, so a vetoed
/// message still appears in the journal (replay / ring buffer / debug) but
/// never reaches state OR effects — "control without dirtying".
///
/// Dispatch onto the journal (`dispatch`), subscribe to admitted messages
/// (`on`), tap the raw record (`journal.on`), and register stores via `store`.
class Ledger implements LedgerRows {
  Ledger() {
    // Every journal message enters the FIRST segment of the queue; guards
    // forward (or drop, or rewrite) between segments; the last segment
    // forwards into [_posted], which [on] taps.
    _tail = _segment(journal);
    _plumbTailToPosted();
    _connSub = journal.connection.listen((v) {
      for (final b in _segments) {
        b.setConnected(v);
      }
      _posted.setConnected(v);
    });
  }

  /// The complete, ungated record. Dispatch here; tap here for replay/debug.
  final Bus journal = Bus();

  /// The end of the queue — what survived EVERY guard. Effects tap it via
  /// [on], so nothing fires on a dropped message.
  final Bus _posted = Bus();

  // ── The queue: segments of stores separated by guards ──
  final List<Bus> _segments = [];
  late Bus _tail;
  StreamSubscription<Object?>? _tailForward;

  /// A new segment fed by [source] (verbatim forward).
  Bus _segment(Bus source) {
    final seg = Bus();
    _forwards.add(source.spine<Msg>().listen((r) {
      final (msg, env) = r;
      seg.dispatch(msg,
          optimistic: env.optimistic, correlationId: env.correlationId);
    }));
    _segments.add(seg);
    return seg;
  }

  void _plumbTailToPosted() {
    _tailForward?.cancel();
    _tailForward = _tail.spine<Msg>().listen((r) {
      final (msg, env) = r;
      _posted.dispatch(msg,
          optimistic: env.optimistic, correlationId: env.correlationId);
    });
  }

  final List<StreamSubscription<Object?>> _forwards = [];
  final List<void Function(String)> _rollbacks = []; // per-store overlay rollback
  final List<void Function()> _disposers = []; // dispose the stores `close` owns
  int _seq = 0; // monotonic correlation id source (no time/random dependency)
  late final StreamSubscription<bool> _connSub;

  /// The declared form: a ledger CONSTRUCTED from its regent enum — [rows]
  /// must be the enum's full `values` list, so the citizen list is closed
  /// and row order IS queue order. Guard rows judge through [read] — this
  /// ledger's own state, no facade. Memories are read back per row, and
  /// [SpecLedger.on] reads the feed at any declared position.
  static SpecLedger<R> of<R extends RegentNode<R>>(List<R> rows) =>
      SpecLedger._(rows);

  // ── Citizen-identity state lookup (guards judge through it) ──

  // Memories keyed by their spec INSTANCE. Const canonicalization makes the
  // constructor expression the citizen's name; registration rejects a
  // duplicate identical instance, so the lookup is total and unambiguous.
  final Map<Object, Object> _specMemories = Map.identity();

  /// This ledger's own CONFIRMED state by citizen identity — what every
  /// guard row judges through: `read(const BrowseDeck())` is the deck's
  /// keyed collection, `read(const AuthMachine())` the unit's value. Base
  /// truth only — no optimistic overlays, no merge edges — so a judge never
  /// rules on a prediction that hasn't been acknowledged.
  S read<S>(AnyStore<S> spec) {
    final memory = _specMemories[spec] ??
        (throw StateError(
            'no row holds this ${spec.runtimeType} instance — the lookup is '
            'by IDENTITY: match the row\'s constructor args exactly, and '
            'spell `const` (a non-const expression is a fresh instance).'));
    return switch (memory) {
      final StoreMemory m => m.base as S,
      final UnitMemory m => m.base as S,
      _ => throw StateError('unreadable memory for ${spec.runtimeType}'),
    };
  }

  void _enroll(Object spec, Object memory) {
    if (_specMemories.containsKey(spec)) {
      throw StateError(
          'two rows hold the identical ${spec.runtimeType} instance — const '
          'canonicalization makes them one citizen. Differ the args or '
          'subclass to declare two.');
    }
    _specMemories[spec] = memory;
  }

  /// Place [spec] at the CURRENT row of the queue: rows registered before it
  /// see every message; rows after it see only what it admits (possibly
  /// rewritten). The judge reads the world through this ledger's own
  /// [read] function.
  @override
  void guard<M extends Msg>(covariant Guard<M> spec) {
    final source = _tail;
    final seg = Bus();
    _forwards.add(source.spine<Msg>().listen((r) {
      final (msg, env) = r;
      // The returned set IS the feed below: empty = drop, one = pass/rewrite,
      // many = fan-out branches in set order. The journal keeps the original.
      final next = msg is M ? spec.judge(env, msg, read) : {msg};
      for (final m in next) {
        seg.dispatch(m,
            optimistic: env.optimistic, correlationId: env.correlationId);
      }
    }));
    _segments.add(seg);
    _tail = seg;
    _plumbTailToPosted();
  }

  /// The inline predicate form of a [Veto] — TRUE drops the message from
  /// this row down. For hand wiring; enum rows use [Veto] classes.
  void veto<M extends Msg>(bool Function(M msg) test) {
    final source = _tail;
    final seg = Bus();
    _forwards.add(source.spine<Msg>().listen((r) {
      final (msg, env) = r;
      if (msg is M && test(msg)) return;
      seg.dispatch(msg,
          optimistic: env.optimistic, correlationId: env.correlationId);
    }));
    _segments.add(seg);
    _tail = seg;
    _plumbTailToPosted();
  }

  /// Push a message onto the journal (it then posts through the guards).
  void dispatch(Msg msg, {bool optimistic = false, String? correlationId}) =>
      journal.dispatch(msg,
          optimistic: optimistic, correlationId: correlationId);

  /// The MANUAL-STORE door: subscribe to typed messages the ledger ADMITTED —
  /// the exact feed registered stores reduce — and wire your own reduce logic
  /// (a riverpod Notifier, a bloc) where [Store] is too simple. Side-effect
  /// subscribers (snackbars, sounds) belong here too: post-guard, so nothing
  /// fires on a vetoed message.
  ///
  /// A manual store forgoes [StoreMemory]'s machinery — the envelope carries
  /// `optimistic`/`correlationId`, but overlays and [rollback] are on you.
  /// For the complete ungated record (replay/debug/transport), tap
  /// `journal.on<M>` explicitly.
  Stream<M> on<M extends Msg>() => _posted.on<M>();

  /// Like [on], with each message's [Envelope] (provenance/correlation).
  Stream<(M, Envelope)> envelopesOf<M extends Msg>() => _posted.envelopesOf<M>();

  /// Discard the optimistic overlay(s) for [correlationId] across every store —
  /// the prediction failed. Confirmed/superseding writes survive (base is clean).
  void rollback(String correlationId) {
    for (final r in _rollbacks) {
      r(correlationId);
    }
  }

  /// Issue an OPTIMISTIC command: dispatch [optimistic] as a prediction (instant
  /// UI), run [effect] (the app's transport send), and reconcile. The TRANSPORT
  /// is yours — `effect` performs the network call; if it resolves with the
  /// server's confirming message that message is dispatched under the same
  /// correlation id (promoting the overlay into base), and if it returns null the
  /// promotion is left to an inbound push carrying that id. If `effect` throws,
  /// the overlay is rolled back and the error rethrown. Returns the correlation id.
  Future<String> command(Msg optimistic,
      {required Future<Msg?> Function() effect}) async {
    final cid = 'c${_seq++}';
    dispatch(optimistic, optimistic: true, correlationId: cid);
    try {
      final confirmed = await effect();
      if (confirmed != null) dispatch(confirmed, correlationId: cid);
    } catch (_) {
      rollback(cid);
      rethrow;
    }
    return cid;
  }

  /// Report transport connection state (drives stability on every store).
  void setConnected(bool value) => journal.setConnected(value);

  /// A live store for [spec], standing at the CURRENT row: it folds
  /// whatever survives the guards declared above it.
  @override
  StoreMemory<K, E, M> store<K, E extends Identifiable<K>, M extends Msg>(
      Store<K, E, M> spec) {
    final mem = StoreMemory<K, E, M>(spec, _tail);
    _enroll(spec, mem);
    _rollbacks.add(mem.rollback);
    _disposers.add(mem.dispose);
    return mem;
  }

  /// A live UNIT store for [spec] (cardinality one, keyless facts).
  @override
  UnitMemory<S, M> unit<S, M extends Msg>(Unit<S, M> spec) {
    final mem = UnitMemory<S, M>(spec, _tail);
    _enroll(spec, mem);
    _rollbacks.add(mem.rollback);
    _disposers.add(mem.dispose);
    return mem;
  }

  void close() {
    for (final d in _disposers) {
      d();
    }
    for (final f in _forwards) {
      f.cancel();
    }
    _tailForward?.cancel();
    _connSub.cancel();
    journal.close();
    for (final b in _segments) {
      b.close();
    }
    _posted.close();
  }
}

/// A ledger built from its DECLARED regent enum ([Ledger.of]): the citizen
/// list is closed, row order is queue order, and every gap between rows is a
/// named observation point. `on<M>()` keeps the base meaning (past the last
/// row — fully admitted); `on<M>(before: row)` reads the feed exactly as it
/// reaches that citizen, so `before: rows.first` is the raw ingress and
/// `before: someStore` is what that store folds.
final class SpecLedger<R extends RegentNode<R>> extends Ledger {
  SpecLedger._(this.rows) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].index != i) {
        throw ArgumentError(
            'rows must be the regent enum\'s full `values` list in order; '
            'row ${rows[i].name} sits at ${rows[i].index}, got position $i');
      }
    }
    for (final row in rows) {
      _sources[row] = _tail;
      _memories[row] = row.regent.mount(this);
    }
  }

  /// The declared citizen list — the enum's `values`, verbatim.
  final List<R> rows;

  final Map<R, Bus> _sources = {};
  final Map<R, Object?> _memories = {};

  /// [row]'s live memory: a `StoreMemory` for store rows, a `UnitMemory`
  /// for unit rows, null for guard rows.
  Object? memoryOf(R row) => _memories[row];

  @override
  Stream<M> on<M extends Msg>({R? before}) =>
      before == null ? super.on<M>() : _sources[before]!.on<M>();
}

