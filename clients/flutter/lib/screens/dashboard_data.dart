import 'package:flutter/foundation.dart';
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

/// Numbers the Painel shows for Estoque.
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
    this.lowStock = const [],
  });

  /// The steel lookup failed: the steel figures are unknown, not zero.
  /// Materials below their minimum stock (empty when the lookup failed).
  final List<Map<String, dynamic>> lowStock;
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

/// Numbers the Painel shows for Suprimentos.
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

/// Numbers the Painel shows for PCP.
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

/// Numbers the Painel shows for Vendas.
class CommercialDashboard {
  CommercialDashboard({
    required this.kpis,
    required this.stages,
    required this.feasibilityInReview,
    this.pendingInvoice = 0,
    this.shippedAwaiting = 0,
    this.overdueReceivables = 0,
  });

  final Map<String, dynamic> kpis;
  final Map<String, int> stages;
  final int feasibilityInReview;

  /// Deliveries shipped whose NF is still owed ("NF pendente").
  final int pendingInvoice;

  /// Deliveries shipped and not yet confirmed as received.
  final int shippedAwaiting;

  /// Duplicatas past their due date with a balance.
  final int overdueReceivables;

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
  var lowStock = <Map<String, dynamic>>[];
  try {
    lowStock = (await api.get('/api/stock/low-stock') as List).cast<Map<String, dynamic>>();
  } catch (e) {
    debugPrint('dashboard_data: Optional context; the screen works without it: $e');
    // Optional context; the screen works without it.
  }
  try {
    steel = (await api.list('/api/steel/lots', take: 200)).items;
  } catch (e) {
    debugPrint('dashboard_data: lookup failed, using fallback: $e');
    steelUnavailable = true;
  }
  return StockDashboard(
    steelUnavailable: steelUnavailable,
    quarantine: lots.total,
    quarantineLots: lots.items,
    openReservations: (r[1] as PageResult).total,
    lastClosing: closings.isEmpty ? null : closings.first,
    locations: (r[3] as PageResult).total,
    lowStock: lowStock,
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
  // The counts below are extra alerts: a failure leaves them at zero instead of hiding the numbers above.
  Future<int> count(Future<int> Function() read) async {
    try {
      return await read();
    } catch (e) {
      debugPrint('dashboard_data: Optional context; the screen works without it: $e');
      return 0;
    }
  }

  final extra = await Future.wait([
    count(() async {
      final page = await api.list('/api/sales/deliveries', take: 200, query: {'pendingInvoice': true});
      // Without the `needsInvoice` flag the answer cannot be trusted (an old server ignores the filter and sends every delivery).
      if (page.items.isEmpty || !page.items.first.containsKey('needsInvoice')) return 0;
      return page.items.every((e) => e['needsInvoice'] == true) ? page.total : page.items.where((e) => e['needsInvoice'] == true).length;
    }),
    count(() async => (await api.list('/api/sales/deliveries', take: 1, query: {'status': 'Shipped'})).total),
    count(() async => (await api.list('/api/receivables', take: 1, query: {'overdue': true})).total),
  ]);
  return CommercialDashboard(
    kpis: (p['kpis'] as Map?)?.cast<String, dynamic>() ?? const {},
    stages: {for (final s in ((p['stages'] as List?) ?? const []).cast<Map<String, dynamic>>()) '${s['key']}': (s['count'] as num).toInt()},
    feasibilityInReview: (r[1] as PageResult).total,
    pendingInvoice: extra[0],
    shippedAwaiting: extra[1],
    overdueReceivables: extra[2],
  );
}
