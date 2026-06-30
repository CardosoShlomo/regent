abstract class Msg {
  const Msg();
}

/// A "this key is needed but not fresh" signal a store puts on the bus (Door 2).
/// The store never fetches — it only emits this; a posting guard or an imperative
/// `on<…>` listener (the riverpod-`build` role) handles the actual read/fetch and
/// dispatches the data back as a normal [Msg]. The generator emits a CONCRETE
/// subclass per store (`ProductSurfaceMsg`) so it pattern-matches cleanly.
abstract class SurfaceMsg extends Msg {
  const SurfaceMsg();

  /// The demanded key (typed on each generated subclass).
  Object? get key;
}
