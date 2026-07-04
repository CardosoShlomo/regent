import 'package:test/test.dart';
import 'package:regent/regent.dart';

class _CounterState with Identifiable<String> {
  _CounterState(this.id, this.value);
  @override
  final String id;
  final int value;
}

sealed class _CounterMsg extends Msg {
  const _CounterMsg();
}

class _Inc extends _CounterMsg with Identifiable<String> {
  _Inc(this.id, this.by);
  @override
  final String id;
  final int by;
}

class _Reset extends _CounterMsg with Identifiable<String> {
  _Reset(this.id);
  @override
  final String id;
}

final class _Counter extends Store<String, _CounterState, _CounterMsg> {
  const _Counter();
  @override
  IdentifiableMap<String, _CounterState> reduce(
          IdentifiableMap<String, _CounterState> states, _CounterMsg m) =>
      switch (m) {
        _Inc(:final id, :final by) =>
          states.upsert(_CounterState(id, (states[id]?.value ?? 0) + by)),
        _Reset(:final id) => states.removeById(id), // remove
      };
}

void main() {
  test('dispatch folds via reduce; flags = confirmed/remote', () {
    final bus = Bus();
    final store = StoreMemory(const _Counter(), bus);
    bus.dispatch(_Inc('a', 5));
    expect(store['a']?.value, 5);
    expect(store.flagsOf('a'),
        const Flags(source: CommonSource.remote, stability: Stability.confirmed));
    bus.dispatch(_Inc('a', 3));
    expect(store['a']?.value, 8);
  });

  test('optimistic dispatch tags the source flag', () {
    final bus = Bus();
    final store = StoreMemory(const _Counter(), bus);
    bus.dispatch(_Inc('a', 1), source: CommonSource.optimistic);
    expect(store.flagsOf('a')?.source, CommonSource.optimistic);
  });

  test('reduce -> null removes the entry and its flags', () {
    final bus = Bus();
    final store = StoreMemory(const _Counter(), bus);
    bus.dispatch(_Inc('a', 5));
    bus.dispatch(_Reset('a'));
    expect(store['a'], isNull);
    expect(store.flagsOf('a'), isNull);
  });

  test('a pure guard vetoes a message without coupling the bus', () {
    final bus = Bus();
    final store = StoreMemory(const _Counter(), bus);
    bus.guard<_Reset>((msg, env) => null); // drop resets
    bus.dispatch(_Inc('a', 5));
    bus.dispatch(_Reset('a')); // vetoed → 'a' survives
    expect(store['a']?.value, 5);
  });

  test('changes stream emits the key per mutation', () {
    final bus = Bus();
    final store = StoreMemory(const _Counter(), bus);
    final keys = <String>[];
    store.changes.listen(keys.add);
    bus.dispatch(_Inc('a', 1));
    bus.dispatch(_Inc('b', 1));
    expect(keys, ['a', 'b']);
  });
}
