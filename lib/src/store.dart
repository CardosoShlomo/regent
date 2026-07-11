import 'dart:async';

import 'package:identifiable/identifiable.dart';
import 'package:meta/meta.dart';

import 'msg.dart';
import 'pure.dart';

/// What a `@stores` row may hold: a keyed [Store] or a [Unit]. [S] is the
/// state a `read` of the regent returns — the keyed collection for a store,
/// the value for a unit — so one typed lookup serves both kinds.
abstract interface class AnyStore<S> {}

/// A POSITION in the queue that answers `ledger.at(...)` with its typed
/// [Handle] — the spec instance carries the handle type, so the lookup is
/// fully typed with no name in between. Every regent kind is a position
/// (store → `StoreMemory`, unit → `UnitMemory`, guard → `GuardMemory`), and
/// the two positions nobody declares are the static sentinels:
///
/// ```dart
/// ledger.at(const Products())[id];        // a row's live memory
/// ledger.at(.entry).msg<Msg>();           // index −1: the RECORD
/// ledger.at(.exit).msg<OrderPlaced>();    // index n+1: the ADMITTED feed
/// ```
///
/// OBSERVE on `.exit`, RECORD on `.entry`: everything enters (the record is
/// complete — replay, persistence, transport mirrors tap it), only what
/// survived every judge exits (effects tap it, so nothing fires on a
/// dropped message; minted facts appear here, provenance-blind).
abstract interface class At<Handle> {
  /// Index −1: every fact as dispatched, before any judge.
  static const entry = EntryPosition();

  /// Index n+1: what survived every guard — a dropped fact never exits.
  static const exit = ExitPosition();
}

/// The sentinel for the queue's ingress — see [At.entry].
final class EntryPosition implements At<Feed> {
  const EntryPosition();
}

/// The sentinel for the queue's end — see [At.exit].
final class ExitPosition implements At<Feed> {
  const ExitPosition();
}

/// The stream-only face of a sentinel position: typed message taps, no
/// dispatch — nobody injects mid-queue.
final class Feed {
  const Feed(this._bus);

  final Bus _bus;

  /// The [M]-typed messages passing this position (plural = a stream).
  Stream<M> msgs<M extends Msg>() => _bus.on<M>();
}

/// The common face of [Projection] and [UnitProjection] — what a
/// `Regency.merges` set holds.
abstract interface class AnyProjection {}

/// A guard's view of the world: this ledger's own state, looked up by
/// regent IDENTITY — `read(const BrowseDeck())`, `read(const AuthMachine())`.
/// Const canonicalization makes the constructor expression the regent's
/// canonical NAME: `const X()` written in a judge IS the instance the row
/// holds (same class, different args = a different regent; two rows may not
/// hold identical instances — enforced at registration). Bound to the ledger
/// the guard stands in, so a replayed ledger reads itself. Throws when no
/// row holds the instance (wrong args, or a missing `const`).
typedef ReadStore = S Function<S>(AnyStore<S> spec);

/// A REGENT — a row of the ledger — anything that occupies a row of the regents
/// enum: stores, units, guards, vetoes. Row order is traversal order: a
/// message walks the rows top to bottom.
///
/// One order, two OPPOSITE relationships to the flow:
///
///  * A STORE row is a pure READER standing at its place in the queue — it
///    folds what passes and can never touch the message. What it sees is
///    whatever survived the guards ABOVE its row.
///  * A GUARD row is a pure JUDGE of the flow itself — it folds nothing and
///    holds no state, but decides what the rows BELOW it see: pass, drop,
///    or rewrite.
///
/// So placement means different things: moving a store changes what IT
/// sees; moving a guard changes what EVERYONE below it sees.
@immutable
abstract base class Regent {
  const Regent();

  /// Registers this regent at the ledger's current row with its OWN type
  /// arguments intact (double dispatch — a type-erased switch would fold
  /// every message into every store). Returns the live memory (stores,
  /// units) or null (guards). [Ledger.of] drives it; consumers register via
  /// `Ledger.of(rows)` or `ledger.store/unit/guard(spec)`.
  @internal
  Object? mount(LedgerRows ledger);
}

/// The registration face [Regent.mount] dispatches into — [Ledger]
/// implements it; the indirection keeps the regent tiers free of the
/// ledger's own import.
abstract interface class LedgerRows {
  StoreMemory<K, E, M> store<K, E extends Identifiable<K>, M extends Msg>(
      Store<K, E, M> spec);
  UnitMemory<S, M> unit<S, M extends Msg>(Unit<S, M> spec);
  void guard<M extends Msg>(covariant Object spec);

