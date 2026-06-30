import 'dart:async';

import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

// --- domain ----------------------------------------------------------------
class Item with Identifiable<String> {
  Item(this.id, this.name);
  @override
  final String id;
  final String name;
}

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

final class Items extends Registry<String, Item, ItemMsg> {
  const Items();
  @override
  IdentifiableMap<Item, String> reduce(
          IdentifiableMap<Item, String> states, ItemMsg m) =>
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
  final _nav = StreamController<void>.broadcast(sync: true);
  Stream<void> get navigations => _nav.stream;
  void go(Enum screen, Object? id) {
    stack.add(_Entry(screen, id));
    _nav.add(null);
  }
}

// --- generated-style concrete surface message (one per store) --------------
class ItemSurfaceMsg extends SurfaceMsg {
  ItemSurfaceMsg(this.key);
  @override
  final String key;
}

// --- hand-written mirror of the GENERATED `Data` surface -------------------
abstract final class Data {
  static late final Ledger _ledger;
  static late final RegistryMemory<String, Item, ItemMsg> _items;
  static late final FakeGraph _graph;

  static void bind(Ledger ledger, FakeGraph graph) {
    _ledger = ledger;
    _items = ledger.registry(const Items());
    _graph = graph;
    graph.navigations.listen((_) => surfaceLive());
    surfaceLive();
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

  // Door 2: on commit, if the live key isn't fresh, mark loading + emit a demand.
  static void surfaceItemOnDetail() {
    for (final e in _graph.stack) {
      if (e.screen == Screen.detail) {
        final key = e.id as String;
        if (_items.needs(key)) {
          _items.markLoading(key);
          _ledger.dispatch(ItemSurfaceMsg(key));
        }
        return;
      }
    }
  }

  static void surfaceLive() => surfaceItemOnDetail();
}

void main() {
  test('e2e: nav → demand → load → consume; optimistic rename round-trips',
      () async {
    final ledger = Ledger();
    final graph = FakeGraph();
    Data.bind(ledger, graph);

    // the consumer's ONE handler — the riverpod-`build` role. A demand on the bus
    // → fetch (async) → dispatch the data back as a normal Msg.
    final server = {'x': 'Widget'};
    var fetches = 0;
    ledger.journal.on<ItemSurfaceMsg>((m, _) => scheduleMicrotask(() {
          fetches++;
          ledger.dispatch(ItemLoaded(m.key, server[m.key]!));
        }));

    // at home: detail isn't live → nothing to read or consume.
    expect(Data.itemOnDetail(), isNull);
    expect(Data.consumeItemOnDetail(), isNull);

    // navigate → commit fires surfaceLive → needs('x') → ItemSurfaceMsg → handler.
    graph.go(Screen.detail, 'x');
    await Future<void>.delayed(Duration.zero);
    expect(Data.itemOnDetail()?.name, 'Widget');
    expect(Data._items.flagsOf('x')?.stability, Stability.confirmed);
    expect(fetches, 1);

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

    // navigating again to an ALREADY-fresh key emits no second demand.
    graph.go(Screen.detail, 'x');
    await Future<void>.delayed(Duration.zero);
    expect(fetches, 1); // needs('x') == false → no demand

    await sub.cancel();
    ledger.close();
  });
}
