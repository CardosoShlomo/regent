import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

class _Line with Identifiable<String> {
  _Line(this.id, this.at);
  @override
  final String id;
  final int at;
}

class _Push extends Msg {
  const _Push(this.chat, this.line);
  final String chat;
  final _Line line;
}

final class _Chat extends ConnectionRegistry<String, _Line, String, int, _Push> {
  const _Chat();
  @override
  String keyOf(_Push m) => m.chat;
  @override
  int sortKeyOf(_Line e) => e.at;
  @override
  void apply(Connection<_Line, String, int> c, _Push m) => c.receive(m.line);
}

void main() {
  test('needs() is true until markSurfaced; invalidate re-arms', () {
    final bus = Bus();
    final store = ConnectionMemory(const _Chat(), bus);

    expect(store.needs('a'), isTrue); // page not requested yet
    store.markSurfaced('a');
    expect(store.needs('a'), isFalse); // requested → no re-emit
    store.invalidate('a');
    expect(store.needs('a'), isTrue); // re-armed
  });

  test('a disconnect re-arms needs (loaded pages may be stale)', () {
    final bus = Bus();
    final store = ConnectionMemory(const _Chat(), bus);

    store.markSurfaced('a');
    expect(store.needs('a'), isFalse);
    bus.setConnected(false); // clears surfaced
    expect(store.needs('a'), isTrue); // re-armed by disconnect
  });
}
