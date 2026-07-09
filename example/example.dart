// The classic todo app, regent-style — compare it with the version you
// already know. Three things to notice:
//
//  1. Messages are FACTS (`TodoAdded`), never calls. Stores fold them.
//  2. The toggle is OPTIMISTIC with no wire ids: the request itself is the
//     prediction (one dispatch sends and folds); the server's echo settles
//     it by state comparison, and silence reverts it — automatically.
//  3. The queue is positional: the veto row above the store drops duplicate
//     adds before the store ever sees them.
import 'package:regent/regent.dart';

// ── The facts ──
sealed class TodoMsg extends Msg {
  const TodoMsg();
}

class TodoAdded extends TodoMsg {
  const TodoAdded(this.id, this.title);
  final String id;
  final String title;
}

/// The intent AND the prediction: dispatching it folds instantly and tells
/// the transport to send — one dispatch, both jobs. Note it states the
/// TARGET (`done: true`), not the operation ("toggle"): verdicts settle by
/// comparing state, so facts should be absolute — re-applying an absolute
/// fact is a no-op, re-applying a toggle never is.
class CompleteTodo extends TodoMsg {
  const CompleteTodo(this.id, {required this.done});
  final String id;
  final bool done;
}

/// The server's echo — the resolver that settles the prediction.
class TodoToggled extends TodoMsg {
  const TodoToggled(this.id, {required this.done});
  final String id;
  final bool done;
}

// ── The state ──
class Todo with Identifiable<String> {
  const Todo(this.id, this.title, {this.done = false});
  @override
  final String id;
  final String title;
  final bool done;

  Todo completed(bool done) => Todo(id, title, done: done);

  // Laws compare replayed states — value equality is the contract.
  @override
  bool operator ==(Object o) =>
      o is Todo && o.id == id && o.title == title && o.done == done;
  @override
  int get hashCode => Object.hash(id, title, done);
}

// ── The store: a pure fold ──
final class Todos extends Store<String, Todo, TodoMsg> {
  const Todos();

  @override
  IdentifiableMap<String, Todo> reduce(
          IdentifiableMap<String, Todo> todos, TodoMsg msg) =>
      switch (msg) {
        TodoAdded(:final id, :final title) => todos.upsert(Todo(id, title)),
        CompleteTodo(:final id, :final done) ||
        TodoToggled(:final id, :final done) =>
          todos.updateById(id, (t) => t.completed(done)),
      };
}

void main() async {
  final ledger = Ledger();

  // Row order is semantics: the veto stands ABOVE the store it protects.
  late final StoreMemory<String, Todo, TodoMsg> todos;
  ledger.veto<TodoAdded>((msg) => todos[msg.id] != null); // duplicates drop
  todos = ledger.store(const Todos());

  ledger.dispatch(const TodoAdded('milk', 'Buy milk'));
  ledger.dispatch(const TodoAdded('milk', 'Buy milk')); // vetoed — a no-op
  ledger.dispatch(const TodoAdded('tea', 'Brew tea'));

  // Optimistic write via command: done flips NOW as a correlated overlay
  // (base untouched); the effect's echo promotes it into base.
  await ledger.command(const CompleteTodo('milk', done: true), effect: () async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return const TodoToggled('milk', done: true); // the fake server's echo
  });
  print('milk done=${todos['milk']!.done} '
      '(${todos.flagsOf('milk')?.stability})'); // true (confirmed)

  // A failing transport rolls the overlay back — base never lied.
  try {
    await ledger.command(const CompleteTodo('tea', done: true),
        effect: () async => throw StateError('offline'));
  } catch (_) {}
  print('tea done=${todos['tea']!.done} '
      '(${todos.flagsOf('tea')?.stability})'); // false (reverted)

  ledger.close();
}
