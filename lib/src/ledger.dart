import 'dart:async';

import 'package:identifiable/identifiable.dart';

import 'connection_store.dart';
import 'envelope.dart';
import 'msg.dart';
import 'registry.dart';

/// The cohesive entry point: a JOURNAL (the complete, ungated record every
/// message lands in) and POSTING (guards decide what becomes state). Registries
/// and connections are registered through it and subscribe to the post-guard
/// stream, so a vetoed message still appears in the journal (replay / ring
/// buffer / debug) but never reaches state — "control without dirtying".
///
/// Dispatch onto the journal (`dispatch`), tap the journal for a complete feed
/// (`journal`), and register stores via `registry` / `connection`.
class Ledger {
  Ledger() {
    // forward EVERY journal message through the posting guards to the registries.
    _sub = journal.on<Msg>((msg, env) {
      var e = env;
      for (final g in _guards) {
        final next = g(e);
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

  /// The post-guard stream registries subscribe to. Private — you reach it only
  /// by registering a store.
  final Bus _posted = Bus();

  final List<Guard> _guards = [];
  final List<void Function(String)> _rollbacks = []; // per-store overlay rollback
  int _seq = 0; // monotonic correlation id source (no time/random dependency)
  late final StreamSubscription<Envelope> _sub;
  late final StreamSubscription<bool> _connSub;

  /// A PURE posting guard — gate what becomes state without touching the journal.
  void guard(Guard g) => _guards.add(g);

  /// Push a message onto the journal (it then posts through the guards).
  void dispatch(Msg msg,
          {Source? source, bool optimistic = false, String? correlationId}) =>
      journal.dispatch(msg,
          source: source, optimistic: optimistic, correlationId: correlationId);

  /// Subscribe to typed messages on the journal (the complete feed) — the bus's
  /// listen door. Returns the subscription to cancel.
  StreamSubscription<Envelope> on<M extends Msg>(
          void Function(M msg, Envelope env) handler) =>
      journal.on<M>(handler);

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

  /// A live store for [reg], driven off the post-guard stream.
  RegistryMemory<K, E, M> registry<K, E extends Identifiable<K>, M extends Msg>(
      Registry<K, E, M> reg) {
    final store = RegistryMemory<K, E, M>(reg, _posted);
    _rollbacks.add(store.rollback);
    return store;
  }

  /// A live connection family for [reg], driven off the post-guard stream.
  ConnectionMemory<K, T, I, SK, M> connection<K, T extends Identifiable<I>, I,
              SK extends Comparable<Object?>, M extends Msg>(
          ConnectionRegistry<K, T, I, SK, M> reg) =>
      ConnectionMemory<K, T, I, SK, M>(reg, _posted);

  void close() {
    _sub.cancel();
    _connSub.cancel();
    journal.close();
    _posted.close();
  }
}
