import 'package:regent/regent.dart';
import 'package:test/test.dart';

sealed class _Msg extends Msg {}

/// Additive: upserts a distinct key. Distinct-key upserts commute.
class _Put extends _Msg {
  _Put(this.id, this.text);
  final String id;
  final String text;
}

/// Last-write-wins on ONE shared key — deliberately order-dependent.
class _SetName extends _Msg {
  _SetName(this.text);
  final String text;
}

/// Counts every message — an order-independent unit, for the ledger snapshot.
class _Tick extends _Msg {}

class _Doc with Identifiable<String> {
  const _Doc(this.id, this.text);
  @override
  final String id;
  final String text;

  @override
  bool operator ==(Object o) => o is _Doc && o.id == id && o.text == text;
  @override
  int get hashCode => Object.hash(id, text);
}

final class _Docs extends Store<String, _Doc, _Msg> {
  const _Docs();

  @override
  IdentifiableMap<String, _Doc> reduce(
          IdentifiableMap<String, _Doc> e, _Msg msg) =>
      switch (msg) {
        _Put(:final id, :final text) => e.upsert(_Doc(id, text)),
        _SetName(:final text) => e.upsert(_Doc('name', text)),
        _Tick() => e,
      };
}

final class _Count extends Unit<int, _Msg> {
  const _Count() : super(0);
  @override
  int reduce(int s, _Msg m) => m is _Put || m is _Tick ? s + 1 : s;
}

enum _Rows with RegentNode<_Rows> {
  docs(_Docs()),
  count(_Count());

  const _Rows(this.regent);
  @override
  final Regent regent;
}

void main() {
  group('replayStore (single store)', () {
    test('additive upserts replay-equal in any order (they commute)', () {
      expect(
        replayStore(const _Docs(), [_Put('x', '1'), _Put('y', '2')]),
        equals(replayStore(const _Docs(), [_Put('y', '2'), _Put('x', '1')])),
      );
    });

    test('last-write-wins is order-dependent (replay proves it with isNot)',
        () {
      expect(
        replayStore(const _Docs(), [_SetName('a'), _SetName('b')]),
        isNot(replayStore(const _Docs(), [_SetName('b'), _SetName('a')])),
      );
    });

    test('idempotence: replaying a message twice equals once', () {
      expect(
        replayStore(const _Docs(), [_Put('x', '1'), _Put('x', '1')]),
        equals(replayStore(const _Docs(), [_Put('x', '1')])),
      );
    });
  });

  group('replay (whole ledger)', () {
    test('snapshots every citizen — store map and unit value', () {
      final s = replay(_Rows.values, [_Put('x', '1'), _Tick()]);
      expect(s[_Rows.docs], {'x': const _Doc('x', '1')});
      expect(s[_Rows.count], 2); // _Put + _Tick both count
    });

    test('order-independent facts converge across the WHOLE ledger', () {
      expect(
        replay(_Rows.values, [_Put('x', '1'), _Tick(), _Put('y', '2')]),
        equals(replay(_Rows.values, [_Tick(), _Put('y', '2'), _Put('x', '1')])),
      );
    });

    test('an order-dependent fact diverges the ledger snapshot', () {
      expect(
        replay(_Rows.values, [_SetName('a'), _SetName('b')]),
        isNot(replay(_Rows.values, [_SetName('b'), _SetName('a')])),
      );
    });
  });
}
