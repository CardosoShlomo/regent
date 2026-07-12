import 'dart:async';

import 'package:identifiable/identifiable.dart';

import 'regency.dart';
import 'guard.dart';
import 'msg.dart';
import 'store.dart';

/// The queue of positions, behind TWO doors:
///
///  * [dispatch] — state a fact (it lands on the record, then walks the
///    guards; what survives reaches the rows below each judge).
///  * [at] — stand at a position: a row's live handle by instance identity
///    (`at(const Products())`), or a sentinel (`at(.entry)` the complete
///    pre-judgment RECORD, `at(.exit)` the admitted feed).
///
/// A vetoed message still appears at `.entry` (replay / ring buffer /
/// debug) but never reaches state or `.exit` — "control without dirtying".
final class Ledger implements LedgerRows {
  Ledger() {
    // Every record message enters the FIRST segment of the queue; guards
    // forward (or drop, or rewrite) between segments; the last segment
    // forwards into [_posted] — the `.exit` position.
    _tail = _segment(_journal);
    _plumbTailToPosted();
  }

  /// The complete, ungated record — the `.entry` position.
  final Bus _journal = Bus();

  /// The end of the queue — what survived EVERY guard: the `.exit`
  /// position. Effects tap it, so nothing fires on a dropped message.
  final Bus _posted = Bus();

  // ── The queue: segments of stores separated by guards ──
  final List<Bus> _segments = [];
  late Bus _tail;
  StreamSubscription<Object?>? _tailForward;

  /// A new segment fed by [source] (verbatim forward).
  Bus _segment(Bus source) {
    final seg = Bus();
    _forwards
        .add(source.spine<Msg>().listen(seg.dispatch));
    _segments.add(seg);
    return seg;
  }

  void _plumbTailToPosted() {
    _tailForward?.cancel();
    _tailForward =
        _tail.spine<Msg>().listen(_posted.dispatch);
  }

  final List<StreamSubscription<Object?>> _forwards = [];
  final List<void Function()> _disposers = []; // dispose the stores `close` owns

  /// The GRAPH form: a ledger from a single [Regent] — a graph splices its
  /// rows (and its nested graphs') in order and its merges auto-wire; a
  /// plain regent is the one-row ledger (`Ledger.root(const NavUnit())`).
  static Ledger root(Regent root) {
    final ledger = Ledger().._mountRoot(root);
    return ledger;
  }

  void _mountRoot(Regent root) {
    root.mount(this);
    _applyMerges();
  }

  // ── Graph splicing ──────────────────────────────────────────────────────
  final Set<Regency> _graphsSeen = Set.identity();
  final List<AnyProjection> _pendingMerges = [];

  @override
  void graph(covariant Regency spec) {
    if (!_graphsSeen.add(spec)) {
      throw StateError(
          'the identical ${spec.runtimeType} graph appears twice — const '
          'canonicalization makes them one graft; a segment may be spliced '
          'only once.');
    }
    for (final row in spec.rows) {
      row.mount(this);
    }
    _pendingMerges.addAll(spec.merges);
  }

  /// Wire the collected projection edges — after every row is mounted, so
  /// endpoints resolve by regent identity across the whole flattened tree.
  void _applyMerges() {
    for (final p in _pendingMerges) {
      final (target, source) = switch (p) {
        final Projection e => (e.target, e.source),
        final UnitProjection e => (e.target, e.source),
        _ => throw StateError('unknown projection kind ${p.runtimeType}'),
      };
      if (target == null || source == null) {
        throw StateError(
            '${p.runtimeType} sits in a graph\'s merges set but carries no '
            'endpoints — pass them through the ctor: '
            '`: super(TargetSpec(), SourceSpec())`.');
      }
      final tMem = _specMemories[target] ??
          (throw StateError(
              '${p.runtimeType}: its target ${target.runtimeType} is not a '
              'row of this graph.'));
      final sMem = _specMemories[source] ??
          (throw StateError(
              '${p.runtimeType}: its source ${source.runtimeType} is not a '
              'row of this graph.'));
      switch ((tMem, sMem, p)) {
        case (final StoreMemory t, final StoreMemory s, Projection()):
          (t as dynamic).mergeStore(s, p);
        case (final StoreMemory t, final UnitMemory s, Projection()):
          (t as dynamic).merge(s, p);
        case (final UnitMemory t, final UnitMemory s, UnitProjection()):
          (t as dynamic).merge(s, p);
        default:
          throw StateError(
              '${p.runtimeType}: a ${tMem.runtimeType} target cannot read '
              'from a ${sMem.runtimeType} source with this projection kind.');
      }
    }
    _pendingMerges.clear();
  }

  /// THE POSITION DOOR: the queue at [position], as its typed handle — the
  /// spec instance carries the handle type, so nothing untyped comes back.
  ///
  ///  * a STORE row → its `StoreMemory` (`at(const Products())[id]`)
  ///  * a UNIT row → its `UnitMemory` (`at(const Viewer()).state`)
  ///  * a GUARD row → its `GuardMemory` (`at(const CachedGate()).dropped`)
  ///  * `.entry` → the RECORD's [Feed] (`at(.entry).msgs<Msg>()`)
  ///  * `.exit` → the ADMITTED [Feed] (`at(.exit).msgs<OrderPlaced>()`)
  ///
  /// Row lookup is by IDENTITY: spell the row's constructor expression with
  /// `const`. Throws when no row holds the instance.
  Handle at<Handle>(At<Handle> position) => switch (position) {
        EntryPosition() => Feed(_journal) as Handle,
        ExitPosition() => Feed(_posted) as Handle,
        _ => (_specMemories[position] ?? (throw _noRow(position))) as Handle,
      };

