/// Marks a method (or class) as PURE — its body may read only its parameters,
/// locals, pattern-bound variables, and compile-time constants, and may call
/// only other pure functions. No ambient or mutable state, no clock, no
/// randomness, no I/O. Purity is what makes a fold deterministic and therefore
/// [replay]-able: `replay(a) == replay(b)` is a law only because the folds
/// between cannot reach outside their arguments.
///
/// Applied structurally to every fold-family contract (Store/Unit.reduce,
/// Guard.judge, Veto.block) and available as `@pure` on any other function you
/// want held to the same bar. Enforced by regent's `custom_lint` rule; without
/// the lint it still documents the contract.
final class Pure {
  const Pure();
}

/// The `@pure` marker — mirrors `@immutable`'s lowercase-const convention.
const pure = Pure();