  /// Splice a graph's rows at the current position and collect its merges.
  void graph(covariant Object spec);
}


/// One fold's full story, emitted by a store AFTER the reduce ran: the cause
/// and its consequence, atomically — an effect filtering these can never race
/// the fold. Filters recover every narrower feed: `structural` (the list
/// shell), `changed.contains(id)` (per key), a before/after delta (state
/// TRANSITIONS), a msg-type check (post-fold message observation).
@immutable
final class StoreEvent<K, E extends Identifiable<K>, M extends Msg> {
  const StoreEvent({
    required this.msg,
    required this.before,
    required this.after,
    required this.changed,
    required this.structural,
  });

  final M msg;
  final IdentifiableMap<K, E> before;
  final IdentifiableMap<K, E> after;
  final Set<K> changed;
  final bool structural;
}

/// A READ RESOLVER for a merge edge (`user.merge(viewer, const
/// ViewerSupportsUser())` in the entities graph): the SOURCE store's state
/// answers the TARGET surface's per-key reads at the source's OWN identity —
/// `S extends Identifiable<K>` IS the claim; there is no key method anywhere.
///
/// The id comparison lives in the engine — never in consumer code and never
/// in [resolve]'s body: [resolve] runs only when the read matches
/// `source.id`, so it merges unconditionally. The edge is skipped while the
/// source state is absent; [row] is the target's own row (null on a cold
/// store — the projection still answers, which is how a self read works
/// before anyone loaded the crowd row). Edges compose in declaration order.
///
/// Scope: per-key surfaces only (`store[id]`, `store(id)`, consume, the UI
/// layer's `.of`/EntityScope). `entities`/`values` stay honest rows — a
/// projection never appears in collection iteration, and reduces never see it.
@immutable
abstract base class Projection<S extends Identifiable<K>, K, E>
    implements AnyProjection {
  /// The projection IS the edge: [target] reads-from [source] through
  /// [resolve]. Endpoints are const fields set through the subclass ctor
  /// (`: super(const Todos(), const LocalTodos())` — a const initializer
  /// list needs the keyword spelled, and it canonicalizes), which is
  /// what lets a [Regency] take bare projection instances as its
  /// `merges` set. Null endpoints = call-site wiring (`merge`/`mergeStore`
  /// name them directly).
  const Projection([this.target, this.source]);

  final AnyStore<Object?>? target;
  final AnyStore<Object?>? source;

  /// The answer at the source's own key — called only when the read matches.
  E resolve(E? row, S source);
}

/// The UNIT form of [Projection] — a unit-target merge edge
/// (`viewer.from(viewerPending, const ApplyPending())` in the regents
/// merges set): the SOURCE unit's state answers the TARGET unit's read.
/// Keyless — a unit has cardinality one, so the edge always applies;
/// [resolve] no-ops itself when the source carries nothing. Read-time only:
/// the fold and guards' `read` never see it.
@immutable
abstract base class UnitProjection<S, T> implements AnyProjection {
  /// See [Projection] — the unit form carries its endpoints the same way.
  const UnitProjection([this.target, this.source]);

  final AnyStore<Object?>? target;
  final AnyStore<Object?>? source;

  /// The effective value: the target's own [value] resolved through
  /// [source].
  T resolve(T value, S source);
}

/// The unit form of [StoreEvent].
@immutable
final class UnitEvent<S, M extends Msg> {
  const UnitEvent({required this.msg, required this.before, required this.after});

  final M msg;
  final S before;
  final S after;
}

/// The message bus — the RICH tier's transport. Dispatch messages through
/// guards to typed subscribers. Transport-agnostic: feed it from WS, HTTP, a
/// local DB, or a local optimistic `dispatch(..., optimistic: true)`.
/// Decoupled from canon and from Flutter; a [StoreMemory] subscribes to it,
/// and a riverpod notifier can subscribe via [on] too — neither owns the other.
class Bus {
  // The SPINE: synchronous delivery that runs the traversal (folds). Internal —
  // memories subscribe here so state is settled when dispatch returns.
  final StreamController<Msg> _spine =
      StreamController<Msg>.broadcast(sync: true);
  // The TAPS: async delivery for all observation (effects, [on]). The event
  // loop is the deferral queue — listeners run after the traversal, each
  // seeing a consistent cut; their dispatches enter like any other.
  final StreamController<Msg> _taps = StreamController<Msg>.broadcast();
  bool _firing = false;

