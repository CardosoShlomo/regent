import 'dart:async';

import 'package:identifiable/identifiable.dart';

import 'envelope.dart';
import 'msg.dart';
import 'store.dart';

/// The cohesive entry point: a JOURNAL (the complete, ungated record every
/// message lands in) and POSTING (guards decide what the ledger ADMITS).
/// Stores reduce the admitted feed and [on] taps the same feed, so a vetoed
/// message still appears in the journal (replay / ring buffer / debug) but
/// never reaches state OR effects — "control without dirtying".
///
/// Dispatch onto the journal (`dispatch`), subscribe to admitted messages
/// (`on`), tap the raw record (`journal.on`), and register stores via `store`.
class Ledger {
  Ledger() {
    // forward EVERY journal message through the posting guards to the registries.
    _sub = journal.envelopesOf<Msg>().listen((r) {
      final (msg, env) = r;
      var e = env;
      for (final g in _guards) {
        final next = g(e.msg, e);
        if (next == null) return; // vetoed at posting — journal keeps it, state doesn't
        e = next;
      }
      _posted.dispatch(e.msg,
          source: e.source, optimistic: e.optimistic, correlationId: e.correlationId);
    });
    // connection state flows to the registries too.
    _connSub = journal.connection.listen(_posted.setConnected);
  }

  /// The complete, ungated record. Dispatch here; tap here for replay/debug.
  final Bus journal = Bus();

  /// The post-guard stream — what the ledger ADMITTED. Stores reduce it and
  /// [on] taps it, so state and effects always see the same feed.
  final Bus _posted = Bus();

  final List<Guard<Msg>> _guards = [];
  final List<void Function(String)> _rollbacks = []; // per-store overlay rollback
  final List<void Function()> _disposers = []; // dispose the stores `close` owns
  int _seq = 0; // monotonic correlation id source (no time/random dependency)
  late final StreamSubscription<Object?> _sub;
  late final StreamSubscription<bool> _connSub;

  /// A PURE posting guard for the [M] family — gate what becomes state without
  /// touching the journal. A non-[M] envelope passes through unchanged.
  void guard<M extends Msg>(Guard<M> g) => _guards
      .add((msg, env) => msg is M ? g(msg, env) : env);

  /// Push a message onto the journal (it then posts through the guards).
  void dispatch(Msg msg,
          {Source? source, bool optimistic = false, String? correlationId}) =>
      journal.dispatch(msg,
          source: source, optimistic: optimistic, correlationId: correlationId);

  /// The MANUAL-STORE door: subscribe to typed messages the ledger ADMITTED —
  /// the exact feed registered stores reduce — and wire your own reduce logic
  /// (a riverpod Notifier, a bloc) where [Store] is too simple. Side-effect
  /// subscribers (snackbars, sounds) belong here too: post-guard, so nothing
  /// fires on a vetoed message.
  ///
  /// A manual store forgoes [StoreMemory]'s machinery — the envelope carries
  /// `optimistic`/`correlationId`, but overlays and [rollback] are on you.
  /// For the complete ungated record (replay/debug/transport), tap
  /// `journal.on<M>` explicitly.
  Stream<M> on<M extends Msg>() => _posted.on<M>();

  /// Like [on], with each message's [Envelope] (provenance/correlation).
  Stream<(M, Envelope)> envelopesOf<M extends Msg>() => _posted.envelopesOf<M>();

  /// Discard the optimistic overlay(s) for [correlationId] across every store —
  /// the prediction failed. Confirmed/superseding writes survive (base is clean).
  void rollback(String correlationId) {
    for (final r in _rollbacks) {
      r(correlationId);
    }
  }

  /// Issue an OPTIMISTIC command: dispatch [optimistic] as a prediction (instant
  /// UI), run [effect] (the app's transport send), and reconcile. The TRANSPORT
  /// is yours — `effect` performs the network call; if it resolves with the
  /// server's confirming message that message is dispatched under the same
  /// correlation id (promoting the overlay into base), and if it returns null the
  /// promotion is left to an inbound push carrying that id. If `effect` throws,
  /// the overlay is rolled back and the error rethrown. Returns the correlation id.
  Future<String> command(Msg optimistic,
      {required Future<Msg?> Function() effect}) async {
    final cid = 'c${_seq++}';
    dispatch(optimistic, optimistic: true, correlationId: cid);
    try {
      final confirmed = await effect();
      if (confirmed != null) dispatch(confirmed, correlationId: cid);
    } catch (_) {
      rollback(cid);
      rethrow;
    }
    return cid;
  }

  /// Report transport connection state (drives stability on every store).
  void setConnected(bool value) => journal.setConnected(value);

  /// A live store for [spec], driven off the post-guard stream.
  StoreMemory<K, E, M> store<K, E extends Identifiable<K>, M extends Msg>(
      Store<K, E, M> spec) {
    final mem = StoreMemory<K, E, M>(spec, _posted);
    _rollbacks.add(mem.rollback);
    _disposers.add(mem.dispose);
    return mem;
  }

  /// A live UNIT store for [spec] (cardinality one, keyless facts).
  ValueMemory<S, M> value<S, M extends Msg>(ValueStore<S, M> spec) {
    final mem = ValueMemory<S, M>(spec, _posted);
    _disposers.add(mem.dispose);
    return mem;
  }

  void close() {
    for (final d in _disposers) {
      d();
    }
    _sub.cancel();
    _connSub.cancel();
    journal.close();
    _posted.close();
  }
}