  StateError _noRow(Object spec) => StateError(
      'no row holds this ${spec.runtimeType} instance — the lookup is by '
      'IDENTITY: match the row\'s constructor args exactly, and spell '
      '`const` (a non-const expression is a fresh instance).');

  /// Every enrolled regent's BASE state, keyed by spec instance — plain
  /// collections so `equals`/`isNot` compare structurally (the replay
  /// snapshot). Fold truth only: merge edges are read-time and stay out,
  /// so a dock's promise or a shadow's answer never leaks into a law.
  Map<Object, Object?> snapshot() => {
        for (final e in _specMemories.entries)
          e.key: switch (e.value) {
            final StoreMemory m => {...m.folded},
            final UnitMemory m => m.folded,
            _ => null,
          },
      };

  // ── Regent-identity state lookup (guards judge through it) ──

  // Memories keyed by their spec INSTANCE. Const canonicalization makes the
  // constructor expression the regent's name; registration rejects a
  // duplicate identical instance, so the lookup is total and unambiguous.
  final Map<Object, Object> _specMemories = Map.identity();

  // This ledger's own CONFIRMED state by regent identity — what every
  // guard row judges through (the injected [ReadStore]): base truth only,
  // no optimistic overlays, no merge edges, so a judge never rules on a
  // prediction that hasn't been acknowledged. The public spelling is
  // `at(spec).folded`.
  S _read<S>(AnyStore<S> spec) {
    final memory = _specMemories[spec] ?? (throw _noRow(spec));
    return switch (memory) {
      final StoreMemory m => m.folded as S,
      final UnitMemory m => m.folded as S,
      _ => throw StateError('unreadable memory for ${spec.runtimeType}'),
    };
  }

  void _enroll(Object spec, Object memory) {
    if (_specMemories.containsKey(spec)) {
      throw StateError(
          'two rows hold the identical ${spec.runtimeType} instance — const '
          'canonicalization makes them one regent. Differ the args or '
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
    final mem = GuardMemory<M>();
    _enroll(spec, mem);
    _disposers.add(mem.dispose);
    final source = _tail;
    final seg = Bus();
    _forwards.add(source.spine<Msg>().listen((msg) {
      if (msg is! M) {
        seg.dispatch(msg);
        return;
      }
      // The verdict: forwards continue THIS round below (empty = drop, one =
      // pass/rewrite, many = fan-out, in set order); mints queue as NEW
      // rounds from index 0 after this round completes. The record keeps
      // only the original.
      final verdict = spec.judge(msg, _read);
      for (final j in verdict) {
        switch (j) {
          case ForwardJudgment(:final msg):
            seg.dispatch(msg);
          case MintJudgment(:final msg):
            _mints.add((msg, _depth + 1));
        }
      }
      mem.add(GuardEvent(msg: msg, verdict: verdict));
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
    _forwards.add(source.spine<Msg>().listen((msg) {
      if (msg is M && test(msg)) return;
      seg.dispatch(msg);
    }));
    _segments.add(seg);
    _tail = seg;
    _plumbTailToPosted();
  }

  // ── Minted rounds: derived facts re-entering at index 0 ────────────────
  // Collected during a round (guards may not dispatch mid-traversal), run
  // FIFO after the round completes — before anything external can
  // interleave. Unjournaled: a mint is a pure derivation of the fold, so
  // replay re-derives it from the source fact.
  final List<(Msg, int)> _mints = [];
  int _depth = 0;
  bool _draining = false;

  /// A mint chain deeper than this is sequencing wearing a derivation's
  /// clothes — a design diagnosis, thrown at development time.
  static const mintDepthBudget = 8;

  void _drainMints() {
    if (_draining) return; // the outermost frame owns the drain
    _draining = true;
    try {
      while (_mints.isNotEmpty) {
        final (msg, depth) = _mints.removeAt(0);
        if (depth > mintDepthBudget) {
          throw StateError(
              'mint chain exceeded depth $mintDepthBudget ($msg) — a mint is '
              'a DERIVATION the fold already implies, never a sequence step; '
              'sequencing over time belongs to effects.');
        }
        _depth = depth;
        // Index 0 = the first segment: the full queue, skipping the journal.
        _segments.first.dispatch(msg);
      }
    } finally {
      _depth = 0;
      _draining = false;
    }
  }

  /// THE WRITE DOOR: push a message onto the record (it then posts through
  /// the guards); minted rounds run after it, before anything else can
  /// interleave.
  void dispatch(Msg msg) {
    _journal.dispatch(msg);
    _drainMints();
  }

  /// A live store for [spec], standing at the CURRENT row: it folds
  /// whatever survives the guards declared above it.
  @override
  StoreMemory<K, E, M> store<K, E extends Identifiable<K>, M extends Msg>(
      Store<K, E, M> spec) {
    final mem = StoreMemory<K, E, M>(spec, _tail);
    _enroll(spec, mem);
    _disposers.add(mem.dispose);
    return mem;
  }

  /// A live UNIT store for [spec] (cardinality one, keyless facts).
  @override
  UnitMemory<S, M> unit<S, M extends Msg>(Unit<S, M> spec) {
    final mem = UnitMemory<S, M>(spec, _tail);
    _enroll(spec, mem);
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
    _journal.close();
    for (final b in _segments) {
      b.close();
    }
    _posted.close();
  }
}
