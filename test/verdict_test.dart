import 'package:test/test.dart';
import 'package:regent/regent.dart';

sealed class _ProfileMsg extends Msg {
  const _ProfileMsg();
}

/// The prediction (a local fact).
class _SetRadius extends _ProfileMsg {
  const _SetRadius(this.m);
  final int m;
}

/// The server echo: the whole profile (radius + name).
class _Profile extends _ProfileMsg {
  const _Profile(this.radius, this.name);
  final int radius;
  final String name;
}

/// An unrelated same-family fact (touches name only).
class _Renamed extends _ProfileMsg {
  const _Renamed(this.name);
  final String name;
}

class _State {
  const _State(this.radius, this.name);
  final int radius;
  final String name;

  @override
  bool operator ==(Object o) =>
      o is _State && o.radius == radius && o.name == name;
  @override
  int get hashCode => Object.hash(radius, name);
}

final class _RadiusVerdict extends Verdict<_SetRadius, _Profile> {
  const _RadiusVerdict();
  @override
  Duration get deadline => const Duration(milliseconds: 50);
}

final class _Viewer extends Unit<_State, _ProfileMsg> {
  const _Viewer() : super(const _State(500, 'a'));
  @override
  Verdict<_ProfileMsg, Msg> get verdict => const _RadiusVerdict();
  @override
  _State reduce(_State s, _ProfileMsg m) => switch (m) {
        _SetRadius(:final m) => _State(m, s.name),
        _Profile(:final radius, :final name) => _State(radius, name),
        _Renamed(:final name) => _State(s.radius, name),
      };
}

void main() {
  test('a prediction shows instantly and never folds base', () {
    final bus = Bus();
    final unit = UnitMemory(const _Viewer(), bus);
    bus.dispatch(const _SetRadius(5000));
    expect(unit.value.radius, 5000); // instant
    bus.dispatch(const _Renamed('b'));
    expect(unit.value, const _State(5000, 'b')); // overlay rides new base
  });

  test('an echo matching the promise CONFIRMS', () {
    final bus = Bus();
    final unit = UnitMemory(const _Viewer(), bus);
    bus.dispatch(const _SetRadius(5000));
    bus.dispatch(const _Profile(5000, 'a')); // server agrees
    expect(unit.value.radius, 5000);
    expect(unit.reverted, isFalse);
    expect(unit.tampered, isFalse);
  });

  test('an echo keeping the old world REVERTS', () {
    final bus = Bus();
    final unit = UnitMemory(const _Viewer(), bus);
    bus.dispatch(const _SetRadius(5000));
    bus.dispatch(const _Profile(500, 'a')); // server refused
    expect(unit.value.radius, 500); // snapped back
    expect(unit.reverted, isTrue);
  });

  test('a non-resolver fact mid-flight says NOTHING — no tamper, no settle',
      () {
    final bus = Bus();
    final unit = UnitMemory(const _Viewer(), bus);
    bus.dispatch(const _SetRadius(5000));
    bus.dispatch(const _Renamed('b')); // not the resolver family
    expect(unit.tampered, isFalse);
    expect(unit.value, const _State(5000, 'b')); // prediction still riding
    bus.dispatch(const _Profile(5000, 'b')); // the resolver settles it
    expect(unit.tampered, isFalse);
    expect(unit.reverted, isFalse);
    expect(unit.value, const _State(5000, 'b'));
  });

  test('a resolver matching neither TAMPERS and keeps waiting', () {
    final bus = Bus();
    final unit = UnitMemory(const _Viewer(), bus);
    bus.dispatch(const _SetRadius(5000));
    bus.dispatch(const _Profile(500, 'b')); // resolver: neither P0 nor A0
    expect(unit.tampered, isTrue);
    bus.dispatch(const _Profile(5000, 'b')); // a later resolver confirms
    expect(unit.tampered, isFalse);
    expect(unit.reverted, isFalse);
  });

  test('deadline with an elsewhere base settles AMENDED (clamp)', () async {
    final bus = Bus();
    final unit = UnitMemory(const _Viewer(), bus);
    bus.dispatch(const _SetRadius(99999));
    bus.dispatch(const _Profile(10000, 'a')); // server clamped — neither
    expect(unit.tampered, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(unit.amended, isTrue);
    expect(unit.value.radius, 10000); // server truth
  });

  test('deadline with a silent server REVERTS', () async {
    final bus = Bus();
    final unit = UnitMemory(const _Viewer(), bus);
    bus.dispatch(const _SetRadius(5000));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(unit.reverted, isTrue);
    expect(unit.value.radius, 500);
  });

  test('a newer prediction supersedes the pending one', () async {
    final bus = Bus();
    final unit = UnitMemory(const _Viewer(), bus);
    bus.dispatch(const _SetRadius(1000));
    bus.dispatch(const _SetRadius(2000)); // supersede
    expect(unit.value.radius, 2000);
    bus.dispatch(const _Profile(2000, 'a')); // answers the live prediction
    expect(unit.reverted, isFalse);
    expect(unit.value.radius, 2000);
  });
}
