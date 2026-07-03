import 'dart:async';

import 'package:identifiable/identifiable.dart';

import 'envelope.dart';
import 'msg.dart';

/// Marks the spec enum canon's generator reads: each row holds a [Store] — the
/// two things no grammar derives: THAT this collection exists, and its reduce.
/// Everything else (key node, key type, tree machinery, screen associations)
/// derives from the `@entities` graph via the store's entity type `E`.
class Stores {
  const Stores();
}

/// The arg-less default.
const stores = Stores();

/// The contract the `@stores` enum wears: a row is a held [Store] instance,
/// nothing more (`ads(Ads())`).
mixin StoreNode<Self extends StoreNode<Self>> on Enum {
  Store get store;
}

/// A PURE interceptor in the dispatch pipeline: inspect/transform an envelope,
/// or return null to veto it. It runs in the replay/optimistic path, so it MUST
/// be pure — a riverpod app guards the flow with one of these without coupling
/// the bus to it; side effects belong in a subscriber ([Bus.on]), not a guard.
///
/// Typed like [Bus.on]: a `Guard<AdMsg>` sees only that family — every other
/// envelope passes through it untouched; the default `M = Msg` sees the feed.
typedef Guard<M extends Msg> = Envelope? Function(M msg, Envelope env);

/// The message bus — the RICH tier's transport. Dispatch envelopes through
/// guards to typed subscribers. Transport-agnostic: feed it from WS, HTTP, a
/// local DB, or a local optimistic `dispatch(..., optimistic: true)`.
/// Decoupled from canon and from Flutter; a [StoreMemory] subscribes to it,
/// and a riverpod notifier can subscribe via [on] too — neither owns the other.
class Bus {
  final StreamController<Envelope> _controller =
      StreamController<Envelope>.broadcast(sync: true);
  final List<Guard<Msg>> _guards = [];
  // Re-entrant dispatches (an effect dispatching from within delivery — the
  // normal message → effect → message pattern) queue here and drain in order;
  // a sync broadcast controller throws on a mid-delivery add.
  final List<Envelope> _queued = [];
  bool _firing = false;

  /// Register a pure guard for the [M] family. Runs on every dispatch, in
  /// registration order; a non-[M] envelope passes through unchanged.
  void guard<M extends Msg>(Guard<M> g) => _guards
      .add((msg, env) => msg is M ? g(msg, env) : env);

  /// Push a message through the bus. `source` tags provenance (defaults to the
  /// common remote/optimistic); `optimistic` is the overlay-routing signal — an
  /// optimistic dispatch flows through the SAME subscribers as a remote one but
  /// lands as a pending overlay.
  void dispatch(Msg msg,
      {Source? source, bool optimistic = false, String? correlationId}) {
    var env = Envelope(msg,
        source: source ??
            (optimistic ? CommonSource.optimistic : CommonSource.remote),
        optimistic: optimistic,
        correlationId: correlationId);
    for (final g in _guards) {
      final next = g(env.msg, env);
      if (next == null) return; // vetoed
      env = next;
    }
    if (_firing) {
      _queued.add(env);
      return;
    }
    _firing = true;
    try {
      _controller.add(env);
      while (_queued.isNotEmpty) {
        _controller.add(_queued.removeAt(0));
      }
    } finally {
      _firing = false;
      _queued.clear();
    }
  }

  /// Subscribe to messages of type [M]. Returns the subscription to cancel.
  StreamSubscription<Envelope> on<M extends Msg>(
          void Function(M msg, Envelope env) handler) =>
      _controller.stream.where((e) => e.msg is M).listen((e) => handler(e.msg as M, e));

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
    _controller.close();
    _conn.close();
  }
}

/// The PURE, const registry descriptor: how a message folds into an entry's
/// state. No mutable state, no `ref`, const — so it can sit in a spec. The live
/// store ([StoreMemory]) is created separately and wired to a [Bus].
abstract class Store<K, E extends Identifiable<K>, M extends Msg> {
  const Store();

