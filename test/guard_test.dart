import 'package:test/test.dart';
import 'package:regent/regent.dart';

sealed class _PriceMsg extends Msg {
  const _PriceMsg();
}

class _PriceSet extends _PriceMsg {
  const _PriceSet(this.id, this.value);
  final String id;
  final double value;
}

class _Price with Identifiable<String> {
  const _Price(this.id, this.value);
  @override
  final String id;
  final double value;
}

final class _Prices extends Store<String, _Price, _PriceMsg> {
  // [lane] distinguishes two rows of this store in one ledger — identical
  // const instances are ONE citizen (identity keying), so rows must differ.
  const _Prices([this.lane = 0]);
  final int lane;

  @override
  IdentifiableMap<String, _Price> reduce(
          IdentifiableMap<String, _Price> entities, _PriceMsg msg) =>
      switch (msg) {
        _PriceSet(:final id, :final value) =>
          entities.upsert(_Price(id, value)),
        _BulkSet() => entities, // heard, unfolded — the guard unbulks it below
      };
}

/// The floor as a UNIT citizen — the guard reads it through `read`, by the
/// canonical const expression (identity lookup, no facade).
final class _Floor extends Unit<double, _PriceMsg> {
  const _Floor(double floor) : super(floor);
  @override
  double reduce(double state, _PriceMsg msg) => state;
}

/// REWRITES an under-floor price up to the floor; drops negatives outright.
final class _FloorGuard extends Guard<_PriceSet> {
  const _FloorGuard();

  @override
  Set<Msg> judge(Envelope env, _PriceSet msg, ReadStore read) {
    final floor = read(const _Floor(10));
    if (msg.value < 0) return const {};
    if (msg.value < floor) return {_PriceSet(msg.id, floor)};
    return {msg};
  }
}

final class _NegativeVeto extends Veto<_PriceSet> {
  const _NegativeVeto();

  @override
  bool block(Envelope env, _PriceSet msg, ReadStore read) => msg.value < 0;
}

/// FANS OUT: a bulk fact becomes one fact per item for the rows below.
class _BulkSet extends _PriceMsg {
  const _BulkSet(this.entries);
  final List<(String, double)> entries;
}

final class _Unbulk extends Guard<_BulkSet> {
  const _Unbulk();

  @override
  Set<Msg> judge(Envelope env, _BulkSet msg, ReadStore read) =>
      {for (final (id, value) in msg.entries) _PriceSet(id, value)};
}

void main() {
  test('a guard REWRITES for the rows below; the row above saw the original',
      () {
    final ledger = Ledger();
    ledger.unit(const _Floor(10));
    final raw = ledger.store(const _Prices()); // above: the original fact
    ledger.guard(const _FloorGuard());
    final floored = ledger.store(const _Prices(1)); // below: the rewrite

    ledger.dispatch(const _PriceSet('a', 3));

    expect(raw['a']?.value, 3); // the journal-true fact
    expect(floored['a']?.value, 10); // the admitted rewrite
  });

  test('a guard DROPS: rows below never fold, the end of the queue is silent',
      () async {
    final ledger = Ledger();
    ledger.unit(const _Floor(10));
    ledger.guard(const _FloorGuard());
    final prices = ledger.store(const _Prices());
    final admitted = <Msg>[];
    ledger.on<Msg>().listen(admitted.add);

    ledger.dispatch(const _PriceSet('a', -1));
    await Future<void>.delayed(Duration.zero);

    expect(prices['a'], isNull);
    expect(admitted, isEmpty);
  });

  test('a Veto is the boolean guard: pass or drop, never rewrite', () {
    final ledger = Ledger();
    ledger.guard(const _NegativeVeto());
    final prices = ledger.store(const _Prices());

    ledger.dispatch(const _PriceSet('a', -1));
    ledger.dispatch(const _PriceSet('b', 5));

    expect(prices['a'], isNull);
    expect(prices['b']?.value, 5);
  });

  test('read is CONFIRMED state — optimistic overlays are invisible to it',
      () {
    final ledger = Ledger();
    final prices = ledger.store(const _Prices());

    ledger.dispatch(const _PriceSet('a', 99),
        optimistic: true, correlationId: 'c1');

    expect(prices['a']?.value, 99); // the effective view projects the overlay
    expect(ledger.read(const _Prices())['a'], isNull); // a judge never sees it
  });

  test('a guard FANS OUT: each returned msg walks the rows below, in order',
      () async {
    final ledger = Ledger();
    final above = ledger.store(const _Prices()); // sees only the bulk fact
    ledger.guard(const _Unbulk());
    final below = ledger.store(const _Prices(1)); // sees the branches
    final seen = <String>[];
    ledger.on<_PriceSet>().listen((m) => seen.add(m.id));

    ledger.dispatch(const _BulkSet([('a', 1), ('b', 2), ('c', 3)]));
    await Future<void>.delayed(Duration.zero);

    expect(above.entities, isEmpty); // the bulk fact folds nothing above
    expect(below['a']?.value, 1);
    expect(below['b']?.value, 2);
    expect(below['c']?.value, 3);
    expect(seen, ['a', 'b', 'c']); // branch order = set order
  });
}
