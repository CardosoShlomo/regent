import 'dart:async';

import 'package:identifiable/identifiable.dart';
import 'package:meta/meta.dart';

import 'envelope.dart';
import 'msg.dart';
import 'pure.dart';

/// Marks the CITIZENS enum canon's generator reads: each row holds a
/// [Regent] — a store, a unit, a guard, or a veto — and ROW ORDER IS
/// TRAVERSAL ORDER. The rows share one order but act OPPOSITELY: store rows
/// are readers (they fold what passes, never touching it — what they see is
/// what survived the guards above them); guard rows are judges (stateless,
/// fold nothing, decide what every row below sees: pass, drop, rewrite).
/// Merge edges live in the enum's static `merges` set
/// (`users.from(viewer, const ViewerSupportsUser())`) and connect reader
/// rows: store targets take store or unit sources; a unit target takes a
/// unit source. Everything else (key node, key type, tree machinery, screen
/// associations) derives from the `@entities` graph via each store's entity
/// type `E`.
class Regents {
  const Regents();
}

/// The arg-less default.
const regents = Regents();

/// The contract the `@regents` enum wears: a row is a held [Regent]
/// instance, nothing more (`ads(Ads())`, `cachedChatsGate(CachedChatsGate())`).
mixin RegentNode<Self extends RegentNode<Self>> on Enum {
  Regent get regent;

  /// A MERGE EDGE for the enum's static `merges` set: this row's store
  /// reads-from [source]'s rows through [projection]
  /// (`users.from(viewer, const ViewerSupportsUser())`). Chainable —
  /// resolution in declaration order. STORE rows only, both ends (the
  /// generator enforces it).
  RegentMerge<Self> from(Self source, Object projection) =>
      RegentMerge<Self>(this as Self, [(source, projection)]);
}

/// A target row's collected merge edges — what [RegentNode.from] builds.
class RegentMerge<Self extends RegentNode<Self>> {
  const RegentMerge(this.target, this.edges);

  final Self target;
  final List<(Self, Object)> edges;

  /// Chain another source into the same target.
  RegentMerge<Self> from(Self source, Object projection) =>
      RegentMerge<Self>(target, [...edges, (source, projection)]);
}

/// What a `@stores` row may hold: a keyed [Store] or a [Unit]. [S] is the
/// state a `read` of the citizen returns — the keyed collection for a store,
/// the value for a unit — so one typed lookup serves both kinds.
abstract interface class AnyStore<S> {}

/// A guard's view of the world: this ledger's own state, looked up by
/// citizen IDENTITY — `read(const BrowseDeck())`, `read(const AuthMachine())`.
/// Const canonicalization makes the constructor expression the citizen's
/// canonical NAME: `const X()` written in a judge IS the instance the row
/// holds (same class, different args = a different citizen; two rows may not
/// hold identical instances — enforced at registration). Bound to the ledger
/// the guard stands in, so a replayed ledger reads itself. Throws when no
/// row holds the instance (wrong args, or a missing `const`).
typedef ReadStore = S Function<S>(AnyStore<S> spec);

/// A CITIZEN of the ledger — anything that occupies a row of the regents
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

  /// Registers this citizen at the ledger's current row with its OWN type
  /// arguments intact (double dispatch — a type-erased switch would fold
  /// every message into every store). Returns the live memory (stores,
  /// units) or null (guards). [Ledger.of] drives it; consumers register via
  /// `Ledger.of(rows)` or `ledger.store/unit/guard(spec)`.
  @internal
  Object? mount(LedgerRows ledger);
}

/// The registration face [Regent.mount] dispatches into — [Ledger]
/// implements it; the indirection keeps the citizen tiers free of the
/// ledger's own import.
abstract interface class LedgerRows {
  StoreMemory<K, E, M> store<K, E extends Identifiable<K>, M extends Msg>(
      Store<K, E, M> spec);
  UnitMemory<S, M> unit<S, M extends Msg>(Unit<S, M> spec);
  void guard<M extends Msg>(covariant Object spec);
}


/// A PURE interceptor in the dispatch pipeline: inspect/transform an envelope,
/// One fold's full story, emitted by a store AFTER the reduce ran: the cause
/// and its consequence, atomically — an effect filtering these can never race
/// the fold. Filters recover every narrower feed: `structural` (the list
/// shell), `changed.contains(id)` (per key), a before/after delta (state
/// TRANSITIONS), a msg-type check (post-fold message observation).
@immutable
final class StoreEvent<K, E extends Identifiable<K>, M extends Msg> {
  const StoreEvent({
    required this.msg,
    required this.env,
    required this.before,
    required this.after,
    required this.changed,
    required this.structural,
  });

