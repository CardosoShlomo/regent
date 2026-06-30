import 'package:test/test.dart';
import 'package:ledger/ledger.dart';

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

final class _Docs extends Registry<String, _Doc, _DocMsg> {
  const _Docs();
  @override
  IdentifiableMap<_Doc, String> reduce(
          IdentifiableMap<_Doc, String> entities, _DocMsg m) =>
      switch (m) {
        _Set(:final id, :final text) => entities.upsert(_Doc(id, text)),
      };
}

void main() {
  test('disconnect flips confirmed entries to stale; reconnect+remote re-confirms',
      () {
    final bus = Bus();
    final store = RegistryMemory(const _Docs(), bus);
    bus.dispatch(_Set('a', 'hi'));
    expect(store.flagsOf('a')?.stability, Stability.confirmed);

    bus.setConnected(false); // push freshness lost
    expect(store.flagsOf('a')?.stability, Stability.stale);
    expect(store['a']?.text, 'hi'); // value survives, just stale

    bus.setConnected(true);
    bus.dispatch(_Set('a', 'hi2')); // a fresh push re-confirms
    expect(store.flagsOf('a')?.stability, Stability.confirmed);
  });

  test('markLoading / markFailed move stability, value untouched', () {
    final bus = Bus();
    final store = RegistryMemory(const _Docs(), bus);
    bus.dispatch(_Set('a', 'hi'));

    store.markLoading('a');
    expect(store.flagsOf('a')?.stability, Stability.loading);
    expect(store['a']?.text, 'hi');

    store.markFailed('a');
    expect(store.flagsOf('a')?.stability, Stability.failed);
  });

  test('loading a missing key: flags exist, value still null', () {
    final bus = Bus();
    final store = RegistryMemory(const _Docs(), bus);
    store.markLoading('a'); // fetch on entry, nothing cached yet
    expect(store['a'], isNull);
    expect(store.flagsOf('a')?.stability, Stability.loading);
  });

  test('invalidate only affects confirmed entries', () {
    final bus = Bus();
    final store = RegistryMemory(const _Docs(), bus);
    bus.dispatch(_Set('a', 'hi'));
    store.markLoading('a'); // now loading, not confirmed
    store.invalidate('a'); // no-op (not confirmed)
    expect(store.flagsOf('a')?.stability, Stability.loading);
  });

  test('stability transitions emit change events', () {
    final bus = Bus();
    final store = RegistryMemory(const _Docs(), bus);
    bus.dispatch(_Set('a', 'hi'));
    final keys = <String>[];
    store.changes.listen(keys.add);
    store.markLoading('a');
    bus.setConnected(false); // invalidateAll → a is loading, not confirmed → no-op
    store.markFailed('a');
    expect(keys, ['a', 'a']); // loading, failed (disconnect was a no-op on loading)
  });
}
