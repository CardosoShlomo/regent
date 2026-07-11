import 'package:identifiable/identifiable.dart';

import 'msg.dart';
import 'store.dart';

/// Pure sugar over a UNIT's post-fold event stream — the recurring effect
/// idioms as verbs. Extensions on the STREAM (not the memory), so they
/// compose after any filter and over replayed feeds alike.
extension UnitEventStream<S, M extends Msg> on Stream<UnitEvent<S, M>> {
  /// Events where the state actually moved — optionally only where the
  /// [of] projection moved (`transitions((s) => s.phase)`).
  Stream<UnitEvent<S, M>> transitions([Object? Function(S state)? of]) =>
      of == null
          ? where((e) => e.before != e.after)
          : where((e) => of(e.before) != of(e.after));

  /// Transitions that land ON [state] — `authStore.events.entering(.synced)`.
  Stream<UnitEvent<S, M>> entering(S state) =>
      where((e) => e.before != e.after && e.after == state);

  /// The [M2]-typed slice of the feed, msg re-typed — the post-fold
  /// counterpart of `ledger.on<M2>()`.
  Stream<UnitEvent<S, M2>> on<M2 extends M>() =>
      where((e) => e.msg is M2).map((e) =>
          UnitEvent(msg: e.msg as M2, before: e.before, after: e.after));
}

/// One row's movement inside one fold — the store's change feed at row
/// grain, derived from [StoreEvent.changed] (no map walk).
sealed class RowChange<K, E> {
  const RowChange(this.id);
  final K id;
}

final class Inserted<K, E> extends RowChange<K, E> {
  const Inserted(super.id, this.entity);
  final E entity;
}

final class Updated<K, E> extends RowChange<K, E> {
  const Updated(super.id, this.before, this.entity);
  final E before;
  final E entity;
}

final class Deleted<K, E> extends RowChange<K, E> {
  const Deleted(super.id, this.before);
  final E before;
}

/// The keyed-store counterpart of [UnitEventStream].
extension StoreEventStream<K, E extends Identifiable<K>, M extends Msg>
    on Stream<StoreEvent<K, E, M>> {
  /// Events that changed anything — optionally only those where the [of]
  /// projection of some CHANGED key's value moved is the caller's judgment;
  /// this form filters on the changed-key set being non-empty.
  Stream<StoreEvent<K, E, M>> transitions() => where((e) => e.changed.isNotEmpty);

  /// The [M2]-typed slice of the feed, msg re-typed.
  Stream<StoreEvent<K, E, M2>> on<M2 extends M>() =>
      where((e) => e.msg is M2).map((e) => StoreEvent(
          msg: e.msg as M2,
          before: e.before,
          after: e.after,
          changed: e.changed,
          structural: e.structural));

  /// Each fold flattened into per-row changes — the vocabulary a surgical
  /// mirror speaks (`store.events.rowChanges().listen(db.applyRow)`).
  Stream<RowChange<K, E>> rowChanges() => expand((e) => [
        for (final id in e.changed)
          switch ((e.before[id], e.after[id])) {
            (null, final E entity) => Inserted<K, E>(id, entity),
            (final E before, null) => Deleted<K, E>(id, before),
            (final E before, final E entity) =>
              Updated<K, E>(id, before, entity),
            (null, null) => throw StateError('changed id $id in neither map'),
          },
      ]);

  /// Rows that appeared this fold.
  Stream<E> inserted() => expand((e) => [
        for (final id in e.changed)
          if (e.before[id] == null && e.after[id] != null) e.after[id]!,
      ]);

  /// Rows whose value moved this fold.
  Stream<E> updated() => expand((e) => [
        for (final id in e.changed)
          if (e.before[id] != null && e.after[id] != null) e.after[id]!,
      ]);

  /// Rows that appeared or moved — the write-side of an upsert mirror.
  Stream<E> upserted() => expand((e) => [
        for (final id in e.changed)
          if (e.after[id] != null) e.after[id]!,
      ]);

  /// Ids of rows that vanished this fold.
  Stream<K> deleted() => expand((e) => [
        for (final id in e.changed)
          if (e.after[id] == null) id,
      ]);
}
