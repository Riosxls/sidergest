import 'package:flutter/material.dart';

import '../../entities.dart';
import '../production_orders.dart' show productionLate;

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
    this.belowMinimum = const [],
  });

  final int quarantine;
  final List<Map<String, dynamic>> quarantineLots;
  final int openReservations;
  final Map<String, dynamic>? lastClosing;
  final int locations;
  final List<Map<String, dynamic>> belowMinimum;
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

typedef Navigate = void Function(String id, [String? filter]);

class SalesDashboard {
  SalesDashboard({required this.openOrders, required this.openQuotes, required this.lateOrders, required this.readyToShip, required this.pendingApprovals});

  factory SalesDashboard.fromJson(Map<String, dynamic> k) => SalesDashboard(
    openOrders: (k['openOrders'] as num?)?.toInt() ?? 0,
    openQuotes: (k['openQuotes'] as num?)?.toInt() ?? 0,
    lateOrders: (k['lateOrders'] as num?)?.toInt() ?? 0,
    readyToShip: (k['readyToShip'] as num?)?.toInt() ?? 0,
    pendingApprovals: (k['pendingApprovals'] as num?)?.toInt() ?? 0,
  );

  final int openOrders;
  final int openQuotes;
  final int lateOrders;
  final int readyToShip;
  final int pendingApprovals;
}

class ModuleInfo {
  const ModuleInfo(this.id, this.title, this.icon);

  final String id;
  final String title;
  final IconData icon;

  String get navId => 'module-$id';
}

const moduleInfos = [
  ModuleInfo('sales', 'Comercial', Icons.storefront_outlined),
  ModuleInfo('engineering', 'Engenharia', Icons.architecture),
  ModuleInfo('stock', 'Estoque', Icons.inventory_outlined),
  ModuleInfo('purchasing', 'Suprimentos', Icons.shopping_cart_outlined),
  ModuleInfo('production', 'PCP', Icons.precision_manufacturing_outlined),
];

class ModuleLink {
  const ModuleLink(this.id, this.icon, this.title);

  final String id;
  final IconData icon;
  final String title;
}