  /// Push a message through the bus.
  void dispatch(Msg msg) {
    // Purity is enforced, not accommodated: nothing inside a traversal may
    // dispatch (reduces are pure; observers deliver async, after). Guards
    // live in the LEDGER's queue, between segments — a bus is one segment.
    assert(!_firing,
        'dispatch during a traversal — guards and reduces must be pure');
    _firing = true;
    try {
      _spine.add(msg);
    } finally {
      _firing = false;
    }
    _taps.add(msg);
  }

  /// The [M]-typed feed as a STREAM — composable (`where`/`asyncMap`), and
  /// `await for`-able: a worker gets pull semantics with natural backpressure
  /// (pause the subscription, the feed waits). `.listen(handler)` for the
  /// callback style.
  Stream<M> on<M extends Msg>() =>
      _taps.stream.where((m) => m is M).cast<M>();

  /// The synchronous spine — memories fold on it so state is settled when
  /// dispatch returns. Observation belongs on [on].
  @internal
  Stream<M> spine<M extends Msg>() =>
      _spine.stream.where((m) => m is M).cast<M>();

  void close() {
    _spine.close();
    _taps.close();
  }
}

/// The PURE, const registry descriptor: how a message folds into an entry's
/// state. No mutable state, no `ref`, const — so it can sit in a spec. The live
/// store ([StoreMemory]) is created separately and wired to a [Bus].
@immutable
abstract base class Store<K, E extends Identifiable<K>, M extends Msg>
    extends Regent
    implements
        AnyStore<IdentifiableMap<K, E>>,
        At<StoreMemory<K, E, M>> {
  const Store([this.initial = const {}]);

  /// The collection before any fact has arrived — empty unless seeded.
  final IdentifiableMap<K, E> initial;

  /// Fold a message into the registry's keyed collection and return the NEXT
  /// collection. PURE — replay depends on it; no side effects, no clocks.
  /// A message may touch MANY entries (a batch load) or none. The
  /// `identifiable` map extensions keep it terse:
  /// `entities.upsert(x)` · `entities.upsertAll(xs)` · `entities.removeById(id)`
  /// · `entities.updateById(id, (cur) => …)`.
  @pure
  IdentifiableMap<K, E> reduce(IdentifiableMap<K, E> entities, M msg);

  @override
  StoreMemory<K, E, M> mount(LedgerRows ledger) => ledger.store(this);
}

/// The UNIT sibling of [Store]: one value, cardinality one — for entities
/// whose identity is the session (the wire sends their facts KEYLESS: a
/// viewer profile, a requests+unseen state). Same purity contract.
@immutable
abstract base class Unit<S, M extends Msg> extends Regent
    implements
        AnyStore<S>,
        At<UnitMemory<S, M>> {
  const Unit(this.initial);

  /// The value before any fact has arrived.
  final S initial;

  /// Fold a message into the value and return the NEXT value. PURE.
  @pure
  S reduce(S state, M msg);

  @override
  UnitMemory<S, M> mount(LedgerRows ledger) => ledger.unit(this);
}

/// The live memory for a [Unit]: the value driven off a [Bus].
class UnitMemory<S, M extends Msg> {
  UnitMemory(this._spec, Bus bus) : _base = _spec.initial {
    _sub = bus.spine<M>().listen(_apply);
  }

  final Unit<S, M> _spec;
  S _base; // the fold's truth — the ONLY state this memory holds

  /// The folded value — what a guard's `read` returns.
  S get folded => _base;

  void _apply(M msg) {
    final before = _base;
    _base = _spec.reduce(_base, msg);
    if (!identical(_base, before)) _changes.add(null);
    _events.add(UnitEvent(msg: msg, before: before, after: _base));
  }

  final StreamController<void> _changes = StreamController<void>.broadcast();
  final StreamController<UnitEvent<S, M>> _events =
      StreamController<UnitEvent<S, M>>.broadcast();
  late final StreamSubscription<Object?> _sub;

  // ── Merge edges (read resolvers), unit form ───────────────────────────
  final List<S Function(S)> _merges = [];
  final List<StreamSubscription<void>> _mergeSubs = [];

  /// Wire a merge edge: [source]'s value answers this unit's read through
  /// [projection] — declaration order = resolution order. Read-time only:
  /// [base] and the fold never see it.
  void merge<S2, M2 extends Msg>(
      UnitMemory<S2, M2> source, UnitProjection<S2, S> projection) {
    _merges.add((v) => projection.resolve(v, source.state));
    _mergeSubs.add(source.changes.listen((_) => _changes.add(null)));
  }