  /// Fold a message into the registry's keyed collection and return the NEXT
  /// collection. PURE — replayed on optimistic confirm/rollback, so no side
  /// effects. A message may touch MANY entries (a batch load) or none. The
  /// `identifiable` map extensions keep it terse:
  /// `entities.upsert(x)` · `entities.upsertAll(xs)` · `entities.removeById(id)`
  /// · `entities.updateById(id, (cur) => …)`.
  IdentifiableMap<K, E> reduce(IdentifiableMap<K, E> entities, M msg);
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
    _sub = bus.on<M>(_apply);
    // a disconnect loses the push freshness guarantee → confirmed entries stale.
    _connSub = bus.connection.listen((up) {
      if (!up) invalidateAll();
    });
  }

  final Store<K, E, M> _reg;
  IdentifiableMap<K, E> _base = {}; // confirmed truth only
  IdentifiableMap<K, E> _eff = {}; // base folded through pending overlays (cache)
  final Map<K, Flags> _flags = {};
  final List<_Pending<M>> _pending = []; // ordered optimistic overlays
  final StreamController<K> _changes = StreamController<K>.broadcast(sync: true);
  final StreamController<void> _structure =
      StreamController<void>.broadcast(sync: true);
  late final StreamSubscription<Envelope> _sub;
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
    // optimistic + correlationId → a pending overlay; base is NOT touched.
    if (env.optimistic && env.correlationId != null) {
      _pending.add(_Pending(env.correlationId!, msg));
      _refresh(const {});
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
        _flags[k] = Flags(source: env.source, stability: Stability.confirmed);
      } else {
        _flags.remove(k);
      }
    }
    _refresh(touched);
  }

  /// Discard the optimistic overlay(s) for [correlationId] — the prediction
  /// failed (timeout/reject). Base is untouched, so any superseding writes that
  /// landed meanwhile survive.
  void rollback(String correlationId) {
    _pending.removeWhere((p) => p.correlationId == correlationId);
    _refresh(const {});
  }

  /// The EFFECTIVE identity-map (base folded through the pending optimistic
  /// overlays) — the whole keyed collection.
  IdentifiableMap<K, E> get entities => _eff;

  /// The EFFECTIVE value at [key]: confirmed base folded through the pending
  /// optimistic overlays — this is what canon reads by nav id.
  E? operator [](K key) => _eff[key];

  /// A keyed HANDLE — `store(id)`: a first-class, passable reference to one
  /// entity slot. `[]` answers "the value, now"; `call` constructs the
  /// reference (read it reactively via the UI layer's `ref.of(context)`).
  EntityRef<K, E, M> call(K id) => EntityRef._(this, id);

  /// The CONFIRMED value at [key] — base only, ignoring overlays.
  E? confirmed(K key) => _base[key];

  /// True when an overlay currently changes [key]'s effective value from base.
  bool _overlaid(K key) => !identical(_eff[key], _base[key]);

  /// Flags at [key]: `optimistic`/`pending` while an overlay changes it, else the
  /// confirmed base flags.
  Flags? flagsOf(K key) {
    if (_overlaid(key)) {
      return const Flags(
          source: CommonSource.optimistic, stability: Stability.pending);
    }
    return _flags[key];
  }

  void _setStability(K key, Stability s, {Source? source}) {
    final cur = _flags[key];
    _flags[key] =
        Flags(source: source ?? cur?.source ?? CommonSource.remote, stability: s);
    _changes.add(key);
  }

  /// A fetch is in flight for [key] — the screen-entry trigger calls this when
  /// it fires a load. The value (if any) stays; stability becomes `loading`.
  void markLoading(K key) => _setStability(key, Stability.loading);

  /// A fetch for [key] errored.
  void markFailed(K key) => _setStability(key, Stability.failed);

  /// Door 2 metadata predicate: does [key] need loading? True when it is missing,
  /// stale, or failed; false when `confirmed`/`loading`/`pending` (present or
  /// in-flight). The generated nav trigger reads this and, if true, marks it
  /// loading and puts a `SurfaceMsg` on the bus — the store never fetches.
  bool needs(K key) => switch (flagsOf(key)?.stability) {
        Stability.confirmed || Stability.loading || Stability.pending => false,
        _ => true,
      };

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

  /// All effective entries — base folded through the optimistic overlays.
  Iterable<E> get values => _eff.values;

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
    _changes.close();
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
