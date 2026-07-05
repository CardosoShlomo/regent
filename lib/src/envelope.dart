import 'package:meta/meta.dart';

import 'msg.dart';

/// Where a value/message came from — the app's OPEN, GLOBAL provenance. Extend
/// it with your own enum (`enum AppSource implements Source { remote, hive, … }`);
/// [CommonSource] ships the usual ones. Global, NOT per-registry: how a message
/// ARRIVED is one fact, identical for every registry that consumes it — so the
/// app wires its own set once, here, not per store.
///
/// Provenance is NOT the overlay's optimistic routing (that's the fixed
/// [Envelope.optimistic] flag) and NOT the closed lifecycle [Stability].
abstract class Source {}

/// The common provenances. Use these, or your own `implements Source` enum.
enum CommonSource implements Source { remote, optimistic, local, replay, cached }

/// The lifecycle position of a stored datum — CLOSED and derived, never set by
/// a consumer. The screen-entry trigger switches over it exhaustively.
/// `reverted` = the last word here was a FAILED optimism: the value is the
/// confirmed base again after a rollback snapped an overlay away, and no newer
/// fact has spoken. The next fold that touches the datum overwrites it.
/// `amended` = the server settled an approved write to a THIRD value —
/// neither the prediction nor the old world (a clamp, a sanitization).
enum Stability {
  missing, loading, pending, confirmed, stale, failed, reverted, amended
}

/// A message wrapped with its transit metadata. `dispatch` produces one; guards
/// transform it; a store reads `source` into its flags sidecar. [optimistic] is
/// the canon-owned overlay-routing signal — separate from `source`, because the
/// base can't read the app's open provenance type to detect an optimistic emit.
/// `correlationId` ties an optimistic dispatch to its later remote confirmation.
@immutable
class Envelope {
  Envelope(this.msg,
      {required this.source, this.optimistic = false, this.correlationId});
  final Msg msg;
  final Source source;
  final bool optimistic;
  final String? correlationId;

  Envelope copyWith(
          {Msg? msg, Source? source, bool? optimistic, String? correlationId}) =>
      Envelope(
        msg ?? this.msg,
        source: source ?? this.source,
        optimistic: optimistic ?? this.optimistic,
        correlationId: correlationId ?? this.correlationId,
      );
}

/// The per-key sidecar a store keeps BESIDE the value: where it came from and how
/// settled it is. Kept separate so a value-only read never rebuilds on a flag
/// flip (a freshness/confirm change that leaves the value untouched).
@immutable
class Flags {
  const Flags(
      {required this.source, required this.stability, this.tampered = false});
  final Source source;
  final Stability stability;

  /// While a prediction is PENDING: some fact touched the predicted values
  /// with a state that neither confirms nor reverts it — contested until the
  /// settling fact or the deadline decides.
  final bool tampered;

  Flags copyWith({Source? source, Stability? stability, bool? tampered}) =>
      Flags(
          source: source ?? this.source,
          stability: stability ?? this.stability,
          tampered: tampered ?? this.tampered);

  @override
  bool operator ==(Object other) =>
      other is Flags &&
      other.source == source &&
      other.stability == stability &&
      other.tampered == tampered;
  @override
  int get hashCode => Object.hash(source, stability, tampered);
}
