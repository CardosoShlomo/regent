## 0.7.0

- `replay(rows, order)` / `replayStore`: fold a message order on a pure ledger to a state snapshot — order-(in)dependence as a law via `equals`/`isNot`.
- `@pure` marker on the fold-family contracts (Store/Unit.reduce, Guard.judge).

## 0.6.0

- `Ledger.of(rows)`: the declared ledger — closed citizen list from the regent enum; `memoryOf(row)`; positional `on<M>(before: row)` reads the feed at any declared row.

## 0.5.0

- Row-grain store feed: `rowChanges()` + `inserted`/`updated`/`upserted`/`deleted` stream verbs.

## 0.4.0

- Regent citizen base; positional Guard/Veto rows; segmented queue; keyed verdicts.

## 0.3.0

- Observation is async (post-cut): store streams and `ledger.on` deliver after the traversal; dispatch during a fold/guard asserts.
- `mergeStore`: keyed-store merge sources; store sources join the collection union.
- `Source`/`CommonSource` removed — provenance is said by types and stores.
- Event-stream verbs: `transitions`, `entering`, `on<M>` on store event streams.

## 0.2.0

- `Verdict`: the write correlation twin — prediction + resolver types, settled by state comparison.
- Optimistic overlays and `rollback` on unit stores.
- `Stability.reverted` / `.amended` and the `tampered` flag.
- `awaits`/`verdict` declared as `super` constructor fields; `Store.initial` is named.

## 0.1.1

- README refreshed for the regent identity.

## 0.1.0

- Initial release: message bus with a journal/admitted split, typed guards and vetoes.
- `Store`/`Unit` pure reduce specs; `StoreMemory`/`UnitMemory` live stores with optimistic overlays.
- `Awaits` correlation twins: key-correlated request status + the `surface` scope-entry ask.
- Store event streams: one post-fold event per delivered family message.
- `Projection` merge edges: a unit's state answers a keyed surface's reads at its own id.
- `@stores` grammar (`StoreNode`) for canon's generator.
