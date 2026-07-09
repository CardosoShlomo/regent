import 'package:test/test.dart';
import 'package:regent/regent.dart';

class _Doc with Identifiable<String> {
  _Doc(this.id, this.text);
  @override
  final String id;
  final String text;
}

sealed class _DocMsg extends Msg {
  const _DocMsg();
}

class _Set extends _DocMsg with Identifiable<String> {
  _Set(this.id, this.text);
  @override
  final String id;
  final String text;
}

final class _Docs extends Store<String, _Doc, _DocMsg> {
  const _Docs();
  @override
  IdentifiableMap<String, _Doc> reduce(
          IdentifiableMap<String, _Doc> entities, _DocMsg m) =>
      switch (m) {
        _Set(:final id, :final text) => entities.upsert(_Doc(id, text)),
      };
}

void main() {
  test('disconnect flips confirmed entries to stale; reconnect+remote re-confirms',
      () {
    final bus = Bus();
    final store = StoreMemory(const _Docs(), bus);
    bus.dispatch(_Set('a', 'hi'));
    expect(store.flagsOf('a')?.stability, Stability.confirmed);

    bus.setConnected(false); // push freshness lost
    expect(store.flagsOf('a')?.stability, Stability.stale);
    expect(store['a']?.text, 'hi'); // value survives, just stale

    bus.setConnected(true);
    bus.dispatch(_Set('a', 'hi2')); // a fresh push re-confirms
    expect(store.flagsOf('a')?.stability, Stability.confirmed);
  });

  test('invalidate only affects confirmed entries', () {
    final bus = Bus();
    final store = StoreMemory(const _Docs(), bus);
    store.invalidate('a'); // absent → no-op
    expect(store.flagsOf('a'), isNull);
    bus.dispatch(_Set('a', 'hi'));
    store.invalidate('a');
    expect(store.flagsOf('a')?.stability, Stability.stale);
    store.invalidate('a'); // already stale → no-op
    expect(store.flagsOf('a')?.stability, Stability.stale);
  });

  test('stability transitions emit change events', () async {
    final bus = Bus();
    final store = StoreMemory(const _Docs(), bus);
    bus.dispatch(_Set('a', 'hi'));
    final keys = <String>[];
    store.changes.listen(keys.add);
    store.invalidate('a');
    await Future<void>.delayed(Duration.zero);
    expect(keys, ['a']);
  });
}
