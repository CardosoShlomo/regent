import 'package:test/test.dart';
import 'package:ledger/ledger.dart';

class _CountState with Identifiable<String> {
  _CountState(this.id, this.value);
  @override
  final String id;
  final int value;
}

sealed class _CountMsg extends Msg {
  const _CountMsg();
}

class _Inc extends _CountMsg with Identifiable<String> {
  _Inc(this.id, this.by);
  @override
  final String id;
  final int by;
}

class _Reset extends _CountMsg with Identifiable<String> {
  _Reset(this.id);
  @override
  final String id;
}

final class _Counter extends Registry<String, _CountState, _CountMsg> {
  const _Counter();
  @override
  IdentifiableMap<_CountState, String> reduce(
          IdentifiableMap<_CountState, String> entities, _CountMsg m) =>
      switch (m) {
        _Inc(:final id, :final by) =>
          entities.upsert(_CountState(id, (entities[id]?.value ?? 0) + by)),
        _Reset(:final id) => entities.removeById(id),
      };
}

void main() {
  test('journal records everything; a posting guard gates what becomes state',
      () {
    final ledger = Ledger();
    final counter = ledger.registry(const _Counter());

    final journalSeen = <Object>[];
    ledger.journal.on<Msg>((m, e) => journalSeen.add(m));

    ledger.guard((e) => e.msg is _Reset ? null : e); // drop resets at posting

    ledger.dispatch(_Inc('a', 5));
    ledger.dispatch(_Reset('a')); // vetoed at posting

    expect(counter['a']?.value, 5); // reset never posted to state
    expect(journalSeen.length, 2); // …but the journal kept BOTH (complete record)
  });

  test('a registered registry receives posted messages and stamps stability', () {
    final ledger = Ledger();
    final counter = ledger.registry(const _Counter());
    ledger.dispatch(_Inc('a', 3));
    expect(counter['a']?.value, 3);
    expect(counter.flagsOf('a')?.stability, Stability.confirmed);
  });

  test('connection state flows through to the stores', () {
    final ledger = Ledger();
    final counter = ledger.registry(const _Counter());
    ledger.dispatch(_Inc('a', 1));
    ledger.setConnected(false); // disconnect → confirmed entries go stale
    expect(counter.flagsOf('a')?.stability, Stability.stale);
  });
}
