import '../../api.dart';
import '../../entities.dart';
import 'models.dart';

class DashboardLoader {
  DashboardLoader(this.api);

  final ApiClient api;

  static final _counted = [products, materials, machines, standardOperations, workCenters, tools];

  Future<DashboardData> engineering() async {
    final pages = await Future.wait(_counted.map((s) => api.list(s.path, take: 1)));
    final all = await api.listAll(products.path);
    return DashboardData({for (var i = 0; i < _counted.length; i++) _counted[i]: pages[i].total}, all);
  }

  Future<StockDashboard> stock() async {
    final r = await Future.wait([
      api.list('/api/stock/lots', take: 8, query: {'status': 'Quarantine'}),
      api.list('/api/stock/reservations', take: 1, query: {'status': 'Open'}),
      api.get('/api/stock/closings'),
      api.list('/api/stock-locations', take: 1),
      api.listAll(materials.path),
      api.listAll('/api/stock/balances'),
    ]);
    final lots = r[0] as PageResult;
    final closings = (r[2] as List).cast<Map<String, dynamic>>();
    final onHand = <int, num>{};
    for (final b in r[5] as List<Map<String, dynamic>>) {
      final id = b['materialId'];
      if (id is int && b['locationKind'] != 'ThirdParty') onHand.update(id, (v) => v + (b['quantity'] as num), ifAbsent: () => b['quantity'] as num);
    }
    final below = [
      for (final m in r[4] as List<Map<String, dynamic>>)
        if (m['active'] != false && m['minStock'] is num && (m['minStock'] as num) > 0 && (onHand[m['id']] ?? 0) < (m['minStock'] as num)) m,
    ];
    return StockDashboard(
      quarantine: lots.total,
      quarantineLots: lots.items,
      openReservations: (r[1] as PageResult).total,
      lastClosing: closings.isEmpty ? null : closings.first,
      locations: (r[3] as PageResult).total,
      belowMinimum: below,
    );
  }

  Future<PurchasingDashboard> purchasing() async {
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

  Future<ProductionDashboard> production() async {
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

  Future<SalesDashboard> sales() async {
    final r = await api.get('/api/sales/pipeline') as Map<String, dynamic>;
    return SalesDashboard.fromJson((r['kpis'] as Map).cast<String, dynamic>());
  }
}
