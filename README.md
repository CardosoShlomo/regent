# ledger

Optimistic, message-driven state engine: a journal of sealed messages reduced into keyed stores. Pure Dart.

One bus. Dispatch a `Msg`; it flows through pure **guards** (transform or veto), lands in every **store** whose sealed family it belongs to (`Store.reduce`), and watchers react to store STATE. Optimistic dispatches overlay until confirmed or rolled back by correlation id.

## Message conventions

The structure prevents most failure modes; message taxonomy discipline prevents the rest. These are the rules the engine can't enforce for you:

- **Messages are facts, not calls.** Name an inbound message for the fact it states (`ProductLoaded`, `UsernameTaken`), an outbound one for the intent it declares. A message never names its handler.
- **Semantic outcomes, never generic errors.** `UsernameTaken`, not `Error("username taken")` — an expected outcome is a message the reducer and UI handle like any other fact.
- **One sealed family per entity concern.** The family (`AdListMsg`, `ProfileMsg`) is exactly what one store reduces — `sealed`, so the reduce is exhaustively matched and a new variant is a compile error until every store answers it.
- **Guards are pure.** A guard may read state, transform, or veto — never dispatch or touch the world. Side effects belong in subscribers (`on<M>`). Register guards centrally, in one ordered setup: the pipeline order IS semantics.

## Guards

Typed like `on<M>` — a guard sees one family; everything else passes through untouched:

```dart
ledger.guard<AdMsg>((msg, env) => banned.contains(msg.adId) ? null : env);
ledger.guard((msg, env) => readOnlyMode ? null : env); // M = Msg: the full feed
```
