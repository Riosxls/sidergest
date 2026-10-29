import '../api.dart';
import '../entities.dart';
import 'production_orders.dart';

class DashboardData {
  DashboardData(this.counts, this.products);

  final Map<EntitySpec, int> counts;
  final List<Map<String, dynamic>> products;

  List<Map<String, dynamic>> get withoutRouting => products.where((p) => (p['operationCount'] ?? 0) == 0).toList();
  List<Map<String, dynamic>> get blocked => products.where((p) => p['blocked'] == true).toList();

  Map<String, int> countBy(String Function(Map<String, dynamic>) key) {
    final m = <String, int>{};
    for (final p in products) {
      m.update(key(p), (v) => v + 1, ifAbsent: () => 1);
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }
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
  });

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

  Map<String, num> get overdueBySupplier {
    final m = <String, num>{};
    for (final l in overdue) {
      m.update('${l['supplierName']}', (v) => v + 1, ifAbsent: () => 1);
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }
}

class ProductionDashboard {
  ProductionDashboard({required this.orders, required this.shipments, required this.load});

  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> shipments;
  final List<Map<String, dynamic>> load;

  int count(String status) => orders.where((o) => o['status'] == status).length;
  List<Map<String, dynamic>> get late => orders.where(productionLate).toList();

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
  final all = await api.listAll(products.path);
  return DashboardData({for (var i = 0; i < counted.length; i++) counted[i]: pages[i].total}, all);
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
  try {
    steel = (await api.list('/api/steel/lots', take: 200)).items;
  } catch (_) {}
  return StockDashboard(
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
    api.list('/api/purchase-orders', take: 200, query: {'open': true}),
    api.get('/api/purchasing/overdue'),
  ]);
  final orders = r[3] as PageResult;
  final now = DateTime.now();
  final from = isoDate(DateTime(now.year - 1, now.month, now.day));
  final supplierIds = orders.items.map((o) => o['supplierId'] as int).toSet().take(8);
  final perf = await Future.wait(supplierIds.map((id) => api.get('/api/suppliers/$id/performance', {'from': from, 'to': isoDate(now)})));
  return PurchasingDashboard(
    pendingApproval: (r[0] as PageResult).total,
    approved: (r[1] as PageResult).total,
    openQuotations: (r[2] as PageResult).total,
    openOrders: orders.total,
    overdue: (r[4] as List).cast<Map<String, dynamic>>(),
    performance: perf.cast<Map<String, dynamic>>(),
  );
}

Future<ProductionDashboard> fetchProduction(ApiClient api) async {
  final now = DateTime.now();
  final r = await Future.wait([
    api.listAll('/api/production/orders', query: {'open': true}),
    api.get('/api/production/outside-shipments', {'open': true}),
    api.get('/api/production/load', {'from': isoDate(now), 'to': isoDate(now.add(const Duration(days: 27)))}),
  ]);
  return ProductionDashboard(
    orders: r[0] as List<Map<String, dynamic>>,
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
