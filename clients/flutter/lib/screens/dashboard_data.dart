import '../api.dart';
import '../entities.dart';

Map<String, int> _intMap(Object? m) => {for (final e in ((m as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()};
List<Map<String, dynamic>> _rows(Object? l) => ((l as List?) ?? const []).cast<Map<String, dynamic>>();

/// Engenharia numbers as the server aggregates them (`GET /api/products/dashboard`): the lists are capped, the totals are not.
class DashboardData {
  DashboardData(
    this.counts, {
    this.total = 0,
    this.byKind = const {},
    this.byShape = const {},
    this.operationBuckets = const {},
    this.blockedTotal = 0,
    this.blocked = const [],
    this.withoutRoutingTotal = 0,
    this.withoutRouting = const [],
  });

  final Map<EntitySpec, int> counts;
  final int total;
  final Map<String, int> byKind;
  final Map<String, int> byShape;

  /// Keys `0`, `1-3`, `4-6`, `7+`.
  final Map<String, int> operationBuckets;
  final int blockedTotal;
  final List<Map<String, dynamic>> blocked;
  final int withoutRoutingTotal;
  final List<Map<String, dynamic>> withoutRouting;
}

/// Late open OFs of one kind: the full count and the first few (by due date) for the alert list.
class LateOrders {
  const LateOrders(this.total, this.items);

  final int total;
  final List<Map<String, dynamic>> items;
}

class StockDashboard {
  StockDashboard({
    required this.quarantine,
    required this.quarantineLots,
    required this.openReservations,
    required this.lastClosing,
    required this.locations,
    this.steelLots = 0,
    this.steelPending = 0,
    this.steelBalanceKg = 0,
    this.steelBalanceValue = 0,
    this.steelUnavailable = false,
  });

  /// The steel lookup failed: the steel figures are unknown, not zero.
  final bool steelUnavailable;
  final int steelLots;
  final int steelPending;
  final num steelBalanceKg;
  final num steelBalanceValue;
  final int quarantine;
  final List<Map<String, dynamic>> quarantineLots;
  final int openReservations;
  final Map<String, dynamic>? lastClosing;
  final int locations;
}

class PurchasingDashboard {
  PurchasingDashboard({
    required this.pendingApproval,
    required this.approved,
    required this.openQuotations,
    required this.openOrders,
    required this.overdue,
    required this.performance,
  });

  final int pendingApproval;
  final int approved;
  final int openQuotations;
  final int openOrders;
  final List<Map<String, dynamic>> overdue;
  final List<Map<String, dynamic>> performance;

  Map<String, num> get overdueBySupplier => overdueBySupplierOf(overdue);

  Map<String, num> overdueBySupplierOf(List<Map<String, dynamic>> lines) {
    final m = <String, num>{};
    for (final l in lines) {
      m.update('${l['supplierName']}', (v) => v + 1, ifAbsent: () => 1);
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }
}

class ProductionDashboard {
  ProductionDashboard({
    required this.openTotal,
    required this.byStatus,
    required this.lateFresh,
    required this.lateLegacy,
    required this.shipments,
    required this.load,
  });

  final int openTotal;
  final Map<String, int> byStatus;
  final LateOrders lateFresh;
  final LateOrders lateLegacy;
  final List<Map<String, dynamic>> shipments;
  final List<Map<String, dynamic>> load;

  int count(String status) => byStatus[status] ?? 0;

  Map<String, num> get peakLoad {
    final m = <String, num>{};
    for (final r in load) {
      final pct = r['loadPercent'] as num;
      m.update('${r['code']}', (v) => pct > v ? pct : v, ifAbsent: () => pct);
    }
    return Map.fromEntries((m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(8));
  }
}

class CommercialDashboard {
  CommercialDashboard({required this.kpis, required this.stages, required this.feasibilityInReview});

  final Map<String, dynamic> kpis;
  final Map<String, int> stages;
  final int feasibilityInReview;

  num k(String key) => (kpis[key] as num?) ?? 0;
}

Future<DashboardData> fetchEngineering(ApiClient api, List<EntitySpec> counted) async {
  final pages = await Future.wait(counted.map((s) => api.list(s.path, take: 1)));
  final p = await api.get('/api/products/dashboard', {'top': 50}) as Map<String, dynamic>;
  return DashboardData(
    {for (var i = 0; i < counted.length; i++) counted[i]: pages[i].total},
    total: (p['total'] as num?)?.toInt() ?? 0,
    byKind: _intMap(p['byKind']),
    byShape: _intMap(p['byShape']),
    operationBuckets: _intMap(p['operationBuckets']),
    blockedTotal: (p['blockedTotal'] as num?)?.toInt() ?? 0,
    blocked: _rows(p['blocked']),
    withoutRoutingTotal: (p['withoutRoutingTotal'] as num?)?.toInt() ?? 0,
    withoutRouting: _rows(p['withoutRouting']),
  );
}

Future<StockDashboard> fetchStock(ApiClient api) async {
  final r = await Future.wait([
    api.list('/api/stock/lots', take: 8, query: {'status': 'Quarantine'}),
    api.list('/api/stock/reservations', take: 1, query: {'status': 'Open'}),
    api.get('/api/stock/closings'),
    api.list('/api/stock-locations', take: 1),
  ]);
  final lots = r[0] as PageResult;
  final closings = (r[2] as List).cast<Map<String, dynamic>>();
  var steel = <Map<String, dynamic>>[];
  var steelUnavailable = false;
  try {
    steel = (await api.list('/api/steel/lots', take: 200)).items;
  } catch (_) {
    steelUnavailable = true;
  }
  return StockDashboard(
    steelUnavailable: steelUnavailable,
    quarantine: lots.total,
    quarantineLots: lots.items,
    openReservations: (r[1] as PageResult).total,
    lastClosing: closings.isEmpty ? null : closings.first,
    locations: (r[3] as PageResult).total,
    steelLots: steel.length,
    steelPending: steel.fold<int>(0, (a, l) => a + ((l['pendingJobs'] as num?)?.toInt() ?? 0)),
    steelBalanceKg: steel.fold<num>(0, (a, l) => a + ((l['balanceKg'] as num?) ?? 0)),
    steelBalanceValue: steel.fold<num>(0, (a, l) => a + ((l['balanceValue'] as num?) ?? 0)),
  );
}

Future<PurchasingDashboard> fetchPurchasing(ApiClient api) async {
  final r = await Future.wait([
    api.list('/api/requisitions', take: 1, query: {'status': 'PendingApproval'}),
    api.list('/api/requisitions', take: 1, query: {'status': 'Approved'}),
    api.list('/api/quotations', take: 1, query: {'status': 'Open'}),
    api.get('/api/purchase-orders/open-summary', {'top': 8}),
    api.get('/api/purchasing/overdue'),
  ]);
  final orders = r[3] as Map<String, dynamic>;
  final now = DateTime.now();
  final from = isoDate(DateTime(now.year - 1, now.month, now.day));
  final supplierIds = ((orders['supplierIds'] as List?) ?? const []).cast<int>();
  final perf = await Future.wait(supplierIds.map((id) => api.get('/api/suppliers/$id/performance', {'from': from, 'to': isoDate(now)})));
  return PurchasingDashboard(
    pendingApproval: (r[0] as PageResult).total,
    approved: (r[1] as PageResult).total,
    openQuotations: (r[2] as PageResult).total,
    openOrders: (orders['total'] as num?)?.toInt() ?? 0,
    overdue: (r[4] as List).cast<Map<String, dynamic>>(),
    performance: perf.cast<Map<String, dynamic>>(),
  );
}

Future<ProductionDashboard> fetchProduction(ApiClient api, {required int legacyDays}) async {
  final now = DateTime.now();
  final r = await Future.wait([
    api.get('/api/production/orders/dashboard', {'legacyDays': legacyDays, 'top': 50}),
    api.get('/api/production/outside-shipments', {'open': true}),
    api.get('/api/production/load', {'from': isoDate(now), 'to': isoDate(now.add(const Duration(days: 27)))}),
  ]);
  final o = r[0] as Map<String, dynamic>;
  LateOrders late(Object? j) {
    final m = j as Map?;
    return LateOrders((m?['total'] as num?)?.toInt() ?? 0, _rows(m?['items']));
  }
  return ProductionDashboard(
    openTotal: (o['openTotal'] as num?)?.toInt() ?? 0,
    byStatus: _intMap(o['byStatus']),
    lateFresh: late(o['lateFresh']),
    lateLegacy: late(o['lateLegacy']),
    shipments: (r[1] as List).cast<Map<String, dynamic>>(),
    load: (r[2] as List).cast<Map<String, dynamic>>(),
  );
}

Future<CommercialDashboard> fetchCommercial(ApiClient api) async {
  final r = await Future.wait([
    api.get('/api/sales/pipeline'),
    api.list('/api/viability', take: 1, query: {'status': 'InReview'}),
  ]);
  final p = r[0] as Map<String, dynamic>;
  return CommercialDashboard(
    kpis: (p['kpis'] as Map?)?.cast<String, dynamic>() ?? const {},
    stages: {for (final s in ((p['stages'] as List?) ?? const []).cast<Map<String, dynamic>>()) '${s['key']}': (s['count'] as num).toInt()},
    feasibilityInReview: (r[1] as PageResult).total,
  );
}
