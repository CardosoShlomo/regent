import 'package:meta/meta.dart';

/// The cursor intervals an authority has covered — a plain folded VALUE,
/// pure and axis-blind (the consumer decides what [C] means: a DateTime, an
/// int, a name). Absence WITHIN a covered interval is a fact ("gone");
/// absence outside is silence.
///
/// Intervals are CLOSED — `[lo, hi]` includes both edges, because a page
/// returns the items AT its boundary cursors. A `null` [lo] is open-ended
/// coverage below (a final page: everything before [hi] is known).
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

  /// Sorted by [hi], disjoint after merging. A `null` lo = open below.
  final List<({C? lo, C hi})> _ranges;

  /// The ranges, for persistence/inspection. Sorted, disjoint.
  List<({C? lo, C hi})> get ranges => _ranges;

  bool get isEmpty => _ranges.isEmpty;

  /// Coverage extended by `[lo, hi]` (closed; `lo == null` = open below).
  /// Overlapping and touching intervals merge.
  CoveredRanges<C> mark(C? lo, C hi) {
    C? newLo = lo;
    C newHi = hi;
    final rest = <({C? lo, C hi})>[];
    for (final r in _ranges) {
      if (_overlaps(newLo, newHi, r.lo, r.hi)) {
        newLo = _minLo(newLo, r.lo);
        newHi = _max(newHi, r.hi);
      } else {
        rest.add(r);
      }
    }
    rest.add((lo: newLo, hi: newHi));
    rest.sort((a, b) => a.hi.compareTo(b.hi));
    return CoveredRanges._(rest);
  }

  /// Coverage with `[lo, hi]` withdrawn — the expiry/invalidation verb.
  /// Splits any interval straddling the withdrawn span.
  CoveredRanges<C> retract(C? lo, C hi) {
    final out = <({C? lo, C hi})>[];
    for (final r in _ranges) {
      if (!_overlaps(lo, hi, r.lo, r.hi)) {
        out.add(r);
        continue;
      }
      // Keep the part of r below the retraction.
      if (lo != null && (r.lo == null || r.lo!.compareTo(lo) < 0)) {
        out.add((lo: r.lo, hi: lo));
      }
      // Keep the part of r above the retraction.
      if (hi.compareTo(r.hi) < 0) {
        out.add((lo: hi, hi: r.hi));
      }
    }
    out.sort((a, b) => a.hi.compareTo(b.hi));
    return CoveredRanges._(out);
  }

  /// Is [cursor] inside any covered interval? THE prune/strip predicate.
  bool contains(C cursor) {
    for (final r in _ranges) {
      final aboveLo = r.lo == null || cursor.compareTo(r.lo!) >= 0;
      if (aboveLo && cursor.compareTo(r.hi) <= 0) return true;
    }
    return false;
  }

  static bool _overlaps<C extends Comparable<C>>(C? aLo, C aHi, C? bLo, C bHi) {
    final aStartsBelowBEnd = aLo == null || aLo.compareTo(bHi) <= 0;
    final bStartsBelowAEnd = bLo == null || bLo.compareTo(aHi) <= 0;
    return aStartsBelowBEnd && bStartsBelowAEnd;
  }

  static C? _minLo<C extends Comparable<C>>(C? a, C? b) =>
      a == null || b == null ? null : (a.compareTo(b) <= 0 ? a : b);

  static C _max<C extends Comparable<C>>(C a, C b) =>
      a.compareTo(b) >= 0 ? a : b;

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
        for (final r in _ranges) '[${r.lo ?? '-∞'}..${r.hi}]'
      ]}';
}