  /// The state, now — the fold's truth resolved through the merge edges
  /// (the dock's promise answers here; [folded] is the unmerged reading).
  S get state {
    var v = _base;
    for (final m in _merges) {
      v = m(v);
    }
    return v;
  }

  /// Fires on every value change.
  Stream<void> get changes => _changes.stream;

  /// The fold's full story, post-reduce — one event per delivered family
  /// message (a no-op fold still emits: msg-type filters see the family
  /// completely). Transition listeners filter on a before/after delta.
  /// The PRIMITIVE the branches below derive from — atomic, so nothing
  /// races the fold.
  Stream<UnitEvent<S, M>> get events => _events.stream;

  /// The [T]-typed family messages as delivered at this row.
  Stream<T> msgs<T extends M>() =>
      events.where((e) => e.msg is T).map((e) => e.msg as T);

  /// The post-fold values, one per delivery.
  Stream<S> get states => events.map((e) => e.after);

  /// The pre-fold values, one per delivery — pair with [states] for
  /// transition logic without racing the fold.
  Stream<S> get statesBefore => events.map((e) => e.before);

  void dispose() {
    _sub.cancel();
    for (final s in _mergeSubs) {
      s.cancel();
    }
    _changes.close();
    _events.close();
  }
}

/// One wired merge edge, type-erased for heterogeneous sources: [claim]
/// answers (claimed key, source state) or null while the source is absent.
class _MergeEdge<K, E> {
  _MergeEdge(this.claimAt, this.resolve);
  final Object? Function(K key) claimAt;
  final E Function(E? row, Object source) resolve;
}

/// The live store for a [Store]: the folded collection driven off a [Bus],
/// plus read-time merge edges and the change/event feeds. It holds NO other
/// state — optimism, in-flight status, freshness, and settlement all live in
/// consumer ROWS (docks, in-flight units, coverage), where they replay.
class StoreMemory<K, E extends Identifiable<K>, M extends Msg> {
  StoreMemory(this._reg, Bus bus) {
    _sub = bus.spine<M>().listen(_apply);
  }

  final Store<K, E, M> _reg;
  late IdentifiableMap<K, E> _base = _reg.initial;

  /// The folded collection — the ONLY state this memory holds; no merge
  /// edges. What a guard's `read` returns.
  IdentifiableMap<K, E> get folded => _base;
  final StreamController<K> _changes = StreamController<K>.broadcast();
  final StreamController<void> _structure =
      StreamController<void>.broadcast();
  final StreamController<StoreEvent<K, E, M>> _events =
      StreamController<StoreEvent<K, E, M>>.broadcast();
  late final StreamSubscription<Object?> _sub;

  Set<K> _diff(IdentifiableMap<K, E> a, IdentifiableMap<K, E> b) => {
        for (final k in {...a.keys, ...b.keys})
          if (!identical(a[k], b[k])) k
      };

  bool _sameKeys(IdentifiableMap<K, E> a, IdentifiableMap<K, E> b) {
    if (a.length != b.length) return false;
    final ia = a.keys.iterator, ib = b.keys.iterator;
    while (ia.moveNext() && ib.moveNext()) {
      if (ia.current != ib.current) return false;
    }
    return true;
  }

  void _apply(M msg) {
    final before = _base;
    _base = _reg.reduce(before, msg);
    // Change signals decided ONCE here, where both maps are in hand, so no
    // listener ever diffs: per changed key, plus [structure] when the key
    // sequence itself moved.
    final touched = _diff(before, _base);
    for (final k in touched) {
      _changes.add(k);
    }
    if (!_sameKeys(before, _base)) _structure.add(null);
    // ONE event per delivered family message — even a no-op fold emits, so
    // a msg-type filter is a complete post-fold observation of the family.
    _events.add(StoreEvent(
      msg: msg,
      before: before,
      after: _base,
      changed: touched,
      structural: !_sameKeys(before, _base),
    ));
  }

  /// The fold's full story, post-reduce: (cause, consequence) atomically —
  /// the PRIMITIVE the branches below derive from (filters recover every
  /// narrower feed without racing the fold).
  Stream<StoreEvent<K, E, M>> get events => _events.stream;

  /// The [T]-typed family messages as delivered at this row.
  Stream<T> msgs<T extends M>() =>
      events.where((e) => e.msg is T).map((e) => e.msg as T);

  /// The post-fold collections, one per delivery.
  Stream<IdentifiableMap<K, E>> get states => events.map((e) => e.after);

  /// The pre-fold collections, one per delivery.
  Stream<IdentifiableMap<K, E>> get statesBefore =>
      events.map((e) => e.before);

