import 'package:identifiable/identifiable.dart';

import 'ledger.dart';
import 'msg.dart';
import 'store.dart';

/// A snapshot of every citizen's state after a replay — keyed by regent row.
/// Store rows map to a plain `Map` of their entities, unit rows to their
/// value, guard rows to null. Plain collections so `equals` / `isNot` compare
/// structurally.
typedef LedgerState<R> = Map<R, Object?>;

/// The state the WHOLE ledger folds from [order] — its *replay*. Builds a pure
/// ledger from the declared regent list ([rows] must be the enum's `values`),
/// folds the messages synchronously, and returns a snapshot of every citizen's
/// state. Deterministic: the folds are pure, so the same messages always yield
/// the same snapshot — replay is the operation purity buys you.
///
/// Compare two replays with `equals` / `isNot` to state order-(in)dependence
/// across the ledger as a law:
///
///   expect(replay(Rows.values, [cache, authority]),
///          equals(replay(Rows.values, [authority, cache])));  // converges
///
/// [stores] is the read-only facade guard rows judge through — required only
/// when the ledger has guards.
LedgerState<R> replay<R extends RegentNode<R>>(List<R> rows, List<Msg> order,
    {Object? stores}) {
  final ledger = Ledger.of(rows, stores: stores);
  for (final msg in order) {
    ledger.dispatch(msg);
  }
  final snapshot = <R, Object?>{
    for (final r in rows) r: _stateOf(ledger.memoryOf(r)),
  };
  ledger.close();
  return snapshot;
}

Object? _stateOf(Object? memory) => switch (memory) {
      final StoreMemory m => {...m.entities},
      final UnitMemory m => m.value,
      _ => null,
    };

/// A single store's replayed collection — the narrow form of [replay] for a
/// store whose `reduce` reads only its own state (no guards, no merge edges).
IdentifiableMap<K, E> replayStore<K, E extends Identifiable<K>, M extends Msg>(
    Store<K, E, M> store, List<Msg> order) {
  final bus = Bus();
  final mem = StoreMemory<K, E, M>(store, bus);
  for (final msg in order) {
    bus.dispatch(msg);
  }
  final state = mem.entities;
  mem.dispose();
  bus.close();
  return state;
}
