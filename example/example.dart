// The COMPLETE tour — every regent capability in one shop:
//
//   1. facts as sealed families (a msg IS a source: its TYPE is its rank)
//   2. stores & units: pure folds, nothing else lives in a memory
//   3. the regents ENUM: row order is traversal order; gates protect below
//   4. guards are LAUNCHERS: `.forward` (drop/rewrite/fan-out below) and
//      `.mint` (derive a NEW round from index 0 — unjournaled, re-derived
//      on replay); the SHADOW LAW: every row folds a sealed GROUP of
//      exactly its facts — no wildcard arms anywhere
//   5. `read(const X())` — judges read the ledger's own state by identity
//   6. an IN-FLIGHT row: request status as honest state, deduped by a gate
//   7. COVERAGE: recorded permission to treat absence as knowledge
//   8. a shadow store + mergeStore: disk cache answers until censored
//   9. a WRITE DOCK: optimism as rows — pending unit, settling gate,
//      deadline as a dispatched FACT (timers live in effects)
//  10. unit-from-unit merge: the pending promise answers reads instantly
//  11. events: effects observe (cause, consequence) atomically
//  12. replay: order-(in)dependence as an executable LAW
//
// ignore_for_file: avoid_print
import 'package:regent/regent.dart';

// ── 1. Facts. The sealed family is the fold contract; the msg's TYPE says
// what it may claim: wire facts state truth, cached facts fill absence,
// policy facts are minted by gates, timeout facts by effects. ──
sealed class ShopMsg extends Msg {
  const ShopMsg();
}

class Product with Identifiable<String> {
  const Product(this.id, this.name, this.addedAt);
  @override
  final String id;
  final String name;
  final int addedAt; // the page cursor

  @override
  bool operator ==(Object o) =>
      o is Product && o.id == id && o.name == name && o.addedAt == addedAt;
  @override
  int get hashCode => Object.hash(id, name, addedAt);
}

/// A cursor page of the catalog — the AUTHORITY over its own window.
class CatalogPage extends ShopMsg implements CatalogMsg, InFlightMsg {
  const CatalogPage(this.products, {required this.hasMore});
  final List<Product> products;
  final bool hasMore;
}

/// The disk cache speaking at boot — may only fill ABSENCE, never overwrite.
class CachedCatalog extends ShopMsg implements LocalCatalogMsg {
  const CachedCatalog(this.products);
  final List<Product> products;
}

/// The request — kept OUT of any reduce family; the in-flight row tracks it.
class LoadCatalog extends ShopMsg implements InFlightMsg {
  const LoadCatalog();
}

/// The gate's RULING — MINTED (never dispatched by hand, never journaled;
/// replay re-derives it from the page): the window a page was exhaustive
/// about, and the known ids it thereby declared gone.
class CatalogRuled extends ShopMsg
    implements CatalogMsg, LocalCatalogMsg {
  const CatalogRuled(this.lo, this.hi, this.gone);
  final int? lo, hi;
  final Set<String> gone;
}

// ── The SHADOW LAW: each row folds a sealed GROUP of exactly its facts —
// a message joins its family by `extends` and its readers by `implements`,
// so every reduce is exhaustive and a new member is a compile error. ──
sealed class CatalogMsg extends Msg {}
sealed class LocalCatalogMsg extends Msg {}
sealed class InFlightMsg extends Msg {}
sealed class ShopWriteMsg extends Msg {}

/// The optimistic PREDICTION (a rename), its wire echo, and the deadline
/// fact an effect's timer would dispatch — the ledger never holds a Timer.
class RenameShop extends ShopMsg implements ShopWriteMsg {
  const RenameShop(this.name);
  final String name;
}

class ShopSaved extends ShopMsg implements ShopWriteMsg {
  const ShopSaved(this.name);
  final String name;
}

class RenameTimedOut extends ShopMsg implements ShopWriteMsg {
  const RenameTimedOut();
}

// ── 2. The folds. A memory holds NOTHING but these. ──

/// The catalog table: wire pages upsert; rulings censor; that's all —
/// and the sealed group says EXACTLY that: no wildcard, nothing unheard.
final class Catalog extends Store<String, Product, CatalogMsg> {
  const Catalog();
  @override
  IdentifiableMap<String, Product> reduce(
          IdentifiableMap<String, Product> rows, CatalogMsg msg) =>
      switch (msg) {
        CatalogPage(:final products) => rows.upsertAll(products),
        CatalogRuled(:final gone) =>
          rows.withoutWhere((id, _) => gone.contains(id)),
      };
}

