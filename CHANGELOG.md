## 0.1.1

- README refreshed for the regent identity.

## 0.1.0

- Initial release: message bus with a journal/admitted split, typed guards and vetoes.
- `Store`/`Unit` pure reduce specs; `StoreMemory`/`UnitMemory` live stores with optimistic overlays.
- `Awaits` correlation twins: key-correlated request status + the `surface` scope-entry ask.
- Store event streams: one post-fold event per delivered family message.
- `Projection` merge edges: a unit's state answers a keyed surface's reads at its own id.
- `@stores` grammar (`StoreNode`) for canon's generator.
