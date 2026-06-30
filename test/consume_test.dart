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
  test('watch is value-distinct: a flag-only change emits nothing', () async {
    final bus = Bus();
    final store = RegistryMemory(const _Docs(), bus);
    bus.dispatch(_Set('a', 'hi'));

    final seen = <String?>[];
    final sub = store.consume('a').listen((d) => seen.add(d?.text));
    await Future<void>.delayed(Duration.zero); // initial 'hi'

    store.markLoading('a'); // FLAG-only flip — value unchanged
    bus.dispatch(_Set('a', 'hi2')); // value change
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(seen, ['hi', 'hi2']); // no emit for the loading flip
  });

  test('watchStatus is flag-distinct: emits stability transitions only', () async {
    final bus = Bus();
    final store = RegistryMemory(const _Docs(), bus);
    bus.dispatch(_Set('a', 'hi'));

    final seen = <Stability?>[];
    final sub = store.watchStatus('a').listen((f) => seen.add(f?.stability));
    await Future<void>.delayed(Duration.zero); // initial confirmed

    store.markLoading('a');
    bus.dispatch(_Set('a', 'hi2')); // value change re-confirms (same flags as start) → no extra emit
    store.markFailed('a');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(seen, [Stability.confirmed, Stability.loading, Stability.confirmed, Stability.failed]);
  });

  test('watch only fires for ITS key', () async {
    final bus = Bus();
    final store = RegistryMemory(const _Docs(), bus);

    final seen = <String?>[];
    final sub = store.consume('a').listen((d) => seen.add(d?.text));
    await Future<void>.delayed(Duration.zero); // initial null

    bus.dispatch(_Set('b', 'other')); // different key
    bus.dispatch(_Set('a', 'mine'));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(seen, [null, 'mine']); // 'b' never woke 'a'
  });
}
