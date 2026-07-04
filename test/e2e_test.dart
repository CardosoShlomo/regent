import 'dart:async';

import 'package:regent/regent.dart';
import 'package:test/test.dart';

// --- domain ----------------------------------------------------------------
class Item with Identifiable<String> {
  Item(this.id, this.name);
  @override
  final String id;
  final String name;
}

// The reduce message family is SEALED — every source msg implements it.
sealed class ItemMsg extends Msg with Identifiable<String> {
  ItemMsg(this.id);
  @override
  final String id;
}

class ItemLoaded extends ItemMsg {
  ItemLoaded(super.id, this.name);
  final String name;
}

class ItemRenamed extends ItemMsg {
  ItemRenamed(super.id, this.name);
  final String name;
}

final class Items extends Store<String, Item, ItemMsg> {
  const Items();
  @override
  IdentifiableMap<String, Item> reduce(
          IdentifiableMap<String, Item> states, ItemMsg m) =>
      switch (m) {
        ItemLoaded(:final id, :final name) => states.upsert(Item(id, name)),
        ItemRenamed(:final id, :final name) => states.upsert(Item(id, name)),
      };
}

// --- a stand-in for canon's nav graph --------------------------------------
enum Screen { home, detail }

class _Entry {
  _Entry(this.screen, this.id);
  final Enum screen;
  final Object? id;
}

class FakeGraph {
  final List<_Entry> stack = [_Entry(Screen.home, null)];
  void go(Enum screen, Object? id) => stack.add(_Entry(screen, id));
}

// --- hand-written mirror of the GENERATED surface: stores + nav-keyed reads.
// No demand/fetch — data enters only as source Msgs dispatched onto the bus.
abstract final class Data {
  static late final StoreMemory<String, Item, ItemMsg> _items;
  static late final FakeGraph _graph;

  static void bind(Ledger ledger, FakeGraph graph) {
    _items = ledger.store(const Items());
    _graph = graph;
  }

  static Item? itemOnDetail() {
    for (final e in _graph.stack) {
      if (e.screen == Screen.detail) return _items[e.id as String];
    }
    return null;
  }

  static Stream<Item?>? consumeItemOnDetail() {
    for (final e in _graph.stack) {
      if (e.screen == Screen.detail) return _items.consume(e.id as String);
    }
    return null;
  }
}

void main() {
  test('nav-keyed read; source msg loads the store; optimistic rename round-trips',
      () async {
    final ledger = Ledger();
    final graph = FakeGraph();
    Data.bind(ledger, graph);

    // at home: detail isn't live → nothing to read.
    expect(Data.itemOnDetail(), isNull);

    // navigate to detail; the entry is empty until data arrives.
    graph.go(Screen.detail, 'x');
    expect(Data.itemOnDetail(), isNull);

    // data enters as a SOURCE msg (implements the sealed ItemMsg) → reduced in.
    ledger.dispatch(ItemLoaded('x', 'Widget'));
    expect(Data.itemOnDetail()?.name, 'Widget');
    expect(Data._items.flagsOf('x')?.stability, Stability.confirmed);

    // consume the live value reactively.
    final seen = <String?>[];
    final sub = Data.consumeItemOnDetail()!.listen((i) => seen.add(i?.name));
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['Widget']);

    // optimistic rename: instant overlay, then confirm via the effect's result.
    await ledger.command(ItemRenamed('x', 'Renamed'),
        effect: () async => ItemRenamed('x', 'Renamed'));
    await Future<void>.delayed(Duration.zero);
    expect(Data.itemOnDetail()?.name, 'Renamed');
    expect(seen.first, 'Widget');
    expect(seen.last, 'Renamed');

    await sub.cancel();
    ledger.close();
  });
}
