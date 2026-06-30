import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

class _Count with Identifiable<String> {
  _Count(this.id, this.value);
  @override
  final String id;
  final int value;
}

class _Add extends Msg with Identifiable<String> {
  _Add(this.id, this.by);
  @override
  final String id;
  final int by;
}

final class _Counter extends Registry<String, _Count, _Add> {
  const _Counter();
  @override
  IdentifiableMap<_Count, String> reduce(
          IdentifiableMap<_Count, String> states, _Add m) =>
      states.upsert(_Count(m.id, (states[m.id]?.value ?? 0) + m.by));
}

void main() {
  test('command: effect resolves with the confirming msg → overlay promoted', () async {
    final ledger = Ledger();
    final store = ledger.registry(const _Counter());

    await ledger.command(_Add('a', 5), effect: () async => _Add('a', 5));

    expect(store.confirmed('a')?.value, 5); // promoted into base exactly once
    expect(store.flagsOf('a')?.stability, Stability.confirmed);
    ledger.close();
  });

  test('command: effect throws → overlay rolled back, base untouched', () async {
    final ledger = Ledger();
    final store = ledger.registry(const _Counter());

    await expectLater(
      ledger.command(_Add('a', 5), effect: () async => throw StateError('net')),
      throwsA(isA<StateError>()),
    );

    expect(store['a'], isNull); // prediction discarded, base never written
    ledger.close();
  });

  test('command: push transport (effect returns null) leaves promotion to inbound', () async {
    final ledger = Ledger();
    final store = ledger.registry(const _Counter());

    final cid = await ledger.command(_Add('a', 5), effect: () async => null);
    expect(store['a']?.value, 5); // overlay visible, still pending
    expect(store.flagsOf('a')?.stability, Stability.pending);

    // the server later pushes the confirming message carrying the same id
    ledger.dispatch(_Add('a', 5), correlationId: cid);
    expect(store.confirmed('a')?.value, 5);
    ledger.close();
  });
}
