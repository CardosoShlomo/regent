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
  test('watch is value-distinct: a flag-only change emits nothing', () async {
    final bus = Bus();
    final store = StoreMemory(const _Docs(), bus);
    bus.dispatch(_Set('a', 'hi'));

    final seen = <String?>[];
    final sub = store.consume('a').listen((d) => seen.add(d?.text));
    await Future<void>.delayed(Duration.zero); // initial 'hi'

    store.invalidate('a'); // FLAG-only flip — value unchanged
    bus.dispatch(_Set('a', 'hi2')); // value change
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    await Future<void>.delayed(Duration.zero);
    expect(seen, ['hi', 'hi2']); // no emit for the loading flip
  });

  test('watchStatus is flag-distinct: emits stability transitions only', () async {
    final bus = Bus();
    final store = StoreMemory(const _Docs(), bus);
    bus.dispatch(_Set('a', 'hi'));
    await Future<void>.delayed(Duration.zero);

    final seen = <Stability?>[];
    final sub = store.watchStatus('a').listen((f) => seen.add(f?.stability));
    await Future<void>.delayed(Duration.zero); // initial confirmed

    store.invalidate('a');
    await Future<void>.delayed(Duration.zero); // stale is its own cut
    bus.dispatch(_Set('a', 'hi2'));
    await Future<void>.delayed(Duration.zero); // value change re-confirms
    store.invalidate('a');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    await Future<void>.delayed(Duration.zero);
    expect(seen, [Stability.confirmed, Stability.stale, Stability.confirmed, Stability.stale]);
  });

  test('watch only fires for ITS key', () async {
    final bus = Bus();
    final store = StoreMemory(const _Docs(), bus);

    final seen = <String?>[];
    final sub = store.consume('a').listen((d) => seen.add(d?.text));
    await Future<void>.delayed(Duration.zero); // initial null

    bus.dispatch(_Set('b', 'other')); // different key
    bus.dispatch(_Set('a', 'mine'));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    await Future<void>.delayed(Duration.zero);
    expect(seen, [null, 'mine']); // 'b' never woke 'a'
  });
}