/// 8. The SHADOW: cache fills absence; authority facts only censor. It may
/// hold LESS truth than the wire, never OTHER.
final class LocalCatalog extends Store<String, Product, LocalCatalogMsg> {
  const LocalCatalog();
  @override
  IdentifiableMap<String, Product> reduce(
          IdentifiableMap<String, Product> rows, LocalCatalogMsg msg) =>
      switch (msg) {
        CachedCatalog(:final products) => {
            for (final p in products)
              if (!rows.containsKey(p.id)) p.id: p,
            ...rows,
          },
        CatalogRuled(:final lo, :final hi, :final gone) =>
          rows.withoutWhere((id, p) =>
              gone.contains(id) ||
              ((lo == null || p.addedAt >= lo) &&
                  (hi == null || p.addedAt <= hi))),
      };
}

final class LocalSupports extends Projection<Product, String, Product> {
  const LocalSupports();
  @override
  Product resolve(Product? row, Product local) => row ?? local;
}

/// 7. COVERAGE as a row: which cursor windows the authority has spoken for.
/// A single-fact row may type on the CONCRETE class — trivially exhaustive.
final class CatalogCoverage extends Unit<CoveredRanges<num>, CatalogRuled> {
  const CatalogCoverage() : super(const CoveredRanges.none());
  @override
  CoveredRanges<num> reduce(CoveredRanges<num> covered, CatalogRuled msg) =>
      covered.mark(msg.lo, msg.hi);
}

/// 6. IN-FLIGHT as a row: the request folds it in, the page folds it out.
final class CatalogInFlight extends Unit<bool, InFlightMsg> {
  const CatalogInFlight() : super(false);
  @override
  bool reduce(bool state, InFlightMsg msg) => switch (msg) {
        LoadCatalog() => true,
        CatalogPage() => false,
      };
}

/// The shop name — a unit; its optimism lives in the dock BESIDE it. Its
/// group is the ONE fact base folds: the prediction isn't a member at all —
/// base never folds a promise, by TYPE.
final class Shop extends Unit<String, ShopSaved> {
  const Shop() : super('corner shop');
  @override
  String reduce(String name, ShopSaved msg) => msg.name;
}

/// 9. The WRITE DOCK's pending row: the promise as honest state.
final class ShopWrite extends Unit<String?, ShopWriteMsg> {
  const ShopWrite() : super(null);
  @override
  String? reduce(String? pending, ShopWriteMsg msg) => switch (msg) {
        RenameShop(:final name) => name,
        ShopSaved() || RenameTimedOut() => null,
      };
}

/// 10. The dock's merge edge: reads show the promise until it settles.
final class WriteSupportsShop extends UnitProjection<String?, String> {
  const WriteSupportsShop();
  @override
  String resolve(String value, String? pending) => pending ?? value;
}

// ── 4/5. The gates. Judges of the flow: they fold nothing, hold nothing,
// and decide what every row BELOW sees — reading the ledger by identity. ──

/// A duplicate ask is queue noise — dropped before it can reach the wire.
final class DedupeLoad extends Guard<LoadCatalog> {
  const DedupeLoad();
  @override
  Set<Judgment> judge(LoadCatalog msg, ReadStore read) =>
      read(const CatalogInFlight()) ? const {} : {.forward(msg)};
}

/// The CACHE gate: a cached product inside a COVERED window is a corpse —
/// the authority already ruled there; strip it before any row folds it.
/// (Without this row the replay law below prints false: the ledger's laws
/// catch a missing citizen the moment you state them.)
final class StripCachedCatalog extends Guard<CachedCatalog> {
  const StripCachedCatalog();
  @override
  Set<Judgment> judge(CachedCatalog msg, ReadStore read) {
    final covered = read(const CatalogCoverage());
    return {
      .forward(CachedCatalog(
          [for (final p in msg.products) if (!covered.contains(p.addedAt)) p])),
    };
  }
}

