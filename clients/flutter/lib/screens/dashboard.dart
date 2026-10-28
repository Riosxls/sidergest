import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities.dart';
import '../session.dart';
import '../api.dart';
import '../widgets/alerts.dart';
import 'orders.dart';
import 'production_orders.dart';
import 'product_detail.dart';
import 'production_floor.dart';
import 'quick_actions.dart';
import 'requisitions.dart';

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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session, this.onNavigate, this.module, this.links = const []});

  final Session session;
  final Navigate? onNavigate;
  final String? module;
  final List<ModuleLink> links;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _maxWidth = 1280.0;
  late Future<DashboardData> _eng = _fetchEngineering();
  late Future<StockDashboard> _stock = _fetchStock();
  late Future<PurchasingDashboard> _purchasing = _fetchPurchasing();
  late Future<ProductionDashboard> _production = _fetchProduction();
  late Future<SalesDashboard> _sales = _fetchSales();
  late Future<List<Object?>> _all = _combine();
  DateTime? _updated;
  final _focus = FocusNode();
  Timer? _timer;

  bool _need(String m) => widget.module == null || widget.module == m;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _settle();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focus.dispose();
    super.dispose();
  }

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

  Future<ProductionDashboard> _fetchProduction() async {
    final api = widget.session.api;
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

  Future<SalesDashboard> _fetchSales() async {
    final r = await widget.session.api.get('/api/sales/pipeline') as Map<String, dynamic>;
    return SalesDashboard.fromJson((r['kpis'] as Map).cast<String, dynamic>());
  }

  Future<Object?> _opt<T>(String m, Future<T> f) => _need(m) ? f.then<Object?>((v) => v, onError: (_) => null) : Future<Object?>.value(null);

  Future<List<Object?>> _combine() => Future.wait<Object?>([
    _opt('engineering', _need('engineering') ? _eng : Future.value(null)),
    _opt('stock', _need('stock') ? _stock : Future.value(null)),
    _opt('purchasing', _need('purchasing') ? _purchasing : Future.value(null)),
    _opt('production', _need('production') ? _production : Future.value(null)),
    _opt('sales', _need('sales') ? _sales : Future.value(null)),
  ]);

  Future<void> _settle() async {
    final d = await _all;
    if (!mounted) return;
    if (widget.module == null) {
      final alerts = _alerts(d);
      widget.session.alerts.value = [for (final a in alerts) AlertInfo(a.icon, a.label, a.count, a.navId, a.filter)];
    }
    setState(() => _updated = DateTime.now());
  }

  Future<void> _refresh() {
    setState(() {
      if (_need('engineering')) _eng = _fetchEngineering();
      if (_need('stock')) _stock = _fetchStock();
      if (_need('purchasing')) _purchasing = _fetchPurchasing();
      if (_need('production')) _production = _fetchProduction();
      if (_need('sales')) _sales = _fetchSales();
      _all = _combine();
    });
    return _settle();
  }

  void Function()? _go(String id, [String? filter]) => widget.onNavigate == null ? null : () => widget.onNavigate!(id, filter);

  Future<void> _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) => _refresh());

  void _openProduct(Map<String, dynamic> p) => _push(ProductDetailScreen(session: widget.session, productId: p['id'] as int));

  void Function() _showList(
    String title,
    List<Map<String, dynamic>> items,
    String Function(Map<String, dynamic>) label,
    void Function(Map<String, dynamic>) open, {
    String? all,
  }) =>
      () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$title (${items.length})'),
          content: SizedBox(
            width: 560,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final e in items)
                  ListTile(
                    dense: true,
                    title: Text(label(e), overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx);
                      open(e);
                    },
                  ),
              ],
            ),
          ),
          actions: [
            if (all != null && widget.onNavigate != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onNavigate!(all);
                },
                child: const Text('Ver todos'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          ],
        ),
      );

  DashboardData? _e(List<Object?> d) => d[0] as DashboardData?;
  StockDashboard? _s(List<Object?> d) => d[1] as StockDashboard?;
  PurchasingDashboard? _p(List<Object?> d) => d[2] as PurchasingDashboard?;
  ProductionDashboard? _o(List<Object?> d) => d[3] as ProductionDashboard?;
  SalesDashboard? _c(List<Object?> d) => d[4] as SalesDashboard?;

  List<_Alert> _alerts(List<Object?> d) {
    final e = _e(d), s = _s(d), p = _p(d), o = _o(d), c = _c(d);
    final late = o == null ? <Map<String, dynamic>>[] : (o.late..sort((a, b) => '${a['dueDate']}'.compareTo('${b['dueDate']}')));
    final overdue = p == null ? <Map<String, dynamic>>[] : ([...p.overdue]..sort((a, b) => (b['daysLate'] as num).compareTo(a['daysLate'] as num)));
    String productLabel(Map<String, dynamic> x) => '${x['code']}  ${x['name']}';
    return [
      if (c != null) ...[
        _Alert('sales', Icons.event_busy_outlined, 'Pedidos atrasados', c.lateOrders, 'sales-orders', null, _go('sales-orders')),
        _Alert('sales', Icons.gavel_outlined, 'Propostas a aprovar', c.pendingApprovals, 'sales-quotes', null, _go('sales-quotes')),
      ],
      if (o != null) ...[
        _Alert(
          'production',
          Icons.schedule,
          'OFs atrasadas',
          late.length,
          'production-orders',
          null,
          _showList(
            'OFs atrasadas',
            late,
            (x) => '${x['reference']} · ${x['productCode']} · ${fmt(x['quantity'])} · ${fmtDay(x['dueDate'])}',
            (x) => openProductionOrder(context, widget.session, x['id'] as int).then((_) => _refresh()),
            all: 'production-orders',
          ),
        ),
        _Alert(
          'production',
          Icons.pause_circle_outline,
          'OFs paradas',
          o.count('Stopped'),
          'production-orders',
          'Stopped',
          _go('production-orders', 'Stopped'),
        ),
      ],
      if (p != null) ...[
        _Alert(
          'purchasing',
          Icons.local_shipping_outlined,
          'Entregas em atraso',
          overdue.length,
          'overdue',
          null,
          _showList(
            'Entregas em atraso',
            overdue,
            (l) => '${l['daysLate']} d · ped. ${l['purchaseOrderNumber']} · ${l['supplierName']} · ${l['description']}',
            (l) => _push(OrderScreen(session: widget.session, id: l['purchaseOrderId'] as int)),
            all: 'overdue',
          ),
        ),
        _Alert(
          'purchasing',
          Icons.assignment_late_outlined,
          'Requisições a aprovar',
          p.pendingApproval,
          'requisitions',
          'PendingApproval',
          _go('requisitions', 'PendingApproval'),
        ),
      ],
      if (s != null) ...[
        _Alert(
          'stock',
          Icons.trending_down,
          'Itens abaixo do mínimo',
          s.belowMinimum.length,
          'balances',
          null,
          _showList(
            'Itens abaixo do mínimo',
            s.belowMinimum,
            (m) => '${m['code']}  ${m['description']} · mín. ${fmt(m['minStock'])}',
            (m) => widget.onNavigate?.call('balances'),
            all: 'balances',
          ),
        ),
        _Alert('stock', Icons.verified_outlined, 'Lotes em quarentena', s.quarantine, 'lots', 'Quarantine', _go('lots', 'Quarantine')),
      ],
      if (e != null) ...[
        _Alert(
          'engineering',
          Icons.block,
          'Produtos bloqueados',
          e.blocked.length,
          products.path,
          null,
          _showList('Produtos bloqueados', e.blocked, productLabel, _openProduct),
        ),
        _Alert(
          'engineering',
          Icons.warning_amber,
          'Produtos sem roteiro',
          e.withoutRouting.length,
          products.path,
          null,
          _showList('Produtos sem roteiro', e.withoutRouting, productLabel, _openProduct),
        ),
      ],
    ].where((a) => a.count > 0).toList();
  }

  static String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _updatedLabel() =>
      _updated == null ? const SizedBox.shrink() : Text('Atualizado às ${_hhmm(_updated!)}', style: Theme.of(context).textTheme.bodySmall);

  Widget _onboarding(List<Object?> d) {
    final e = _e(d), st = _s(d), pu = _p(d), pr = _o(d);
    final steps = [
      ('Cadastrar produtos', 'products', e == null || (e.counts[products] ?? 0) > 0, products.path),
      ('Cadastrar locais de estoque', 'locations', st == null || st.locations > 0, 'locations'),
      (
        'Registrar a primeira requisição ou pedido de compra',
        'purchasing',
        pu == null || pu.pendingApproval + pu.approved + pu.openQuotations + pu.openOrders + pu.overdue.length > 0,
        'requisitions',
      ),
      ('Criar a primeira ordem de fabricação', 'production', pr == null || pr.orders.isNotEmpty || pr.shipments.isNotEmpty, 'production-orders'),
    ];
    final done = steps.where((s) => s.$3).length;
    if (done == steps.length) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        margin: EdgeInsets.zero,
        shape: _cardShape(context),
        color: cs.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.rocket_launch_outlined, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Primeiros passos', style: theme.textTheme.titleMedium)),
                  Text('$done de ${steps.length}', style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: done / steps.length),
              const SizedBox(height: 8),
              for (final s in steps)
                ListTile(
                  key: ValueKey('step-${s.$2}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(s.$3 ? Icons.check_circle : Icons.radio_button_unchecked, color: s.$3 ? cs.primary : cs.onSurfaceVariant),
                  title: Text(
                    s.$1,
                    style: s.$3 ? TextStyle(decoration: TextDecoration.lineThrough, color: cs.onSurfaceVariant) : null,
                  ),
                  trailing: s.$3 || widget.onNavigate == null ? null : FilledButton.tonal(onPressed: _go(s.$4), child: const Text('Abrir')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        ),
        ?trailing,
      ],
    ),
  );

  List<_ModuleCard> _cards(List<Object?> d) {
    final alerts = _alerts(d);
    List<_Alert> alertsOf(String m) => alerts.where((a) => a.module == m).toList();
    final e = _e(d), s = _s(d), p = _p(d), o = _o(d), c = _c(d);
    return [
      for (final m in moduleInfos)
        switch (m.id) {
          'sales' => _ModuleCard(m, c?.openOrders, 'pedidos abertos', alertsOf(m.id), _go(m.navId)),
          'engineering' => _ModuleCard(m, e == null ? null : e.products.length - e.blocked.length, 'produtos ativos', alertsOf(m.id), _go(m.navId)),
          'stock' => _ModuleCard(m, s?.belowMinimum.length, 'itens abaixo do mínimo', alertsOf(m.id), _go(m.navId)),
          'purchasing' => _ModuleCard(m, p?.openOrders, 'OCs pendentes', alertsOf(m.id), _go(m.navId)),
          _ => _ModuleCard(m, o?.count('InProduction'), 'OFs em produção', alertsOf(m.id), _go(m.navId)),
        },
    ];
  }

  List<String> get _order => switch (widget.session.role) {
    'Stock' => ['stock', 'purchasing', 'production', 'engineering', 'sales'],
    'Purchasing' => ['purchasing', 'stock', 'production', 'engineering', 'sales'],
    'Production' => ['production', 'stock', 'purchasing', 'engineering', 'sales'],
    'Sales' || 'SalesManager' => ['sales', 'production', 'stock', 'purchasing', 'engineering'],
    _ => ['sales', 'engineering', 'stock', 'purchasing', 'production'],
  };

  Widget _painel() => FutureBuilder<List<Object?>>(
    future: _all,
    builder: (context, snap) {
      if (!snap.hasData) return const LinearProgressIndicator();
      final d = snap.data!;
      final cards = _cards(d)..sort((a, b) => _order.indexOf(a.info.id).compareTo(_order.indexOf(b.info.id)));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _onboarding(d),
          if (quickActionsFor(widget.session).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final a in quickActionsFor(widget.session))
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: 22)),
                      onPressed: () => a.run(context).then((_) => _refresh()),
                      icon: Icon(a.icon),
                      label: Text(a.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          _heading(
            'Módulos',
            trailing: Row(
              children: [
                _updatedLabel(),
                IconButton(tooltip: 'Atualizar (F5)', onPressed: _refresh, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          _Grid(minColumn: 200, balanced: true, items: [for (final c in cards) _GridItem.sized(c, _ModuleCard.height)]),
        ],
      );
    },
  );

  List<QuickAction> _moduleActions(String m) {
    final s = widget.session;
    return switch (m) {
      'engineering' => [if (s.canWrite) QuickAction(Icons.add_box_outlined, 'Novo produto', (c) => newProduct(c, s))],
      'purchasing' => [
        if (s.canRequest) QuickAction(Icons.post_add, 'Nova requisição', (c) => newRequisition(c, s)),
        if (s.canBuy) QuickAction(Icons.add_shopping_cart, 'Novo pedido', (c) => newPurchaseOrder(c, s)),
      ],
      'production' => [
        if (s.canProduce) QuickAction(Icons.add_task, 'Nova OF', (c) => newProductionOrder(c, s)),
        if (s.canProduce) QuickAction(Icons.edit_note, 'Novo apontamento', (c) => newReport(c, s)),
      ],
      _ => const [],
    };
  }

  List<_GridItem> _kpis(String m, List<Object?> d) {
    switch (m) {
      case 'sales':
        final c = _c(d)!;
        return [
          _GridItem(_Tile(icon: Icons.receipt_long_outlined, label: 'Pedidos abertos', value: '${c.openOrders}', onTap: _go('sales-orders'))),
          _GridItem(_Tile(icon: Icons.request_quote_outlined, label: 'Propostas pendentes', value: '${c.openQuotes}', onTap: _go('sales-quotes'))),
          _GridItem(_Tile(icon: Icons.event_busy_outlined, label: 'Entregas atrasadas', value: '${c.lateOrders}', onTap: _go('sales-orders'))),
          _GridItem(_Tile(icon: Icons.local_shipping_outlined, label: 'Prontos para entregar', value: '${c.readyToShip}', onTap: _go('deliveries'))),
        ];
      case 'engineering':
        final e = _e(d)!;
        final pendingRevision = e.products.where((p) => p['drawingRevision'] == null || p['processRevision'] == null).length;
        return [
          _GridItem(_Tile(icon: Icons.architecture, label: 'Produtos ativos', value: '${e.products.length - e.blocked.length}', onTap: _go(products.path))),
          _GridItem(_Tile(icon: Icons.rate_review_outlined, label: 'Revisões pendentes', value: '$pendingRevision', onTap: _go(products.path))),
          _GridItem(_Tile(icon: Icons.warning_amber, label: 'Sem roteiro', value: '${e.withoutRouting.length}', onTap: _go(products.path))),
          for (final x in e.counts.entries.where((x) => x.key != products))
            _GridItem(_Tile(icon: x.key.icon, label: x.key.title, value: '${x.value}', onTap: _go(x.key.path))),
          _GridItem.panel(_BarPanel(title: 'Produtos por tipo', data: e.countBy((p) => kinds[p['kind']] ?? '—'))),
          _GridItem.panel(_BarPanel(title: 'Produtos por formato', data: e.countBy((p) => shapes[p['shape']] ?? 'Sem formato'))),
          _GridItem.panel(_BarPanel(title: 'Operações por produto', data: e.countBy((p) => _bucket(p['operationCount'] as int? ?? 0)))),
        ];
      case 'stock':
        final s = _s(d)!;
        return [
          _GridItem(_Tile(icon: Icons.trending_down, label: 'Itens abaixo do mínimo', value: '${s.belowMinimum.length}', onTap: _go('balances'))),
          _GridItem(_Tile(icon: Icons.verified_outlined, label: 'Lotes em quarentena', value: '${s.quarantine}', onTap: _go('lots', 'Quarantine'))),
          _GridItem(_Tile(icon: Icons.bookmark_border, label: 'Reservas abertas', value: '${s.openReservations}', onTap: _go('reservations'))),
          _GridItem(
            _Tile(
              icon: Icons.lock_outline,
              label: 'Último mês fechado',
              value: s.lastClosing == null ? '—' : fmtPeriod(s.lastClosing!['period']),
              onTap: _go('closing'),
            ),
          ),
          _GridItem(_Tile(icon: Icons.place_outlined, label: 'Locais de estoque', value: '${s.locations}', onTap: _go('locations'))),
        ];
      case 'purchasing':
        final p = _p(d)!;
        final perf = {for (final x in p.performance.where((x) => (x['receivedLines'] as num) > 0)) '${x['supplierName']}': x['onTimePercent'] as num};
        return [
          _GridItem(
            _Tile(icon: Icons.assignment_outlined, label: 'Requisições abertas', value: '${p.pendingApproval + p.approved}', onTap: _go('requisitions')),
          ),
          _GridItem(_Tile(icon: Icons.receipt_long_outlined, label: 'OCs pendentes', value: '${p.openOrders}', onTap: _go('orders'))),
          _GridItem(
            _Tile(icon: Icons.assignment_turned_in_outlined, label: 'Aprovadas sem cotação', value: '${p.approved}', onTap: _go('requisitions', 'Approved')),
          ),
          _GridItem(_Tile(icon: Icons.request_quote_outlined, label: 'Cotações abertas', value: '${p.openQuotations}', onTap: _go('quotations'))),
          _GridItem.panel(_BarPanel(title: 'Atrasos por fornecedor', data: p.overdueBySupplier)),
          _GridItem.panel(_BarPanel(title: 'Pontualidade 12 meses (%)', data: perf, max: 100)),
        ];
      default:
        final o = _o(d)!;
        return [
          _GridItem(
            _Tile(
              icon: Icons.precision_manufacturing_outlined,
              label: 'OFs em produção',
              value: '${o.count('InProduction')}',
              onTap: _go('production-orders', 'InProduction'),
            ),
          ),
          _GridItem(_Tile(icon: Icons.schedule, label: 'OFs atrasadas', value: '${o.late.length}', onTap: _go('production-orders'))),
          _GridItem(_Tile(icon: Icons.assignment_outlined, label: 'OFs a liberar', value: '${o.count('Created')}', onTap: _go('production-orders', 'Created'))),
          _GridItem(_Tile(icon: Icons.play_circle_outline, label: 'Liberadas', value: '${o.count('Released')}', onTap: _go('production-orders', 'Released'))),
          _GridItem(
            _Tile(icon: Icons.local_shipping_outlined, label: 'Remessas em terceiros', value: '${o.shipments.length}', onTap: _go('outside-processing')),
          ),
          _GridItem.panel(_BarPanel(title: 'Pico de carga 4 semanas (%)', data: o.peakLoad)),
        ];
    }
  }

  Widget _module(ModuleInfo m) {
    final theme = Theme.of(context);
    final actions = _moduleActions(m.id);
    return FutureBuilder<List<Object?>>(
      future: _all,
      builder: (context, snap) {
        final header = Row(
          children: [
            Icon(m.icon, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(m.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            _updatedLabel(),
            IconButton(tooltip: 'Atualizar (F5)', onPressed: _refresh, icon: const Icon(Icons.refresh)),
          ],
        );
        final body = <Widget>[];
        if (!snap.hasData) {
          body.add(const LinearProgressIndicator());
        } else {
          final d = snap.data!;
          final idx = moduleInfos.indexWhere((x) => x.id == m.id);
          const slot = {'engineering': 0, 'stock': 1, 'purchasing': 2, 'production': 3, 'sales': 4};
          if (d[slot[m.id]!] == null) {
            body.add(
              const _Notice(
                icon: Icons.cloud_off_outlined,
                title: 'Indicadores indisponíveis',
                subtitle: 'Não foi possível carregar os dados deste módulo. Tente atualizar.',
              ),
            );
          } else {
            final alerts = _alerts(d).where((a) => a.module == m.id).toList();
            body.addAll([
              if (alerts.isNotEmpty) ...[
                _heading('Atenção'),
                _Grid(
                  items: [for (final a in alerts) _GridItem(_Tile(icon: a.icon, label: a.label, value: '${a.count}', alert: true, onTap: a.onTap))],
                ),
                const SizedBox(height: 16),
              ],
              _heading('Indicadores'),
              _Grid(items: _kpis(m.id, d)),
            ]);
          }
          assert(idx >= 0);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in actions)
                      FilledButton.tonalIcon(onPressed: () => a.run(context).then((_) => _refresh()), icon: Icon(a.icon), label: Text(a.label)),
                  ],
                ),
              ),
            ...body,
            if (widget.links.isNotEmpty) ...[
              const SizedBox(height: 16),
              _heading('Telas de ${m.title}'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final l in widget.links) ActionChip(avatar: Icon(l.icon, size: 18), label: Text(l.title), onPressed: _go(l.id))],
              ),
            ],
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module == null ? null : moduleInfos.firstWhere((m) => m.id == widget.module);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f5): _refresh},
      child: Focus(
        focusNode: _focus,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 32, 16),
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxWidth),
                child: module == null ? _painel() : _module(module),
              ),
            ),
          ),
        ),
      ),
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

