import 'dart:async';

import 'package:regent/regent.dart';
import 'package:test/test.dart';

class _Item with Identifiable<String> {
  _Item(this.id);
  @override
  final String id;
}

class _Set extends Msg with Identifiable<String> {
  _Set(this.id);
  @override
  final String id;
}

final class _Items extends Store<String, _Item, _Set> {
  const _Items();
  @override
  IdentifiableMap<String, _Item> reduce(
          IdentifiableMap<String, _Item> states, _Set m) =>
      states.upsert(_Item(m.id));
}

void main() {
  test('consume refcounts: watchers track live subscribers', () async {
    final bus = Bus();
    final store = StoreMemory(const _Items(), bus);
    expect(store.watchers('a'), 0);

    final s1 = store.consume('a').listen((_) {});
    final s2 = store.consume('a').listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(store.watchers('a'), 2);

    await s1.cancel();
    expect(store.watchers('a'), 1);
    await s2.cancel();
    expect(store.watchers('a'), 0);
  });

  test('gc reclaims unwatched confirmed entries; keeps watched + pending', () async {
    final bus = Bus();
    final store = StoreMemory(const _Items(), bus);
    bus.dispatch(_Set('kept')); // confirmed, will be watched
    bus.dispatch(_Set('dropped')); // confirmed, unwatched
    bus.dispatch(_Set('pend'), optimistic: true, correlationId: 'C1'); // overlay

    final sub = store.consume('kept').listen((_) {});
    await Future<void>.delayed(Duration.zero);

    store.gc();
    expect(store.confirmed('kept'), isNotNull); // watched → kept
    expect(store.confirmed('dropped'), isNull); // unwatched → reclaimed
    expect(store['pend'], isNotNull); // pending overlay → kept

    await sub.cancel();
  });
}
