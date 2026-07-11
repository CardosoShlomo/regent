## 0.13.0

- BREAKING: the 0.12 crud tier removed — role mixins, slot bricks, and presets were DIALECTS, and dialects are app code: a named `Regency` subclass is a pure GRAFT (const rows spliced in place, reads stay flat — `read(todos)` never knows the grouping exists), so resource shapes live beside the app's own rows (the example's point 13 shows the wild's commonest crud written longhand). The package ships only what can never wrong a consumer: the core queue, pure value algebras (`CoveredRanges`), and zero-policy stream sugar.
- `Store.initial` is optional positional (`: super(const {...})` to seed).

## 0.12.0

- `Regency`: the app as a const VALUE — ordered regent rows plus merge edges; graphs nest (a segment splices in place) and a plain regent is a one-row graph; `Ledger.root(regent)` builds it, splicing rows and auto-wiring merges.
- TWO doors: `dispatch(msg)` and `at(position)` — a typed handle per position: `at(const Products())` a StoreMemory, `at(const Viewer())` a UnitMemory, `at(const CachedGate())` a GuardMemory, `at(.entry)` the record, `at(.exit)` the admitted feed. Plural members are streams (`msgs<T>()`, `states`, `statesBefore`, `events`; guards add `dropped`/`forwarded`/`minted`), singular are values now (`base`, `entities`, `value`).
- Guards enroll a `GuardMemory` — judged input and verdict observable as one `GuardEvent`; duplicate guard instances now throw like any regent.
- BREAKING: the enum tier retired — `Regents`/`RegentNode`/`RegentMerge`/`SpecLedger`/`Ledger.of` deleted; `replay(root, order)` takes the graph; `journal`, `read`, `memory`, `on<M>()` fold into `at(...)`.
- `Projection`/`UnitProjection` carry their endpoints as const fields (`: super(const Todos(), const LocalTodos())`) — the projection IS the edge.
- The role vocabulary: `ListMsg`/`CacheMsg`/`AddMsg`/`EchoOf`/`RemoveMsg`/`ResetMsg` — field-less mixins; extends = meaning, with = shape, implements = audience.
- CRUD bricks: `Crud` slot-bound base with `ListCrud`/`WritableListCrud` presets over role-typed regents (`ResourceRows`, `ResourceCache`, `ResourceDock`, `Coverage`, `CacheGate`, `ShadowSupports`).

## 0.11.0

- BREAKING: guards are LAUNCHERS — `judge` returns `Set<Judgment>`: `.forward(msg)` continues this round below (pass/drop/rewrite/fan-out as before), `.mint(msg)` derives a new fact as its own round from index 0 (unjournaled — re-derived on replay; sibling mints must commute; depth-budgeted).
- BREAKING: `Envelope` deleted — `judge(msg, read)` / `block(msg, read)`; the journal carries bare facts (causation goes ON the fact, never beside it).
- The locality axiom documented: stores transform state and nothing else; guards enqueue cursors and nothing else; every invocation reads only (current state, message).
- The SHADOW LAW: no row reduces the unsealed root `Msg` — cross-family rows (shadows, docks, in-flight units) declare a sealed GROUP their facts `implements`; even a shadow's delegation arm is typed.

## 0.10.0

- BREAKING: the memories hold NOTHING but their fold — deleted: `Flags`/`Stability`, the flags sidecar (`flagsOf`, `watchStatus`, `invalidate*`), optimistic overlays (`command`, `rollback`, `dispatch`'s `optimistic`/`correlationId`), Door-1 (`consume`, `gc`, `watchers`), `Bus.connection`/`setConnected`, and `Awaits` entirely. Every status is a consumer ROW (docks, in-flight units, coverage, a connection unit) — it replays, guards read it, laws state it.
- BREAKING: `store.call(id)` / `EntityRef` deleted — the keyed reactive read is the binding layer's `store.entityOf(context, id)`; `store[id]` stays the value-now read.

## 0.9.0

- BREAKING: `Guard.judge` returns `Set<Msg>` — the feed the rows below see: `{}` drop, `{msg}` pass, `{other}` rewrite, `{a, b, …}` fan-out branches in set order. `Veto` unchanged for consumers.
- BREAKING: `Verdict` removed — write settlement is rows now: a pending side store, a settling guard, a merge edge, and a consumer deadline effect.
- BREAKING: awaits' state half deleted — in-flight status is a consumer row (a unit folding request/answer facts) deduped by a guard; `Awaits` keeps only `surface(key, row)`. Gone: `keyOf`, `keys`, `AwaitsUnit`, `Unit.awaits`, `markLoading`, `markFailed`, `inFlight`, `needs`, `UnitMemory.loading`.
- `CoveredRanges` — covered cursor intervals as a pure value (mark/retract/contains; open-ended edges; retraction opens its boundaries).
- Unit-target merge edges: `UnitMemory.merge(source, UnitProjection)`.
- `ledger.read` returns BASE (confirmed state) — judges never rule on unacked predictions.

## 0.8.0

- BREAKING: guards judge through `read` — `Guard<M, S>` → `Guard<M>`, `judge(env, msg, ReadStore read)`; `read(const X())` is the ledger's own state by citizen identity (`AnyStore<S>` carries the type). No stores facade; `Ledger.guard(spec)` takes no facade arg; two rows may not hold identical instances.
- `replay(rows, order)` needs no stores param — gate-bearing enums replay standalone.

## 0.7.1

- identifiable ^0.6.0.

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
