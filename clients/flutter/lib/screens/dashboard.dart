import 'package:flutter/material.dart';

import '../entities.dart';
import '../session.dart';
import '../api.dart';
import 'orders.dart';
import 'product_detail.dart';
import 'stock_lots.dart';

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
  StockDashboard({required this.quarantine, required this.quarantineLots, required this.openReservations, required this.lastClosing, required this.locations});

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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session});

  final Session session;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<DashboardData> _eng = _fetchEngineering();
  late Future<StockDashboard> _stock = _fetchStock();
  late Future<PurchasingDashboard> _purchasing = _fetchPurchasing();

  static final _counted = [products, materials, machines, standardOperations, workCenters, tools];

  Future<DashboardData> _fetchEngineering() async {
    final api = widget.session.api;
    final pages = await Future.wait(_counted.map((s) => api.list(s.path, take: 1)));
    final all = await api.listAll(products.path);
    return DashboardData({for (var i = 0; i < _counted.length; i++) _counted[i]: pages[i].total}, all);
  }

  Future<StockDashboard> _fetchStock() async {
    final api = widget.session.api;
    final r = await Future.wait([
      api.list('/api/stock/lots', take: 8, query: {'status': 'Quarantine'}),
      api.list('/api/stock/reservations', take: 1, query: {'status': 'Open'}),
      api.get('/api/stock/closings'),
      api.list('/api/stock-locations', take: 1),
    ]);
    final lots = r[0] as PageResult;
    final closings = (r[2] as List).cast<Map<String, dynamic>>();
    return StockDashboard(
      quarantine: lots.total,
      quarantineLots: lots.items,
      openReservations: (r[1] as PageResult).total,
      lastClosing: closings.isEmpty ? null : closings.first,
      locations: (r[3] as PageResult).total,
    );
  }

  Future<PurchasingDashboard> _fetchPurchasing() async {
    final api = widget.session.api;
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

  Future<void> _refresh() async {
    setState(() {
      _eng = _fetchEngineering();
      _stock = _fetchStock();
      _purchasing = _fetchPurchasing();
    });
    await Future.wait([_eng, _stock, _purchasing].map((f) => f.then((_) => null, onError: (_) => null)));
  }

  void _openProduct(Map<String, dynamic> p) => Navigator.of(context)
      .push(
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(session: widget.session, productId: p['id'] as int),
        ),
      )
      .then((_) => _refresh());

  double _panelWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - (MediaQuery.sizeOf(context).width >= 900 ? 249 : 0);
    return width >= 1100 ? (width - 64) / 3 : (width >= 700 ? (width - 48) / 2 : width - 32);
  }

  Widget _section<T>(String title, Future<T> future, List<Widget> Function(T data, double panelWidth) build) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      FutureBuilder<T>(
        future: future,
        builder: (context, snap) {
          if (snap.hasError) return Text('${snap.error}', style: TextStyle(color: Theme.of(context).colorScheme.error));
          if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
          return Wrap(spacing: 12, runSpacing: 12, children: build(snap.data as T, _panelWidth(context)));
        },
      ),
      const SizedBox(height: 16),
    ],
  );

  List<Widget> _engineering(DashboardData d, double w) => [
    for (final e in d.counts.entries) _StatCard(icon: e.key.icon, label: e.key.title, value: '${e.value}'),
    _StatCard(icon: Icons.block, label: 'Produtos bloqueados', value: '${d.blocked.length}', alert: d.blocked.isNotEmpty),
    _StatCard(icon: Icons.warning_amber, label: 'Produtos sem roteiro', value: '${d.withoutRouting.length}', alert: d.withoutRouting.isNotEmpty),
    SizedBox(
      width: w,
      child: _BarPanel(title: 'Produtos por tipo', data: d.countBy((p) => kinds[p['kind']] ?? '—')),
    ),
    SizedBox(
      width: w,
      child: _BarPanel(title: 'Produtos por formato', data: d.countBy((p) => shapes[p['shape']] ?? 'Sem formato')),
    ),
    SizedBox(
      width: w,
      child: _BarPanel(title: 'Operações por produto', data: d.countBy((p) => _bucket(p['operationCount'] as int? ?? 0))),
    ),
    SizedBox(
      width: w,
      child: _ListPanel(title: 'Sem roteiro', items: d.withoutRouting, label: (p) => '${p['code']}  ${p['name']}', onTap: _openProduct),
    ),
    SizedBox(
      width: w,
      child: _ListPanel(title: 'Bloqueados', items: d.blocked, label: (p) => '${p['code']}  ${p['name']}', onTap: _openProduct),
    ),
  ];

  List<Widget> _stockPanels(StockDashboard d, double w) => [
    _StatCard(icon: Icons.verified_outlined, label: 'Lotes em quarentena', value: '${d.quarantine}', alert: d.quarantine > 0),
    _StatCard(icon: Icons.bookmark_border, label: 'Reservas abertas', value: '${d.openReservations}'),
    _StatCard(icon: Icons.lock_outline, label: 'Último mês fechado', value: d.lastClosing == null ? '—' : fmtPeriod(d.lastClosing!['period'])),
    _StatCard(icon: Icons.place_outlined, label: 'Locais de estoque', value: '${d.locations}'),
    SizedBox(
      width: w,
      child: _ListPanel(
        title: 'Aguardando inspeção',
        total: d.quarantine,
        items: d.quarantineLots,
        label: (l) => '${l['code']} · ${l['itemCode']} · ${fmt(l['quantity'])} · ${fmtDay(l['receivedOn'])}',
        onTap: (l) => showLotDialog(context, widget.session, l).then((_) => _refresh()),
      ),
    ),
  ];

  List<Widget> _purchasingPanels(PurchasingDashboard d, double w) {
    final perf = {for (final p in d.performance.where((p) => (p['receivedLines'] as num) > 0)) '${p['supplierName']}': p['onTimePercent'] as num};
    final overdue = [...d.overdue]..sort((a, b) => (b['daysLate'] as num).compareTo(a['daysLate'] as num));
    return [
      _StatCard(icon: Icons.assignment_late_outlined, label: 'Requisições a aprovar', value: '${d.pendingApproval}', alert: d.pendingApproval > 0),
      _StatCard(icon: Icons.assignment_turned_in_outlined, label: 'Aprovadas sem cotação', value: '${d.approved}'),
      _StatCard(icon: Icons.request_quote_outlined, label: 'Cotações abertas', value: '${d.openQuotations}'),
      _StatCard(icon: Icons.receipt_long_outlined, label: 'Pedidos abertos', value: '${d.openOrders}'),
      _StatCard(icon: Icons.schedule, label: 'Entregas em atraso', value: '${d.overdue.length}', alert: d.overdue.isNotEmpty),
      SizedBox(
        width: w,
        child: _BarPanel(title: 'Atrasos por fornecedor', data: Map.fromEntries(d.overdueBySupplier.entries.take(8))),
      ),
      SizedBox(
        width: w,
        child: _BarPanel(title: 'Pontualidade 12 meses (%)', data: perf, max: 100),
      ),
      SizedBox(
        width: w,
        child: _ListPanel(
          title: 'Maiores atrasos',
          items: overdue,
          label: (l) => '${l['daysLate']} d · ped. ${l['purchaseOrderNumber']} · ${l['supplierName']} · ${l['description']}',
          onTap: (l) => Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (_) => OrderScreen(session: widget.session, id: l['purchaseOrderId'] as int),
                ),
              )
              .then((_) => _refresh()),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.session.role;
    final sections = [
      _section('Engenharia', _eng, _engineering),
      _section('Estoque', _stock, _stockPanels),
      _section('Suprimentos', _purchasing, _purchasingPanels),
    ];
    final order = switch (role) {
      'Stock' => [1, 2, 0],
      'Purchasing' => [2, 1, 0],
      _ => [0, 1, 2],
    };
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [for (final i in order) sections[i]]),
    );
  }

  static String _bucket(int n) => n == 0
      ? '0'
      : n <= 3
      ? '1–3'
      : n <= 6
      ? '4–6'
      : '7+';
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, this.alert = false});

  final IconData icon;
  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 168,
      child: Card(
        color: alert ? cs.errorContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: alert ? cs.onErrorContainer : cs.primary),
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarPanel extends StatelessWidget {
  const _BarPanel({required this.title, required this.data, this.max});

  final String title;
  final Map<String, num> data;
  final num? max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = max ?? data.values.fold<num>(1, (m, v) => v > m ? v : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (data.isEmpty) const Text('Sem dados'),
            for (final e in data.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 120, child: Text(e.key, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (_, c) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 16,
                            width: c.maxWidth * (e.value / top).clamp(0, 1),
                            decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 56, child: Text(fmtNum(e.value, e.value is int ? 0 : 1), textAlign: TextAlign.right)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListPanel extends StatelessWidget {
  const _ListPanel({required this.title, required this.items, required this.label, required this.onTap, this.total});

  final String title;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) label;
  final void Function(Map<String, dynamic>) onTap;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final count = total ?? items.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('$title ($count)', style: Theme.of(context).textTheme.titleMedium),
            ),
            if (items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nenhum')),
            for (final p in items.take(8))
              ListTile(
                dense: true,
                title: Text(label(p), overflow: TextOverflow.ellipsis),
                onTap: () => onTap(p),
              ),
            if (count > 8) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('+ ${count - 8}')),
          ],
        ),
      ),
    );
  }
}
