# regent

Optimistic, message-driven state engine: a journal of sealed facts folded
into keyed stores and units, traversed by one ordered queue of citizens.
Pure Dart.

## The queue of citizens

Dispatch a `Msg`; it enters the journal (the complete, ungated record) and
walks the QUEUE — an ordered list of citizens, each a `Regent`:

- A **store** row is a pure READER standing at its place: it folds what
  passes (`Store.reduce` over a keyed collection, `Unit.reduce` over one
  value) and can never touch the message. What it sees is whatever survived
  the guards above its row.
- A **guard** row is a pure JUDGE of the flow: it folds nothing and holds no
  state, but decides what every row below it sees — pass, drop, or rewrite
  (`Guard.judge`). A `Veto` is the boolean specialization (pass or drop).

One order, two opposite relationships to it: moving a store changes what IT
sees; moving a guard changes what EVERYONE below it sees. The journal always
keeps the original fact — guards shape the admitted feed, never the record.
`ledger.on<M>()` taps the END of the queue, so effects never fire on a
dropped message.

```dart
final ledger = Ledger();
ledger.veto<CatalogCacheMsg>((_) => cartHasItems); // inline, hand-wired
final products = ledger.store(const Products());   // reads below the veto
```

Guards expose nothing consumable — no state, no stream. All observation
goes through stores; a rejection that needs UI is a fact a store folds,
never a guard tap.

With canon's generator, the queue is DECLARED: a `@regents` enum lists every
citizen in traversal order, guards as `Guard`/`Veto` classes judging through
a generated read-only `Stores` facade, and merge edges in the enum's static
`merges` set (`products.from(localProducts, const LocalProductSupports())`).

## Optimism

An optimistic dispatch lands as a pending OVERLAY — base state is never
touched, so a rollback can't clobber a confirmed or superseding write.
Settle it two ways:

- **Correlation** (`ledger.command`): the transport's confirming message
  promotes the overlay by id; a thrown effect rolls it back.
- **A write dock** — rows, not machinery: a side store holds the pending
  prediction as honest state (base has no arm for it), a merge edge applies
  it at read, a guard settles it against echoes by STATE COMPARISON, and a
  deadline EFFECT dispatches a timeout fact the guard judges like any other.
  Everything replays, so confirm/revert/amend orders are statable as laws.

Every entry carries `Flags` (`pending`, `confirmed`, `reverted`, `amended`,
`stale`, `failed` + `tampered`), so the UI can tell a hope from a truth.

## Beyond the fold

- **Events** — each store emits one post-fold event per delivered family
  message (`msg`, `before`, `after`, changed keys): effects observe cause
  and consequence atomically, so they can never race the fold. Sugar:
  `transitions()`, `entering(state)`, `on<M>()`.
- **Awaits** — a store's correlation twin names its REQUEST family:
  dispatching a request marks its key in flight (status is derived, never a
  state field), and the twin's `surface(key, row, flags)` answers scope
  entry with the ask to dispatch — or null when the row's knowledge
  suffices.
- **Merges** — read-time edges, never copied state: a unit's state answers a
  keyed surface at its own `Identifiable` id (`merge`), or a whole store
  lends its rows to another's reads through a projection (`mergeStore`) —
  the shadow-store pattern: a disk cache folds into its own store and
  supports the main store's reads until the authority covers.

## Message conventions

The structure prevents most failure modes; message taxonomy discipline
prevents the rest. These are the rules the engine can't enforce for you:

- **Messages are facts, not calls.** Name an inbound message for the fact it
  states (`ProductLoaded`, `UsernameTaken`), an outbound one for the intent
  it declares. A message never names its handler.
- **Semantic outcomes, never generic errors.** `UsernameTaken`, not
  `Error("username taken")` — an expected outcome is a message the reducer
  and UI handle like any other fact.
- **One sealed family per entity concern.** The family (`ProductMsg`,
  `CartMsg`) is exactly what one store reduces — `sealed`, so the reduce is
  exhaustively matched and a new variant is a compile error until every
  store answers it. (A SHADOW store may reduce the root `Msg` and delegate.)
- **Guards are pure.** A guard reads the world only through its stores
  facade — never dispatches, never touches the world. Placement is
  semantics: declare guards above the rows they protect.

## Store keys are gradually typed

A store's key type may be the raw codec type or the id's generated extension
type — both are always valid, and they are runtime-identical (extension types
erase):

```dart
final class Products extends Store<String, Product, ProductMsg> { … }     // day one
final class Products extends Store<ProductId, Product, ProductMsg> { … }  // hardened
```

Write `String` before the first generation exists (nothing else compiles
yet); tighten to `ProductId` whenever you like — or never. The typed key buys
exactly one thing: nominal protection on the store's key axis
(`products[someUserId]` stops compiling). Everything else — verbs, entity
fields, derived reads — is typed independently and works the same either way.
