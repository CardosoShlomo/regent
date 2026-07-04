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
          IdentifiableMap<String, _Item> entities, _Set m) =>
      entities.upsert(_Item(m.id));
}

void main() {
  test('needs() tracks Door 2 stability: missing/stale/failed → true', () {
    final bus = Bus();
    final store = StoreMemory(const _Items(), bus);

    expect(store.needs('a'), isTrue); // missing
    store.markLoading('a');
    expect(store.needs('a'), isFalse); // in flight
    bus.dispatch(_Set('a'));
    expect(store.needs('a'), isFalse); // confirmed
    store.invalidate('a');
    expect(store.needs('a'), isTrue); // stale → needs again
    store.markFailed('a');
    expect(store.needs('a'), isTrue); // failed → needs
  });
}