class _Alert {
  const _Alert(this.module, this.icon, this.label, this.count, this.navId, this.filter, this.onTap);

  final String module;
  final IconData icon;
  final String label;
  final int count;
  final String navId;
  final String? filter;
  final void Function()? onTap;
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard(this.info, this.metric, this.metricLabel, this.alerts, this.onTap);

  static const height = 160.0;

  final ModuleInfo info;
  final int? metric;
  final String metricLabel;
  final List<_Alert> alerts;
  final void Function()? onTap;

  int get badge => alerts.fold(0, (n, a) => n + a.count);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final alertText = alerts.isEmpty
        ? null
        : alerts.take(2).map((a) => '${a.count} ${a.label.toLowerCase()}').join(' · ') + (alerts.length > 2 ? ' · +${alerts.length - 2}' : '');
    return Semantics(
      button: true,
      label: '${info.title}: ${metric ?? 'indisponível'} $metricLabel',
      excludeSemantics: true,
      child: Card(
        key: ValueKey('module-card-${info.id}'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: _cardShape(context),
        color: cs.surfaceContainerHigh,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(info.icon, size: 28, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(info.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (badge > 0)
                      Tooltip(
                        message: alerts.map((a) => '${a.count} ${a.label.toLowerCase()}').join('\n'),
                        child: Container(
                          key: ValueKey('module-badge-${info.id}'),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            '$badge',
                            style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ],
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: metric == null
                        ? Text('Indisponível', style: TextStyle(color: cs.onSurfaceVariant))
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.bottomLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$metric',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Text(metricLabel, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                                if (alertText != null)
                                  Text(
                                    alertText,
                                    style: theme.textTheme.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.w600),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridItem {
  const _GridItem(this.child) : span = 1, height = _Tile.height;
  const _GridItem.panel(this.child) : span = 2, height = _BarPanel.height;
  const _GridItem.sized(this.child, this.height) : span = 1;

  final Widget child;
  final int span;
  final double height;
}

class _Grid extends StatelessWidget {
  const _Grid({required this.items, this.minColumn = 180, this.balanced = false});

  static const gap = 12.0;

  final double minColumn;
  final bool balanced;
  final List<_GridItem> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      var cols = math.max(1, ((c.maxWidth + gap) / (minColumn + gap)).floor());
      if (balanced && items.isNotEmpty) {
        // Avoid an orphan card on the last row: pick the column count that fills it best.
        if (cols >= items.length) {
          cols = items.length;
        } else {
          var best = cols, bestFill = -1.0;
          for (var k = cols; k >= 2; k--) {
            final rem = items.length % k;
            final fill = rem == 0 ? 1.0 : rem / k;
            if (fill > bestFill) {
              best = k;
              bestFill = fill;
            }
          }
          cols = best;
        }
      }
      final colWidth = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final i in items)
            SizedBox(
              width: (() {
                final span = math.min(i.span, cols);
                return colWidth * span + gap * (span - 1) - 0.01;
              })(),
              height: i.height,
              child: i.child,
            ),
        ],
      );
    },
  );
}

ShapeBorder _cardShape(BuildContext context) => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(12),
  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
);

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.value, this.alert = false, this.onTap});

  static const height = 104.0;

  final IconData icon;
  final String label;
  final String value;
  final bool alert;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = alert ? cs.onErrorContainer : null;
    return Semantics(
      button: onTap != null,
      label: '$value $label',
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: _cardShape(context),
        color: alert ? cs.errorContainer : cs.surfaceContainerHigh,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(alert ? Icons.error_outline : icon, size: 20, color: alert ? cs.onErrorContainer : cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Tooltip(
                        message: label,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                        ),
                      ),
                    ),
                    if (onTap != null) Icon(Icons.chevron_right, size: 18, color: fg ?? cs.onSurfaceVariant),
                  ],
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: fg,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: _cardShape(context),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarPanel extends StatelessWidget {
  const _BarPanel({required this.title, required this.data, this.max});

  static const height = 268.0;

  final String title;
  final Map<String, num> data;
  final num? max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = data.entries.take(8).toList();
    final top = max ?? rows.fold<num>(1, (m, e) => e.value > m ? e.value : m);
    return Card(
      margin: EdgeInsets.zero,
      shape: _cardShape(context),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Expanded(
                child: Center(
                  child: Text('Sem dados ainda', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ),
            for (final e in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 120, child: Text(e.key, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (e.value / top).clamp(0, 1).toDouble(),
                          child: Container(
                            height: 16,
                            decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        fmtNum(e.value, e.value is int ? 0 : 1),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
