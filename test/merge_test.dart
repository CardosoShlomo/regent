import 'package:identifiable/identifiable.dart';
import 'package:regent/regent.dart';
import 'package:test/test.dart';

sealed class _UserMsg extends Msg {}

class _Loaded extends _UserMsg {
  _Loaded(this.id, this.name);
  final String id;
  final String name;
}

class _User with Identifiable<String> {
  const _User(this.id, this.name, {this.bio});
  @override
  final String id;
  final String name;
  final String? bio;
}

final class _Users extends Store<String, _User, _UserMsg> {
  const _Users();

  @override
  IdentifiableMap<String, _User> reduce(
          IdentifiableMap<String, _User> entities, _UserMsg msg) =>
      switch (msg) {
        _Loaded(:final id, :final name) => entities.upsert(_User(id, name)),
      };
}

sealed class _SelfMsg extends Msg {}

class _SignedIn extends _SelfMsg {
  _SignedIn(this.id, this.name, this.bio);
  final String id;
  final String name;
  final String bio;
}

class _SignedOut extends _SelfMsg {}

/// Wearing [Identifiable] IS the claim — the engine compares reads against
/// [id]; no key method exists anywhere.
class _Self with Identifiable<String> {
  const _Self(this.id, this.name, this.bio);
  @override
  final String id;
  final String name;
  final String bio;
}

final class _SelfUnit extends Unit<_Self?, _SelfMsg> {
  const _SelfUnit() : super(null);

  @override
  _Self? reduce(_Self? state, _SelfMsg msg) => switch (msg) {
        _SignedIn(:final id, :final name, :final bio) => _Self(id, name, bio),
        _SignedOut() => null,
      };
}

/// The self's truth answers user reads at her own key — no id comparison in
/// the body: the engine already matched against `self.id`.
final class _SelfSupportsUser extends Projection<_Self, String, _User> {
  const _SelfSupportsUser();

  @override
  _User resolve(_User? row, _Self self) =>
      _User(self.id, self.name, bio: self.bio);
}

void main() {
  test('the claimed key routes to the projection, even on a cold store', () {
    final bus = Bus();
    final users = StoreMemory(const _Users(), bus);
    final self = UnitMemory(const _SelfUnit(), bus);
    users.merge(self, const _SelfSupportsUser());

    expect(users['me'], isNull); // no source yet — the row stands (absent)

    bus.dispatch(_SignedIn('me', 'Me', 'hi'));
    expect(users['me']!.name, 'Me'); // cold store: the projection answers
    expect(users['me']!.bio, 'hi');
    expect(users['other'], isNull); // unclaimed keys untouched

    bus.dispatch(_Loaded('other', 'Other'));
    expect(users['other']!.name, 'Other'); // crowd rows resolve honestly
  });

  test('collection reads stay honest — no phantom rows', () {
    final bus = Bus();
    final users = StoreMemory(const _Users(), bus);
    final self = UnitMemory(const _SelfUnit(), bus);
    users.merge(self, const _SelfSupportsUser());

    bus.dispatch(_SignedIn('me', 'Me', 'hi'));
    expect(users.entities, isEmpty);
    expect(users.values, isEmpty);
  });

  test('a source change re-announces exactly the claimed keys', () {
    final bus = Bus();
    final users = StoreMemory(const _Users(), bus);
    final self = UnitMemory(const _SelfUnit(), bus);
    users.merge(self, const _SelfSupportsUser());
    final announced = <String>[];
    users.changes.listen(announced.add);

    bus.dispatch(_SignedIn('me', 'Me', 'hi'));
    expect(announced, ['me']);

    bus.dispatch(_SignedIn('me2', 'Me2', 'hi')); // account switch: claim moves
    expect(announced, ['me', 'me', 'me2']); // old key released, new answered

    bus.dispatch(_SignedOut());
    expect(announced.last, 'me2'); // the released claim re-announces
    expect(users['me2'], isNull);
  });
}
