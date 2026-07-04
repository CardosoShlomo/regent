import 'package:test/test.dart';
import 'package:regent/regent.dart';

class _Count with Identifiable<String> {
  _Count(this.id, this.value);
  @override
  final String id;
  final int value;
}

sealed class _CountMsg extends Msg {
  const _CountMsg();
}

class _Add extends _CountMsg with Identifiable<String> {
  _Add(this.id, this.by);
  @override
  final String id;
  final int by;
}

final class _Counter extends Store<String, _Count, _CountMsg> {
  const _Counter();
  @override
  IdentifiableMap<String, _Count> reduce(
          IdentifiableMap<String, _Count> states, _CountMsg m) =>
      switch (m) {
        _Add(:final id, :final by) =>
          states.upsert(_Count(id, (states[id]?.value ?? 0) + by)),
      };
}

void main() {
  test('optimistic overlay shows instantly; base stays untouched', () {
    final bus = Bus();
    final store = StoreMemory(const _Counter(), bus);
    bus.dispatch(_Add('a', 10)); // confirmed base = 10
    bus.dispatch(_Add('a', 5), optimistic: true, correlationId: 'C1');

    expect(store['a']?.value, 15); // EFFECTIVE = base + overlay
    expect(store.confirmed('a')?.value, 10); // base untouched
    expect(store.flagsOf('a'),
        const Flags(source: CommonSource.optimistic, stability: Stability.pending));
  });

  test('remote with matching correlationId confirms (promote + drop overlay)', () {
    final bus = Bus();
    final store = StoreMemory(const _Counter(), bus);
    bus.dispatch(_Add('a', 10));
    bus.dispatch(_Add('a', 5), optimistic: true, correlationId: 'C1');
    // the real server effect arrives, carrying C1 → confirms
    bus.dispatch(_Add('a', 5), correlationId: 'C1');

    expect(store['a']?.value, 15);
    expect(store.confirmed('a')?.value, 15); // now in base
    expect(store.flagsOf('a')?.stability, Stability.confirmed);
  });

  test('rollback discards the prediction, returns to base', () {
    final bus = Bus();
    final store = StoreMemory(const _Counter(), bus);
    bus.dispatch(_Add('a', 10));
    bus.dispatch(_Add('a', 5), optimistic: true, correlationId: 'C1');
    store.rollback('C1');

    expect(store['a']?.value, 10);
    expect(store.flagsOf('a')?.stability, Stability.confirmed);
  });

  test('THE PROOF: rollback after a superseding write keeps the superseding write',
      () {
    final bus = Bus();
    final store = StoreMemory(const _Counter(), bus);
    bus.dispatch(_Add('a', 10)); // base = 10
    bus.dispatch(_Add('a', 5), optimistic: true, correlationId: 'C1');
    expect(store['a']?.value, 15); // effective with overlay

    // an UNRELATED remote write lands on top while C1 is still pending
    bus.dispatch(_Add('a', 3)); // base = 13
    expect(store['a']?.value, 18); // base(13) folded with overlay(+5)

    store.rollback('C1'); // C1 failed

    // the superseding +3 SURVIVES; only the optimistic +5 is gone.
    expect(store['a']?.value, 13); // not 10 (pre-optimistic), not 15, not 18
    expect(store.confirmed('a')?.value, 13);
  });

  test('changes fire on overlay add, confirm, and rollback', () {
    final bus = Bus();
    final store = StoreMemory(const _Counter(), bus);
    final keys = <String>[];
    store.changes.listen(keys.add);
    bus.dispatch(_Add('a', 10)); // base
    bus.dispatch(_Add('a', 5), optimistic: true, correlationId: 'C1'); // overlay
    store.rollback('C1'); // rollback
    expect(keys, ['a', 'a', 'a']);
  });
}
