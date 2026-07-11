import 'package:meta/meta.dart';

/// The cursor intervals an authority has covered — a plain folded VALUE,
/// pure and axis-blind (the consumer decides what [C] means: a DateTime, an
/// int, a name). Absence WITHIN a covered interval is a fact ("gone");
/// absence outside is silence.
///
/// Marked intervals are CLOSED — `[lo, hi]` includes both edges, because a
/// page returns the items AT its boundary cursors. A `null` [lo] is
/// open-ended coverage below (a final page: everything before [hi] is
/// known). RETRACTION opens an edge: the remainder around a withdrawn span
/// excludes the boundary cursor itself — a retracted cursor is never still
/// presumed absent.
///
/// Boundary law (from shipped systems' bug history): a limit-truncated page
/// covers only `[cursor-of-last-item, hi]` — never beyond its own items.
/// The CALLER derives bounds from what the page actually holds; this value
/// only stores and queries them.
@immutable
final class CoveredRanges<C extends Comparable<C>> {
  const CoveredRanges._(this._ranges);

  /// No coverage — nothing may be presumed absent.
  const CoveredRanges.none() : _ranges = const [];

  /// Sorted by [hi] (null last), disjoint after merging. A `null` edge is
  /// open-ended; an `xOpen` flag excludes that finite edge (retraction
  /// remainders only — marks are always closed).
  final List<({C? lo, C? hi, bool loOpen, bool hiOpen})> _ranges;

  /// The ranges, for persistence/inspection. Sorted, disjoint.
  List<({C? lo, C? hi, bool loOpen, bool hiOpen})> get ranges => _ranges;

  bool get isEmpty => _ranges.isEmpty;

  /// Coverage extended by `[lo, hi]` (closed; a `null` edge is open-ended).
  /// Overlapping and touching intervals merge; a mark closes any open edge
  /// it reaches.
  CoveredRanges<C> mark(C? lo, C? hi) {
    C? newLo = lo;
    C? newHi = hi;
    var loOpen = false;
    var hiOpen = false;
    final rest = <({C? lo, C? hi, bool loOpen, bool hiOpen})>[];
    for (final r in _ranges) {
      if (_overlaps(newLo, newHi, r.lo, r.hi)) {
        if (_cmpLo(r.lo, newLo) < 0) {
          loOpen = r.loOpen;
          newLo = r.lo;
        } else if (_cmpLo(r.lo, newLo) == 0) {
          loOpen = loOpen && r.loOpen;
        }
        if (_cmpHi(r.hi, newHi) > 0) {
          hiOpen = r.hiOpen;
          newHi = r.hi;
        } else if (_cmpHi(r.hi, newHi) == 0) {
          hiOpen = hiOpen && r.hiOpen;
        }
      } else {
        rest.add(r);
      }
    }
    rest.add((lo: newLo, hi: newHi, loOpen: loOpen, hiOpen: hiOpen));
    rest.sort(_byHi);
    return CoveredRanges._(rest);
  }

  /// Coverage with `[lo, hi]` withdrawn (closed span; a `null` edge is
  /// open-ended) — the expiry/invalidation verb. Splits any interval
  /// straddling the withdrawn span; the remainders' inner edges are OPEN:
  /// after `retract(lo, hi)`, neither [lo] nor [hi] is contained.
  CoveredRanges<C> retract(C? lo, C? hi) {
    final out = <({C? lo, C? hi, bool loOpen, bool hiOpen})>[];
    for (final r in _ranges) {
      if (!_overlaps(lo, hi, r.lo, r.hi)) {
        out.add(r);
        continue;
      }
      if (lo != null && (r.lo == null || r.lo!.compareTo(lo) < 0)) {
        out.add((lo: r.lo, hi: lo, loOpen: r.loOpen, hiOpen: true));
      }
      if (hi != null && (r.hi == null || hi.compareTo(r.hi!) < 0)) {
        out.add((lo: hi, hi: r.hi, loOpen: true, hiOpen: r.hiOpen));
      }
    }
    out.sort(_byHi);
    return CoveredRanges._(out);
  }

  /// Is [cursor] inside any covered interval? THE prune/strip predicate.
  bool contains(C cursor) {
    for (final r in _ranges) {
      final vsLo = r.lo == null ? 1 : cursor.compareTo(r.lo!);
      final vsHi = r.hi == null ? -1 : cursor.compareTo(r.hi!);
      final aboveLo = r.loOpen ? vsLo > 0 : vsLo >= 0;
      final belowHi = r.hiOpen ? vsHi < 0 : vsHi <= 0;
      if (aboveLo && belowHi) return true;
    }
    return false;
  }

  static int _byHi<C extends Comparable<C>>(
      ({C? lo, C? hi, bool loOpen, bool hiOpen}) a,
      ({C? lo, C? hi, bool loOpen, bool hiOpen}) b) {
    if (a.hi == null) return b.hi == null ? 0 : 1;
    if (b.hi == null) return -1;
    return a.hi!.compareTo(b.hi!);
  }

  /// -1/0/1 with null = open below (smallest).
  static int _cmpLo<C extends Comparable<C>>(C? a, C? b) {
    if (a == null) return b == null ? 0 : -1;
    if (b == null) return 1;
    return a.compareTo(b).sign;
  }

  /// -1/0/1 with null = open above (largest).
  static int _cmpHi<C extends Comparable<C>>(C? a, C? b) {
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    return a.compareTo(b).sign;
  }

  static bool _overlaps<C extends Comparable<C>>(
      C? aLo, C? aHi, C? bLo, C? bHi) {
    final aStartsBelowBEnd =
        aLo == null || bHi == null || aLo.compareTo(bHi) <= 0;
    final bStartsBelowAEnd =
        bLo == null || aHi == null || bLo.compareTo(aHi) <= 0;
    return aStartsBelowBEnd && bStartsBelowAEnd;
  }

  @override
  bool operator ==(Object other) {
    if (other is! CoveredRanges<C>) return false;
    if (other._ranges.length != _ranges.length) return false;
    for (var i = 0; i < _ranges.length; i++) {
      if (_ranges[i] != other._ranges[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_ranges);

  @override
  String toString() => 'Covered${[
        for (final r in _ranges)
          '${r.loOpen ? '(' : '['}${r.lo ?? '-∞'}..${r.hi ?? '∞'}${r.hiOpen ? ')' : ']'}'
      ]}';
}
