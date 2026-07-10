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
  state. Its verdict is a set of LAUNCHES targeting the only two indices
  that preserve the theorem *no row ever sees a message that skipped a
  guard above it*: `.forward(msg)` continues THIS round below (pass, drop
  via `{}`, rewrite, fan out); `.mint(msg)` DERIVES a new fact as its own
  round from index 0, after this round completes — re-judged by every
  guard, never journaled (it re-derives on replay), required to commute
  with its siblings. A `Veto` is the boolean specialization (pass or drop).

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
citizen in traversal order, guards as `Guard`/`Veto` classes reading the
ledger's own state by citizen identity (`read(const Products())` — checked
at build time), and merge edges in the enum's static `merges` set
(`products.from(localProducts, const LocalProductSupports())`).

## Optimism

Optimism is ROWS, never memory machinery — a store's memory holds nothing
but its fold. The **write dock**: a side store holds the pending prediction
as honest state (base has no arm for it), a merge edge applies it at read,
a guard settles it against echoes by STATE COMPARISON, and a deadline
EFFECT dispatches a timeout fact the guard judges like any other. Pending,
settled, in-flight, covered — every status a UI could render is a row, so
everything replays and confirm/revert/amend orders are statable as laws.

## Beyond the fold

- **Events** — each store emits one post-fold event per delivered family
  message (`msg`, `before`, `after`, changed keys): effects observe cause
  and consequence atomically, so they can never race the fold. Sugar:
  `transitions()`, `entering(state)`, `on<M>()`.
- **In-flight as a row** — a request fact folds its key in, the answering
  facts (success or failure) fold it out; presence = loading, read with the
  same surface as any state. A guard reading it drops duplicate asks; a
  scope-entry FACT judged by a gate replaces every fetch-on-entry bridge.
  No machinery, no sidecar.
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
  store answers it. NO row reduces the root `Msg` — a row whose facts cross
  families (a shadow, a dock, an in-flight unit) declares a sealed GROUP its
  facts `implements` (a family base may join a group wholesale), so even a
  shadow's delegation arm is typed: `final UserMsg m => const Users().reduce(rows, m)`.
- **Guards are pure.** A guard reads the world only through `read` — never
  dispatches, never touches the world. Placement is semantics: declare
  guards above the rows they protect.
- **The locality axiom.** Every citizen invocation is a pure function of
  (current state, message) — never of why the cursor arrived, what round it
  is, or what minted what. STORES TRANSFORM STATE AND NOTHING ELSE; GUARDS
  ENQUEUE CURSORS (at 0 or x+1) AND NOTHING ELSE. History reaches the
  future only through state, so replay totality is a theorem, provenance is
  invisible (if causation matters, it goes ON the fact), and every citizen
  is table-testable with (state, msg) pairs — judgments are values.
- **Mints derive, never sequence.** A legitimate mint is a fact the fold
  already implies, restatable as a law about state ("whenever X folds, Y
  exists"). Sequencing over time belongs to effects; a mint chain past the
  depth budget throws — a design diagnosis, not a runtime hazard.

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
