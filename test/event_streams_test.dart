import 'package:test/test.dart';
import 'package:regent/regent.dart';

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

enum _Phase { idle, compressing, uploading, done }

sealed class _FlowMsg extends Msg {
  const _FlowMsg();
}

class _Advance extends _FlowMsg {
  const _Advance(this.phase, [this.note = '']);
  final _Phase phase;
  final String note;
}

class _Noted extends _FlowMsg {
  const _Noted(this.note);
  final String note;
}

class _Flow {
  const _Flow(this.phase, this.note);
  final _Phase phase;
  final String note;

  @override
  bool operator ==(Object o) => o is _Flow && o.phase == phase && o.note == note;
  @override
  int get hashCode => Object.hash(phase, note);
}

final class _FlowUnit extends Unit<_Flow, _FlowMsg> {
  const _FlowUnit() : super(const _Flow(_Phase.idle, ''));
  @override
  _Flow reduce(_Flow s, _FlowMsg m) => switch (m) {
        _Advance(:final phase, :final note) => _Flow(phase, note),
        _Noted(:final note) => _Flow(s.phase, note),
      };
}

void main() {
  test('transitions() passes only real moves', () async {
    final bus = Bus();
    final unit = UnitMemory(const _FlowUnit(), bus);
    final seen = <_Phase>[];
    unit.events.transitions().listen((e) => seen.add(e.after.phase));
    bus.dispatch(const _Advance(_Phase.compressing));
    bus.dispatch(const _Advance(_Phase.compressing)); // no-op fold
    bus.dispatch(const _Advance(_Phase.uploading));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [_Phase.compressing, _Phase.uploading]);
  });

  test('transitions(projection) watches one aspect', () async {
    final bus = Bus();
    final unit = UnitMemory(const _FlowUnit(), bus);
    var fired = 0;
    unit.events.transitions((s) => s.phase).listen((_) => fired++);
    bus.dispatch(const _Noted('a')); // note moved, phase did not
    bus.dispatch(const _Advance(_Phase.done));
    await Future<void>.delayed(Duration.zero);
    expect(fired, 1);
  });

  test('entering fires once per arrival at the state', () async {
    final bus = Bus();
    final unit = UnitMemory(const _FlowUnit(), bus);
    var arrived = 0;
    unit.events
        .entering(const _Flow(_Phase.done, 'x'))
        .listen((_) => arrived++);
    bus.dispatch(const _Advance(_Phase.done, 'x'));
    bus.dispatch(const _Advance(_Phase.done, 'x')); // already there
    await Future<void>.delayed(Duration.zero);
    expect(arrived, 1);
  });

  test('on<M>() re-types the msg', () async {
    final bus = Bus();
    final unit = UnitMemory(const _FlowUnit(), bus);
    final notes = <String>[];
    unit.events.on<_Noted>().listen((e) => notes.add(e.msg.note));
    bus.dispatch(const _Advance(_Phase.compressing, 'skip'));
    bus.dispatch(const _Noted('kept'));
    await Future<void>.delayed(Duration.zero);
    expect(notes, ['kept']);
  });

  test('rowChanges() classifies inserts, updates, deletes', () async {
    final bus = Bus();
    final docs = StoreMemory(const _Docs(), bus);
    final seen = <String>[];
    docs.events.rowChanges().listen((c) => seen.add(switch (c) {
          Inserted(:final entity) => 'ins:${c.id}=${entity.text}',
          Updated(:final entity) => 'upd:${c.id}=${entity.text}',
          Deleted() => 'del:${c.id}',
        }));
    bus.dispatch(_Put('a', 'one'));
    bus.dispatch(_Put('a', 'two'));
    bus.dispatch(_Noop());
    bus.dispatch(_Drop('a'));
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['ins:a=one', 'upd:a=two', 'del:a']);
  });

  test('row verbs slice the feed', () async {
    final bus = Bus();
    final docs = StoreMemory(const _Docs(), bus);
    final ins = <String>[], ups = <String>[], del = <String>[];
    docs.events.inserted().listen((d) => ins.add(d.id));
    docs.events.upserted().listen((d) => ups.add('${d.id}=${d.text}'));
    docs.events.deleted().listen(del.add);
    bus.dispatch(_Put('a', 'one'));
    bus.dispatch(_Put('b', 'x'));
    bus.dispatch(_Put('a', 'two'));
    bus.dispatch(_Drop('b'));
    await Future<void>.delayed(Duration.zero);
    expect(ins, ['a', 'b']);
    expect(ups, ['a=one', 'b=x', 'a=two']);
    expect(del, ['b']);
  });
}