/// The PAGE gate: resolves what window this page was exhaustive about and
/// MINTS one policy fact — the known ids inside it that went unlisted are
/// GONE (covered absence is knowledge, not silence). The mint is the
/// upward door: it runs as its own round from index 0, unjournaled, and
/// replay re-derives it — a fact the fold already implies, stated as one.
final class RuleCatalogPage extends Guard<CatalogPage> {
  const RuleCatalogPage();
  @override
  Set<Judgment> judge(CatalogPage msg, ReadStore read) {
    if (msg.products.isEmpty) return {.forward(msg)};
    final cursors = [for (final p in msg.products) p.addedAt]..sort();
    final lo = msg.hasMore ? cursors.first : null; // final page: open below
    final hi = cursors.last;
    final listed = {for (final p in msg.products) p.id};
    final known = {
      ...read(const LocalCatalog()),
      ...read(const Catalog()),
    };
    return {
      .forward(msg),
      .mint(CatalogRuled(lo, hi, {
        for (final p in known.values)
          if (!listed.contains(p.id) &&
              (lo == null || p.addedAt >= lo) &&
              p.addedAt <= hi)
            p.id,
      })),
    };
  }
}

// ── 3. The CITIZENS enum: row order IS the queue. Gates stand above what
// they protect; the dock and its unit close the file. ──
enum Rows with RegentNode<Rows> {
  dedupeLoad(DedupeLoad()),
  inFlight(CatalogInFlight()),
  stripCachedCatalog(StripCachedCatalog()),
  ruleCatalogPage(RuleCatalogPage()),
  coverage(CatalogCoverage()),
  localCatalog(LocalCatalog()),
  catalog(Catalog()),
  shopWrite(ShopWrite()),
  shop(Shop());

  const Rows(this.regent);
  @override
  final Regent regent;
}

void main() {
  final ledger = Ledger.of(Rows.values);
  final catalog = ledger.memoryOf(Rows.catalog)
      as StoreMemory<String, Product, CatalogMsg>;
  final local = ledger.memoryOf(Rows.localCatalog)
      as StoreMemory<String, Product, LocalCatalogMsg>;
  final shop = ledger.memoryOf(Rows.shop) as UnitMemory<String, ShopSaved>;
  final write =
      ledger.memoryOf(Rows.shopWrite) as UnitMemory<String?, ShopWriteMsg>;
  // 8/10. Merge edges — read-time, never copied state.
  catalog.mergeStore(local, const LocalSupports());
  shop.merge(write, const WriteSupportsShop());

  // 11. An effect: observes post-fold, atomically (cause, consequence).
  // Taps deliver ASYNC — after the synchronous script below, each seeing a
  // consistent cut; an effect's own dispatches enter like any other fact.
  catalog.events.listen((e) =>
      print('  event: ${e.msg.runtimeType} → ${e.after.length} products'));

  // Boot: the cache fills absence…
  ledger.dispatch(const CachedCatalog(
      [Product('p1', 'kettle', 10), Product('p2', 'ghost teapot', 20)]));
  // …asks dedupe through the in-flight row…
  ledger.dispatch(const LoadCatalog());
  ledger.dispatch(const LoadCatalog()); // dropped by the gate
  // …and the authority's final page RULES: the unlisted teapot inside its
  // window is gone, from the main AND the shadow.
  ledger.dispatch(const CatalogPage(
      [Product('p1', 'kettle', 10), Product('p3', 'mug', 30)],
      hasMore: false));
  print('catalog: ${[for (final p in catalog.values) p.name]}');
  print('covered 20? ${(ledger.read(const CatalogCoverage())).contains(20)}');

  // 9/10. The dock: the promise shows instantly, base never lied, the echo
  // settles — and a silent server would settle via a timeout FACT instead.
  ledger.dispatch(const RenameShop('corner shop & co'));
  print('shop reads "${shop.value}", base holds "${ledger.read(const Shop())}"');
  ledger.dispatch(const ShopSaved('corner shop & co'));
  print('settled: "${shop.value}"');

  // 12. The LAW: cache-vs-authority converges in either order.
  final a = replay(Rows.values, [
    const CachedCatalog([Product('p2', 'ghost teapot', 20)]),
    const CatalogPage([Product('p3', 'mug', 30)], hasMore: false),
  ]);
  final b = replay(Rows.values, [
    const CatalogPage([Product('p3', 'mug', 30)], hasMore: false),
    const CachedCatalog([Product('p2', 'ghost teapot', 20)]),
  ]);
  print('replay converges: ${_equal(a, b)}');

  ledger.close();
}

bool _equal(LedgerState<Rows> a, LedgerState<Rows> b) =>
    Rows.values.every((r) => '${a[r]}' == '${b[r]}');