  final M msg;
  final Envelope env;
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
abstract base class Projection<S extends Identifiable<K>, K, E> {
  const Projection();

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
abstract base class UnitProjection<S, T> {
  const UnitProjection();

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

/// The message bus — the RICH tier's transport. Dispatch envelopes through
/// guards to typed subscribers. Transport-agnostic: feed it from WS, HTTP, a
/// local DB, or a local optimistic `dispatch(..., optimistic: true)`.
/// Decoupled from canon and from Flutter; a [StoreMemory] subscribes to it,
/// and a riverpod notifier can subscribe via [on] too — neither owns the other.
class Bus {
  // The SPINE: synchronous delivery that runs the traversal (folds). Internal —
  // memories subscribe here so state is settled when dispatch returns.
  final StreamController<Envelope> _spine =
      StreamController<Envelope>.broadcast(sync: true);
  // The TAPS: async delivery for all observation (effects, [on]). The event
  // loop is the deferral queue — listeners run after the traversal, each
  // seeing a consistent cut; their dispatches enter like any other.
  final StreamController<Envelope> _taps = StreamController<Envelope>.broadcast();
  bool _firing = false;

  /// Push a message through the bus. `source` tags provenance (defaults to the
  /// common remote/optimistic); `optimistic` is the overlay-routing signal — an
  /// optimistic dispatch flows through the SAME subscribers as a remote one but
  /// lands as a pending overlay.
  void dispatch(Msg msg, {bool optimistic = false, String? correlationId}) {
    // Purity is enforced, not accommodated: nothing inside a traversal may
    // dispatch (reduces are pure; observers deliver async, after). Guards
    // live in the LEDGER's queue, between segments — a bus is one segment.
    assert(!_firing,
        'dispatch during a traversal — guards and reduces must be pure');
    final env =
        Envelope(msg, optimistic: optimistic, correlationId: correlationId);
    _firing = true;
    try {
      _spine.add(env);
    } finally {
      _firing = false;
    }
    _taps.add(env);
  }

  /// The [M]-typed feed as a STREAM — composable (`where`/`asyncMap`), and
  /// `await for`-able: a worker gets pull semantics with natural backpressure
  /// (pause the subscription, the feed waits). `.listen(handler)` for the
  /// callback style.
  Stream<M> on<M extends Msg>() =>
      _taps.stream.where((e) => e.msg is M).map((e) => e.msg as M);

  /// Like [on], but paired with each message's [Envelope] — for the rare
  /// effect that needs provenance/correlation.
  Stream<(M, Envelope)> envelopesOf<M extends Msg>() => _taps.stream
      .where((e) => e.msg is M)
      .map((e) => (e.msg as M, e));

  /// The synchronous spine — memories fold on it so state is settled when
  /// dispatch returns. Observation belongs on [on]/[envelopesOf].
  @internal
  Stream<(M, Envelope)> spine<M extends Msg>() =>
      _spine.stream.where((e) => e.msg is M).map((e) => (e.msg as M, e));

  bool _connected = true;
  final StreamController<bool> _conn = StreamController<bool>.broadcast(sync: true);

  /// The transport's connection state. While connected + subscribed, a registry
  /// is fresh (the server pushes changes); a drop means freshness is no longer
  /// guaranteed — stores flip confirmed entries to `stale` until revalidated.
  bool get connected => _connected;
  Stream<bool> get connection => _conn.stream;

  /// Report transport connection state (the WS adapter calls this). A drop is
  /// the one event that invalidates everything push was keeping fresh.
  void setConnected(bool value) {
    if (value == _connected) return;
    _connected = value;
    _conn.add(value);
  }

  void close() {
    _spine.close();
    _taps.close();
    _conn.close();
  }
}

/// The PURE, const registry descriptor: how a message folds into an entry's
/// state. No mutable state, no `ref`, const — so it can sit in a spec. The live
/// store ([StoreMemory]) is created separately and wired to a [Bus].
@immutable
abstract base class Store<K, E extends Identifiable<K>, M extends Msg>
    extends Regent implements AnyStore<IdentifiableMap<K, E>> {
  const Store({this.initial = const {}, this.awaits});

  /// The collection before any fact has arrived — empty unless seeded.
  final IdentifiableMap<K, E> initial;

  /// The store's correlation twin: names the REQUEST family and carries the
  /// scope-entry ask ([Awaits.surface]). Null when the store has no
  /// requests — and therefore no ask.
  final Awaits<K, E, Msg>? awaits;

  /// Fold a message into the registry's keyed collection and return the NEXT
  /// collection. PURE — replayed on optimistic confirm/rollback, so no side
  /// effects. A message may touch MANY entries (a batch load) or none. The
  /// `identifiable` map extensions keep it terse:
  /// `entities.upsert(x)` · `entities.upsertAll(xs)` · `entities.removeById(id)`
  /// · `entities.updateById(id, (cur) => …)`.
  @pure
  IdentifiableMap<K, E> reduce(IdentifiableMap<K, E> entities, M msg);

  @override
  StoreMemory<K, E, M> mount(LedgerRows ledger) => ledger.store(this);
}

/// The correlation twin of a [Store]: names the request family [R] (kept OUT
/// of the store's reduce family, so reduces never carry dead request arms)
/// and judges the SCOPE-ENTRY ask ([surface]). Holds NO state and drives no
/// machinery — in-flight status is an honest ledger row (a consumer unit
/// folding request facts in and answering facts out), deduped by a guard.
@immutable
abstract class Awaits<K, E, R extends Msg> {
  const Awaits();

  /// Door 2 — the scope-entry ask: called when a screen keyed by the
  /// entity's id node is actually navigated to (never on a render). Return
  /// the request fact to dispatch, or null when [row]'s knowledge suffices.
  /// The return type IS the request family — a foreign fact is unwritable.
  /// [row] is the RAW store state — merge edges never mask fetch-need.
  /// PURE: judge, don't act; duplicate asks are a GUARD's job.
  R? surface(K key, E? row) => null;
}

/// The UNIT sibling of [Store]: one value, cardinality one — for entities
/// whose identity is the session (the wire sends their facts KEYLESS: a
/// viewer profile, a requests+unseen state). Same purity contract.
@immutable
abstract base class Unit<S, M extends Msg> extends Regent
    implements AnyStore<S> {
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
  UnitMemory(this._spec, Bus bus)
      : _base = _spec.initial,
        _eff = _spec.initial {
    _sub = bus.spine<M>().listen((r) => _apply(r.$1, r.$2));
  }

  final Unit<S, M> _spec;
  S _base; // confirmed truth only
  S _eff; // base folded through pending overlays (cache)

  /// The CONFIRMED value — no optimistic overlays. What a guard's `read`
  /// returns.
  S get base => _base;
  final List<_Pending<M>> _pending = []; // ordered optimistic overlays
  bool _reverted = false;

  void _refresh() {
    var v = _base;
    for (final p in _pending) {
      v = _spec.reduce(v, p.msg);
    }
    _eff = v;
  }

  void _apply(M msg, Envelope env) {
    // any reduce-family fact speaks over the settled-optimism flag.
    final cleared = _reverted;
    _reverted = false;
    final before = _eff;
    if (env.optimistic && env.correlationId != null) {
      // manual optimistic overlay (ledger.command); base is NOT touched.
      _pending.add(_Pending(env.correlationId!, msg));
    } else {
      // a confirmed message carrying a pending correlation id CONFIRMS it:
      // drop the overlay; the real effect below replaces it in base.
      final cid = env.correlationId;
      if (cid != null) _pending.removeWhere((p) => p.correlationId == cid);
      _base = _spec.reduce(_base, msg);
    }
    _refresh();
    if (!identical(_eff, before) || cleared) _changes.add(null);
    _events.add(UnitEvent(msg: msg, before: before, after: _eff));
  }

  /// Discard the optimistic overlay(s) for [correlationId] — the prediction
  /// failed. Base is untouched, so superseding writes survive. Emits no
  /// event (no message caused it), only a change. When the value snapped
  /// back, [reverted] holds until the next family fact speaks.
  void rollback(String correlationId) {
    final before = _eff;
    _pending.removeWhere((p) => p.correlationId == correlationId);
    _refresh();
    if (!identical(_eff, before)) {
      _reverted = true;
      _changes.add(null);
    }
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
    _merges.add((v) => projection.resolve(v, source.value));
    _mergeSubs.add(source.changes.listen((_) => _changes.add(null)));
  }

  /// The value, now — base folded through pending overlays, then resolved
  /// through the merge edges.
  S get value {
    var v = _eff;
    for (final m in _merges) {
      v = m(v);
    }
    return v;
  }

  /// True after a rollback snapped the value back to base, until the next
  /// family fact speaks — the unit-tier [Stability.reverted]: render the
  /// failed optimism however you want.
  bool get reverted => _reverted;

  /// Fires on every value change.
  Stream<void> get changes => _changes.stream;

  /// The fold's full story, post-reduce — one event per delivered family
  /// message (a no-op fold still emits: msg-type filters see the family
  /// completely). Transition listeners filter on a before/after delta.
  Stream<UnitEvent<S, M>> get events => _events.stream;

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

/// One in-flight optimistic prediction: the message to re-fold over the base,
/// tagged by the correlation id that will confirm or roll it back. Keyless — a
/// prediction may touch any number of entries, discovered by diffing.
class _Pending<M> {
  _Pending(this.correlationId, this.msg);
  final String correlationId;
  final M msg;
}

/// The live store for a [Store]: a confirmed BASE (`identifiable.Store`) plus
/// a provenance/stability flags sidecar, driven off a [Bus] — and an OPTIMISTIC
/// OVERLAY on top.
///
/// Optimism is modelled as a pending message log, never a base mutation: an
/// `optimistic` dispatch with a `correlationId` is recorded as an overlay; the
/// EFFECTIVE read folds the base through the pending overlays for that key
/// (overlay wins, base stays clean). A remote message carrying that same
/// correlation id CONFIRMS it (drop the overlay, apply the real effect to base);
/// [rollback] discards it. Because predictions never touch base, a rollback
/// after a superseding write keeps the superseding write — see the test.
class StoreMemory<K, E extends Identifiable<K>, M extends Msg> {
  StoreMemory(this._reg, Bus bus) {
    _sub = bus.spine<M>().listen((r) => _apply(r.$1, r.$2));
    // a disconnect loses the push freshness guarantee → confirmed entries stale.
    _connSub = bus.connection.listen((up) {
      if (!up) invalidateAll();
    });
  }

  final Store<K, E, M> _reg;
  late IdentifiableMap<K, E> _base = _reg.initial; // confirmed truth only

  /// The CONFIRMED collection — no optimistic overlays, no merge edges.
  /// What a guard's `read` returns.
  IdentifiableMap<K, E> get base => _base;
  late IdentifiableMap<K, E> _eff = _reg.initial; // base folded through pending overlays (cache)
  final Map<K, Flags> _flags = {};
  final List<_Pending<M>> _pending = []; // ordered optimistic overlays
  final StreamController<K> _changes = StreamController<K>.broadcast();
  final StreamController<void> _structure =
      StreamController<void>.broadcast();
  final StreamController<StoreEvent<K, E, M>> _events =
      StreamController<StoreEvent<K, E, M>>.broadcast();
  late final StreamSubscription<Object?> _sub;
  late final StreamSubscription<bool> _connSub;

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

  /// Recompute the effective map (base folded through every pending message),
  /// emit the keys whose effective value changed (unioned with [extra]), and
  /// signal [structure] when the key sequence itself changed — decided ONCE
  /// here, where both maps are in hand, so no listener ever diffs.
  void _refresh(Set<K> extra) {
    final prev = _eff;
    var m = _base;
    for (final p in _pending) {
      m = _reg.reduce(m, p.msg);
    }
    _eff = m;
    for (final k in {..._diff(prev, m), ...extra}) {
      _changes.add(k);
    }
    if (!_sameKeys(prev, m)) _structure.add(null);
  }

  void _apply(M msg, Envelope env) {
    final prevEff = _eff;
    // optimistic + correlationId → a pending overlay; base is NOT touched.
    if (env.optimistic && env.correlationId != null) {
      _pending.add(_Pending(env.correlationId!, msg));
      _refresh(const {});
      _emit(msg, env, prevEff);
      return;
    }
    // a confirmed/remote message carrying a pending correlation id CONFIRMS it:
    // drop the optimistic overlay; the real effect below replaces it in base.
    final cid = env.correlationId;
    if (cid != null) _pending.removeWhere((p) => p.correlationId == cid);
    final before = _base;
    _base = _reg.reduce(before, msg);
    final touched = _diff(before, _base);
    for (final k in touched) {
      if (_base.containsKey(k)) {
        _flags[k] = const Flags(stability: Stability.confirmed);
      } else {
        _flags.remove(k);
      }
    }
    _refresh(touched);
    _emit(msg, env, prevEff);
  }

  // ONE event per delivered family message — even a no-op fold emits, so a
  // msg-type filter is a complete post-fold observation of the family.
  void _emit(M msg, Envelope env, IdentifiableMap<K, E> prevEff) {
    _events.add(StoreEvent(
      msg: msg,
      env: env,
      before: prevEff,
      after: _eff,
      changed: _diff(prevEff, _eff),
      structural: !_sameKeys(prevEff, _eff),
    ));
  }

  /// The fold's full story, post-reduce: (cause, consequence) atomically —
  /// the ONE stream effects subscribe to (filters recover every narrower
  /// feed). Rollbacks emit no event (no message caused them).
  Stream<StoreEvent<K, E, M>> get events => _events.stream;

  /// Discard the optimistic overlay(s) for [correlationId] — the prediction
  /// failed (timeout/reject). Base is untouched, so any superseding writes that
  /// landed meanwhile survive. Keys whose effective value snapped back are
  /// flagged [Stability.reverted] until the next fold touches them, so a
  /// consumer can render the failure however it wants.
  void rollback(String correlationId) {
    final before = _eff;
    _pending.removeWhere((p) => p.correlationId == correlationId);
    var m = _base;
    for (final p in _pending) {
      m = _reg.reduce(m, p.msg);
    }
    for (final k in _diff(before, m)) {
      _flags[k] = const Flags(stability: Stability.reverted);
    }
    _refresh(const {});
  }

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
        final s = source.value;
        return s != null && s.id == k ? s : null;
      },
      (row, s) => projection.resolve(row, s as S),
    ));
    // Surgical reactivity: a source change moves exactly the claimed keys —
    // the previous claim (released) and the current one (answered anew).
    var last = source.value?.id;
    _mergeSubs.add(source.changes.listen((_) {
      final prev = last;
      final now = source.value?.id;
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

  /// Own effective keys, then each store source's EXTRA keys in its order.
  Iterable<K> get _unionKeys sync* {
    yield* _eff.keys;
    for (final src in _storeSources) {
      for (final k in src._unionKeys) {
        if (!_eff.containsKey(k)) yield k;
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

  /// The EFFECTIVE keyed collection: base folded through the pending
  /// optimistic overlays — unioned with any STORE sources' extra keys,
  /// resolved through the edges. Unit projections stay out of iteration.
  IdentifiableMap<K, E> get entities => _storeSources.isEmpty
      ? _eff
      : {for (final k in _unionKeys) k: _resolved(k, _eff[k]) as E};

  /// The EFFECTIVE value at [key]: confirmed base folded through the pending
  /// optimistic overlays, then through the merge edges — this is what canon
  /// reads by nav id.
  E? operator [](K key) => _resolved(key, _eff[key]);

  /// A keyed HANDLE — `store(id)`: a first-class, passable reference to one
  /// entity slot. `[]` answers "the value, now"; `call` constructs the
  /// reference (read it reactively via the UI layer's `ref.of(context)`).
  EntityRef<K, E, M> call(K id) => EntityRef._(this, id);

  /// The CONFIRMED value at [key] — base only, ignoring overlays.
  E? confirmed(K key) => _base[key];

  /// True when an overlay currently changes [key]'s effective value from base.
  bool _overlaid(K key) => !identical(_eff[key], _base[key]);

  /// Flags at [key]: `pending` while an overlay changes it, else the
  /// confirmed base flags.
  Flags? flagsOf(K key) {
    if (_overlaid(key)) {
      return const Flags(stability: Stability.pending);
    }
    return _flags[key];
  }

  void _setStability(K key, Stability s) {
    _flags[key] = Flags(stability: s);
    _changes.add(key);
  }

  /// Mark a CONFIRMED entry stale (server invalidation, a related change, or a
  /// disconnect). A no-op on an entry that isn't currently confirmed.
  void invalidate(K key) {
    if (_flags[key]?.stability == Stability.confirmed) {
      _setStability(key, Stability.stale);
    }
  }

  /// Invalidate every confirmed entry — what a [Bus] disconnect triggers.
  void invalidateAll() {
    for (final key in _flags.keys.toList()) {
      invalidate(key);
    }
  }

  /// All effective entries — base folded through the optimistic overlays,
  /// unioned with store-source extras (see [entities]).
  Iterable<E> get values => _storeSources.isEmpty
      ? _eff.values
      : [for (final k in _unionKeys) _resolved(k, _eff[k]) as E];

  /// Keys whose EFFECTIVE value changed — base apply, overlay add, confirm, or
  /// rollback. Surgical, per key. (Also fires on flag-only changes; use [consume]
  /// for a value-distinct stream, [watchStatus] for a flag-distinct one.)
  Stream<K> get changes => _changes.stream;

  /// Fires when the key SEQUENCE changed (add / remove / reorder) — the
  /// list-shape feed. Value-only changes never fire here: a list watching this
  /// rebuilds exactly on membership/order, with no diffing downstream.
  Stream<void> get structure => _structure.stream;

  final Map<K, int> _watchers = {}; // active consumers per key (Door 1 refcount)

  void _retain(K key) => _watchers.update(key, (n) => n + 1, ifAbsent: () => 1);

  void _release(K key) {
    final n = (_watchers[key] ?? 1) - 1;
    if (n <= 0) {
      _watchers.remove(key);
    } else {
      _watchers[key] = n;
    }
  }

  /// How many consumers are currently subscribed to [key] (Door 1 refcount).
  int watchers(K key) => _watchers[key] ?? 0;

  /// Door 1 GC: reclaim every CONFIRMED entry no consumer is watching and no
  /// optimistic overlay needs. Call it on memory pressure or a cache-trim tick —
  /// a later [surface] simply refetches anything dropped. Loading/pending and
  /// still-watched entries are kept.
  void gc() {
    var changed = false;
    for (final key in _base.keys.toList()) {
      if (watchers(key) > 0) continue;
      if (_overlaid(key)) continue; // an overlay still needs it
      _base.remove(key);
      _flags.remove(key);
      changed = true;
    }
    if (changed) _refresh(const {});
  }

  /// Door 1: CONSUME [key] — the effective value now, then on every VALUE change
  /// (flag-only flips emit nothing). While a consumer holds this subscription the
  /// entry is RETAINED ([watchers] counts it); when the last one cancels it
  /// becomes [gc]-eligible. Universal: wrap in any framework's stream primitive.
  Stream<E?> consume(K key) {
    late final StreamController<E?> ctrl;
    StreamSubscription<K>? sub;
    E? last;
    ctrl = StreamController<E?>(
      onListen: () {
        _retain(key);
        last = this[key];
        ctrl.add(last);
        sub = changes.listen((k) {
          if (k != key) return;
          final v = this[key];
          if (!identical(v, last)) {
            last = v;
            ctrl.add(v);
          }
        });
      },
      onCancel: () {
        sub?.cancel();
        _release(key);
      },
    );
    return ctrl.stream;
  }

  /// The `(key, #status)` aspect: the flags at [key] now, then on every FLAG
  /// change — value-only changes that leave the flags equal emit nothing.
  Stream<Flags?> watchStatus(K key) {
    late final StreamController<Flags?> ctrl;
    StreamSubscription<K>? sub;
    Flags? last;
    ctrl = StreamController<Flags?>(
      onListen: () {
        last = flagsOf(key);
        ctrl.add(last);
        sub = changes.listen((k) {
          if (k != key) return;
          final f = flagsOf(key);
          if (f != last) {
            last = f;
            ctrl.add(f);
          }
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return ctrl.stream;
  }

  void dispose() {
    _sub.cancel();
    _connSub.cancel();
    for (final s in _mergeSubs) {
      s.cancel();
    }
    _changes.close();
    _events.close();
  }
}

/// A (store, id) reference — one entity slot as a first-class value. Pure:
/// carries no subscription; readers (e.g. canon_flutter's `ref.of(context)`)
/// decide how to observe it.
final class EntityRef<K, E extends Identifiable<K>, M extends Msg> {
  const EntityRef._(this.store, this.id);

  final StoreMemory<K, E, M> store;
  final K id;

  /// The value, now (non-reactive) — same as `store[id]`.
  E? get value => store[id];
}
