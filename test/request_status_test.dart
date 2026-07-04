import 'package:identifiable/identifiable.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

// The request family lives OUTSIDE the reduce family — no dead arms.
sealed class _PageRequest extends Msg {}

class _Get extends _PageRequest {
  _Get(this.id);
  final String id;
}

sealed class _PageMsg extends Msg {}

class _Page extends _PageMsg {
  _Page(this.id, this.items);
  final String id;
  final List<String> items;
}

class _Entry with Identifiable<String> {
  const _Entry(this.id, this.items);
  @override
  final String id;
  final List<String> items;
}

final class _PagesAwaits extends Awaits<String, _PageRequest> {
  const _PagesAwaits();

  @override
  String keyOf(_PageRequest request) =>
      switch (request) { _Get(:final id) => id };
}

final class _Pages extends Store<String, _Entry, _PageMsg> {
  const _Pages();

  @override
  Awaits<String, Msg>? get awaits => const _PagesAwaits();

  @override
  IdentifiableMap<String, _Entry> reduce(
          IdentifiableMap<String, _Entry> entities, _PageMsg msg) =>
      switch (msg) {
        _Page(:final id, :final items) => entities.upsert(_Entry(id, items)),
      };
}

class _Refresh extends Msg {}

sealed class _FeedMsg extends Msg {}

class _Feed extends _FeedMsg {
  _Feed(this.items);
  final List<String> items;
}

final class _FeedUnit extends ValueStore<List<String>, _FeedMsg> {
  const _FeedUnit() : super(const []);

  @override
  AwaitsUnit<Msg>? get awaits => const AwaitsUnit<_Refresh>();

  @override
  List<String> reduce(List<String> state, _FeedMsg msg) =>
      switch (msg) { _Feed(:final items) => items };
}

void main() {
  test('request fact marks the key loading; the answer confirms it', () {
    final bus = Bus();
    final pages = StoreMemory(const _Pages(), bus);

    expect(pages.inFlight('a'), isFalse);
    bus.dispatch(_Get('a'));
    expect(pages.inFlight('a'), isTrue);
    expect(pages['a'], isNull);

    bus.dispatch(_Page('a', ['x']));
    expect(pages.inFlight('a'), isFalse);
    expect(pages.flagsOf('a')?.stability, Stability.confirmed);
    expect(pages['a']!.items, ['x']);
  });

  test('loading is per key', () {
    final bus = Bus();
    final pages = StoreMemory(const _Pages(), bus);

    bus.dispatch(_Get('a'));
    bus.dispatch(_Get('b'));
    bus.dispatch(_Page('a', ['x']));
    expect(pages.inFlight('a'), isFalse);
    expect(pages.inFlight('b'), isTrue);
  });

  test('unit: request sets loading, any reduce-family fact clears it', () {
    final bus = Bus();
    final feed = ValueMemory(const _FeedUnit(), bus);

    expect(feed.loading, isFalse);
    bus.dispatch(_Refresh());
    expect(feed.loading, isTrue);
    bus.dispatch(_Feed(['x']));
    expect(feed.loading, isFalse);
    expect(feed.value, ['x']);
  });

  test('unit: flag flips alone emit changes', () {
    final bus = Bus();
    final feed = ValueMemory(const _FeedUnit(), bus);
    var emits = 0;
    feed.changes.listen((_) => emits++);

    bus.dispatch(_Refresh());
    expect(emits, 1);
    bus.dispatch(_Feed(const []));
    // value unchanged (identical initial? no — new list) but loading cleared.
    expect(emits, 2);
  });
}
