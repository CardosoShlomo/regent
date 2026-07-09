import 'package:regent/regent.dart';
import 'package:test/test.dart';

void main() {
  const none = CoveredRanges<num>.none();

  test('empty coverage presumes nothing absent', () {
    expect(none.contains(5), isFalse);
    expect(none.isEmpty, isTrue);
  });

  test('closed edges: a page covers the items AT its boundary cursors', () {
    final c = none.mark(10, 20);
    expect(c.contains(10), isTrue);
    expect(c.contains(20), isTrue);
    expect(c.contains(9), isFalse);
    expect(c.contains(21), isFalse);
  });

  test('overlapping and touching marks merge', () {
    final c = none.mark(10, 20).mark(15, 30).mark(30, 40);
    expect(c.ranges.length, 1);
    expect(c.contains(10), isTrue);
    expect(c.contains(40), isTrue);
  });

  test('disjoint marks stay disjoint — the unfetched hole stays unknown', () {
    final c = none.mark(10, 20).mark(40, 50);
    expect(c.ranges.length, 2);
    expect(c.contains(30), isFalse); // never covered — no claim
  });

  test('open-below marks a final page: everything before hi is known', () {
    final c = none.mark(null, 20);
    expect(c.contains(-1000), isTrue);
    expect(c.contains(20), isTrue);
    expect(c.contains(21), isFalse);
  });

  test('open-below merges with an overlapping bounded range', () {
    final c = none.mark(10, 30).mark(null, 15);
    expect(c.ranges.length, 1);
    expect(c.contains(0), isTrue);
    expect(c.contains(30), isTrue);
  });

  test('mark order is irrelevant — coverage is a join', () {
    final a = none.mark(10, 20).mark(15, 30).mark(null, 12);
    final b = none.mark(null, 12).mark(15, 30).mark(10, 20);
    expect(a, equals(b));
  });

  test('retract withdraws, splitting a straddled interval', () {
    final c = none.mark(10, 50).retract(20, 30);
    expect(c.contains(15), isTrue);
    expect(c.contains(25), isFalse);
    expect(c.contains(40), isTrue);
    expect(c.ranges.length, 2);
  });

  test('retract from an open-below range keeps the tail above', () {
    final c = none.mark(null, 50).retract(null, 30);
    expect(c.contains(10), isFalse);
    expect(c.contains(40), isTrue);
  });

  test('open-above marks a first page: nothing exists past its top', () {
    final c = none.mark(30, null);
    expect(c.contains(30), isTrue);
    expect(c.contains(1000000), isTrue);
    expect(c.contains(29), isFalse);
  });

  test('open-above merges with an overlapping bounded range', () {
    final c = none.mark(10, 40).mark(35, null);
    expect(c.ranges.length, 1);
    expect(c.contains(10), isTrue);
    expect(c.contains(9999), isTrue);
  });

  test('retract a middle span from a fully open range', () {
    final c = none.mark(null, null).retract(20, 30);
    expect(c.contains(10), isTrue);
    expect(c.contains(25), isFalse);
    expect(c.contains(40), isTrue);
  });
}