  // ── Merge edges (read resolvers) ──────────────────────────────────────
  // `user.merge(viewer, projection)`: per-key reads consult each edge's
  // source in declaration order. Collection reads (entities/values) and the
  // fold never see projections.
  final List<_MergeEdge<K, E>> _merges = [];
  final List<StreamSubscription<void>> _mergeSubs = [];

  /// Wire a merge edge: [source]'s state answers this store's per-key reads
  /// through [projection], at the source's own [Identifiable] id. The edge is
  /// skipped while the source state is null. Declaration order = resolution
  /// order (later edges see earlier answers).
  void merge<S extends Identifiable<K>>(
      UnitMemory<S?, Msg> source, Projection<S, K, E> projection) {
    _merges.add(_MergeEdge<K, E>(
      (k) {
        final s = source.state;
        return s != null && s.id == k ? s : null;
      },
      (row, s) => projection.resolve(row, s as S),
    ));
    // Surgical reactivity: a source change moves exactly the claimed keys —
    // the previous claim (released) and the current one (answered anew).
    var last = source.state?.id;
    _mergeSubs.add(source.changes.listen((_) {
      final prev = last;
      final now = source.state?.id;
      last = now;
      if (prev != null && prev != now) _changes.add(prev);
      if (now != null) _changes.add(now);
    }));
  }

  /// Like [merge], with a whole KEYED STORE as the source: the source
  /// answers this store's per-key reads at every key it holds — the
  /// local/offline store shadowing the live one. The source's own merges
  /// apply (chains compose); the projection decides precedence per key
  /// (main-wins = `row ?? local`).
  ///
  /// Unlike unit edges, a store source ALSO joins the COLLECTION reads:
  /// [entities]/[values] union in the source's extra keys (own keys first,
  /// then source-only keys in the source's order), and [structure] fires
  /// when the union's shape moves. A unit projection is a synthetic answer
  /// at one key and stays out of iteration; a store source holds real rows.
  void mergeStore<S extends Identifiable<K>>(
      StoreMemory<K, S, Msg> source, Projection<S, K, E> projection) {
    _merges.add(_MergeEdge<K, E>(
      (k) => source[k],
      (row, s) => projection.resolve(row, s as S),
    ));
    _storeSources.add(source);
    // A source key moved → exactly that key's read may resolve differently.
    _mergeSubs.add(source.changes.listen(_changes.add));
    // Source membership moved → the union's shape may have moved.
    _mergeSubs.add(source.structure.listen(_structure.add));
  }

  /// Store-source edges, kept for the collection union.
  final List<StoreMemory<K, Identifiable<K>, Msg>> _storeSources = [];

  /// Own keys, then each store source's EXTRA keys in its order.
  Iterable<K> get _unionKeys sync* {
    yield* _base.keys;
    for (final src in _storeSources) {
      for (final k in src._unionKeys) {
        if (!_base.containsKey(k)) yield k;
      }
    }
  }

  E? _resolved(K key, E? row) {
    var value = row;
    for (final m in _merges) {
      final s = m.claimAt(key);
      if (s == null) continue;
      value = m.resolve(value, s);
    }
    return value;
  }

  /// The keyed collection — the fold's truth unioned with any STORE
  /// sources' extra keys, resolved through the edges. Unit projections stay
  /// out of iteration.
  IdentifiableMap<K, E> get entities => _storeSources.isEmpty
      ? _base
      : {for (final k in _unionKeys) k: _resolved(k, _base[k]) as E};

  /// The value at [key], resolved through the merge edges — this is what
  /// canon reads by nav id.
  E? operator [](K key) => _resolved(key, _base[key]);

  /// The key SEQUENCE, resolved (own keys first, then store-source extras) —
  /// the synchronous twin of the reactive `of(context)` read.
  List<K> get ids =>
      _storeSources.isEmpty ? [..._base.keys] : [..._unionKeys];

  /// All entries, unioned with store-source extras (see [entities]).
  Iterable<E> get values => _storeSources.isEmpty
      ? _base.values
      : [for (final k in _unionKeys) _resolved(k, _base[k]) as E];

  /// Keys whose value changed — surgical, per key.
  Stream<K> get changes => _changes.stream;

  /// Fires when the key SEQUENCE changed (add / remove / reorder) — the
  /// list-shape feed. Value-only changes never fire here: a list watching this
  /// rebuilds exactly on membership/order, with no diffing downstream.
  Stream<void> get structure => _structure.stream;

  void dispose() {
    _sub.cancel();
    for (final s in _mergeSubs) {
      s.cancel();
    }
    _changes.close();
    _events.close();
  }
}

