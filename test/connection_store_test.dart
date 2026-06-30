import 'package:test/test.dart';
import 'package:ledger/ledger.dart';

class _M with Identifiable<int> {
  _M(this.id, this.chat); // id doubles as sort key (higher = newer)
  @override
  final int id;
  final String chat; // the connection key
}

sealed class _CMsg extends Msg {
  const _CMsg();
}

class _Page extends _CMsg {
  _Page(this.chat, this.items, this.hasMore);
  final String chat;
  final List<_M> items;
  final bool hasMore;
}

class _Push extends _CMsg {
  _Push(this.item);
  final _M item;
}

final class _Chats
    extends ConnectionRegistry<String, _M, int, int, _CMsg> {
  const _Chats();
  @override
  String keyOf(_CMsg m) => switch (m) {
        _Page(:final chat) => chat,
        _Push(:final item) => item.chat,
      };
  @override
  int sortKeyOf(_M e) => e.id;
  @override
  void apply(Connection<_M, int, int> c, _CMsg m) => switch (m) {
        _Page(:final items, :final hasMore) =>
          c.setWindow(items, hasMoreBefore: hasMore),
        _Push(:final item) => c.receive(item),
      };
}

void main() {
  test('messages route to the right connection by key', () {
    final bus = Bus();
    final store = ConnectionMemory(const _Chats(), bus);
    bus.dispatch(_Page('a', [_M(2, 'a'), _M(1, 'a')], true));
    bus.dispatch(_Push(_M(3, 'a'))); // live edge → anchors
    expect(store['a'].window.map((m) => m.id), [3, 2, 1]);
  });

  test('a push for a never-opened connection is STORED (floating), not ignored',
      () {
    final bus = Bus();
    final store = ConnectionMemory(const _Chats(), bus);
    bus.dispatch(_Push(_M(9, 'b'))); // chat 'b' never loaded → not at live edge
    expect(store['b'].window, isEmpty); // window untouched
    expect(store['b'].floating.single.entity.id, 9); // but kept, floating
  });

  test('store.watch streams a connection view that updates on dispatch', () async {
    final bus = Bus();
    final store = ConnectionMemory(const _Chats(), bus);
    final seen = <List<int>>[];
    final sub = store.watch('a').listen((v) => seen.add([for (final m in v.window) m.id]));
    await Future<void>.delayed(Duration.zero); // initial empty

    bus.dispatch(_Page('a', [_M(5, 'a')], false));
    bus.dispatch(_Push(_M(6, 'a')));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(seen, [
      <int>[],
      [5],
      [6, 5],
    ]);
  });
}
