import 'package:regent/regent.dart';
import 'package:test/test.dart';

sealed class _DocMsg extends Msg {}

class _Put extends _DocMsg {
  _Put(this.id, this.text);
  final String id;
  final String text;
}

class _Drop extends _DocMsg {
  _Drop(this.id);
  final String id;
}

class _Noop extends _DocMsg {}

class _Doc with Identifiable<String> {
  const _Doc(this.id, this.text);
  @override
  final String id;
  final String text;
}

final class _Docs extends Store<String, _Doc, _DocMsg> {
  const _Docs();

  @override
  IdentifiableMap<String, _Doc> reduce(
          IdentifiableMap<String, _Doc> entities, _DocMsg msg) =>
      switch (msg) {
        _Put(:final id, :final text) => entities.upsert(_Doc(id, text)),
        _Drop(:final id) => entities.removeById(id),
        _Noop() => entities,
      };
}

sealed class _FlowMsg extends Msg {}

class _Go extends _FlowMsg {}

class _Stop extends _FlowMsg {}

final class _Flow extends Unit<String, _FlowMsg> {
  const _Flow() : super('idle');

  @override
  String reduce(String state, _FlowMsg msg) =>
      switch (msg) { _Go() => 'running', _Stop() => 'idle' };
}

void main() {
  test('one event per delivered message, cause and consequence atomic', () async {
    final bus = Bus();
    final docs = StoreMemory(const _Docs(), bus);
    final seen = <StoreEvent<String, _Doc, _DocMsg>>[];
    docs.events.listen(seen.add);

    bus.dispatch(_Put('a', 'x'));
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
    await Future<void>.delayed(Duration.zero);
    expect(seen.last.msg, isA<_Put>());
    await Future<void>.delayed(Duration.zero);
    expect(seen.last.before['a'], isNull);
    await Future<void>.delayed(Duration.zero);
    expect(seen.last.after['a']!.text, 'x');
    await Future<void>.delayed(Duration.zero);
    expect(seen.last.changed, {'a'});
    await Future<void>.delayed(Duration.zero);
    expect(seen.last.structural, isTrue);

    bus.dispatch(_Put('a', 'y')); // value change, same keys
    await Future<void>.delayed(Duration.zero);
    expect(seen.last.changed, {'a'});
    await Future<void>.delayed(Duration.zero);
    expect(seen.last.structural, isFalse);

    bus.dispatch(_Noop()); // no-op fold still emits — msg filters see it
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(3));
    await Future<void>.delayed(Duration.zero);
    expect(seen.last.changed, isEmpty);

    bus.dispatch(_Drop('a'));
    await Future<void>.delayed(Duration.zero);
    expect(seen.last.structural, isTrue);
  });

  test('unit events carry before/after — transition filters need no dedupe',
      () async {
    final bus = Bus();
    final flow = UnitMemory(const _Flow(), bus);
    final transitions = <(String, String)>[];
    flow.events
        .where((e) => e.before != e.after)
        .listen((e) => transitions.add((e.before, e.after)));

    bus.dispatch(_Go());
    bus.dispatch(_Go()); // running → running: filtered out
    bus.dispatch(_Stop());
    await Future<void>.delayed(Duration.zero);
    expect(transitions, [('idle', 'running'), ('running', 'idle')]);
  });
}
