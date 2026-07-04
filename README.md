# regent

Optimistic, message-driven state engine: a journal of sealed facts folded into keyed stores and units. Pure Dart.

One bus. Dispatch a `Msg`; it flows through pure **guards** (transform or veto), lands in every **store** whose sealed family it belongs to (`Store.reduce` over a keyed collection, `Unit.reduce` over one value), and watchers react to store STATE. Optimistic dispatches overlay until confirmed or rolled back by correlation id.

Beyond the fold:

- **Events** — each store emits one post-fold event per delivered family message (`msg`, `before`, `after`, changed keys): effects observe cause and consequence atomically, so they can never race the fold.
- **Awaits** — a store's correlation twin names its REQUEST family: dispatching a request marks its key in flight (status is derived, never a state field), and the twin's `surface(key, row, flags)` answers scope entry with the ask to dispatch — or null when the row's knowledge suffices.
- **Projection** — a merge edge: a unit's state answers a keyed surface's per-key reads at its own `Identifiable` id (the self row answered by the session's own truth, with no id comparison in consumer code).

## Message conventions

The structure prevents most failure modes; message taxonomy discipline prevents the rest. These are the rules the engine can't enforce for you:

- **Messages are facts, not calls.** Name an inbound message for the fact it states (`ProductLoaded`, `UsernameTaken`), an outbound one for the intent it declares. A message never names its handler.
- **Semantic outcomes, never generic errors.** `UsernameTaken`, not `Error("username taken")` — an expected outcome is a message the reducer and UI handle like any other fact.
- **One sealed family per entity concern.** The family (`AdListMsg`, `ProfileMsg`) is exactly what one store reduces — `sealed`, so the reduce is exhaustively matched and a new variant is a compile error until every store answers it.
- **Guards are pure.** A guard may read state, transform, or veto — never dispatch or touch the world. Side effects belong in subscribers (`on<M>`). Register guards centrally, in one ordered setup: the pipeline order IS semantics.

## Store keys are gradually typed

A store's key type may be the raw codec type or the id's generated extension
type — both are always valid, and they are runtime-identical (extension types
erase):

```dart
class Products extends Store<String, Product, ProductMsg> { … }     // day one
class Products extends Store<ProductId, Product, ProductMsg> { … }  // hardened
```

Write `String` before the first generation exists (nothing else compiles yet);
tighten to `ProductId` whenever you like — or never. The typed key buys exactly
one thing: nominal protection on the store's key axis (`products[someUserId]`
stops compiling). Everything else — verbs, entity fields, derived reads — is
typed independently and works the same either way.

## Guards

Typed like `on<M>` — a guard sees one family; everything else passes through untouched:

```dart
ledger.guard<AdMsg>((msg, env) => banned.contains(msg.adId) ? null : env);
ledger.guard((msg, env) => readOnlyMode ? null : env); // M = Msg: the full feed
```
