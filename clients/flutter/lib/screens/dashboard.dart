import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities.dart';
import '../session.dart';
import '../api.dart';
import '../widgets/actions.dart';
import 'orders.dart';
import 'production_orders.dart';
import 'product_detail.dart';
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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session, this.onNavigate});

  final Session session;
  final Navigate? onNavigate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<DashboardData> _eng = _fetchEngineering();
  late Future<StockDashboard> _stock = _fetchStock();
  late Future<PurchasingDashboard> _purchasing = _fetchPurchasing();
  late Future<ProductionDashboard> _production = _fetchProduction();
  late Future<List<Object?>> _all = _combine();
  DateTime? _updated;
  final _anchors = [for (var i = 0; i < 5; i++) GlobalKey()];
  int? _anchor;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _settle();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
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

  Future<List<Object?>> _combine() =>
      Future.wait<Object?>([_eng, _stock, _purchasing, _production].map((f) => f.then<Object?>((v) => v, onError: (_) => null)));

  Future<void> _settle() async {
    await _all;
    if (mounted) setState(() => _updated = DateTime.now());
  }

  Future<void> _refresh() {
    setState(() {
      _eng = _fetchEngineering();
      _stock = _fetchStock();
      _purchasing = _fetchPurchasing();
      _production = _fetchProduction();
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

  List<_Alert> _alerts(DashboardData? e, StockDashboard? s, PurchasingDashboard? p, ProductionDashboard? o) {
    final late = o == null ? <Map<String, dynamic>>[] : (o.late..sort((a, b) => '${a['dueDate']}'.compareTo('${b['dueDate']}')));
    final overdue = p == null ? <Map<String, dynamic>>[] : ([...p.overdue]..sort((a, b) => (b['daysLate'] as num).compareTo(a['daysLate'] as num)));
    String productLabel(Map<String, dynamic> x) => '${x['code']}  ${x['name']}';
    return [
      if (o != null) ...[
        _Alert(
          Icons.schedule,
          'OFs atrasadas',
          late.length,
          _showList(
            'OFs atrasadas',
            late,
            (x) => '${x['reference']} · ${x['productCode']} · ${fmt(x['quantity'])} · ${fmtDay(x['dueDate'])}',
            (x) => openProductionOrder(context, widget.session, x['id'] as int).then((_) => _refresh()),
            all: 'production-orders',
          ),
        ),
        _Alert(Icons.pause_circle_outline, 'OFs paradas', o.count('Stopped'), _go('production-orders', 'Stopped')),
      ],
      if (p != null) ...[
        _Alert(
          Icons.local_shipping_outlined,
          'Entregas em atraso',
          overdue.length,
          _showList(
            'Entregas em atraso',
            overdue,
            (l) => '${l['daysLate']} d · ped. ${l['purchaseOrderNumber']} · ${l['supplierName']} · ${l['description']}',
            (l) => _push(OrderScreen(session: widget.session, id: l['purchaseOrderId'] as int)),
            all: 'overdue',
          ),
        ),
        _Alert(Icons.assignment_late_outlined, 'Requisições a aprovar', p.pendingApproval, _go('requisitions', 'PendingApproval')),
      ],
      if (s != null) _Alert(Icons.verified_outlined, 'Lotes em quarentena', s.quarantine, _go('lots', 'Quarantine')),
      if (e != null) ...[
        _Alert(Icons.block, 'Produtos bloqueados', e.blocked.length, _showList('Produtos bloqueados', e.blocked, productLabel, _openProduct)),
        _Alert(
          Icons.warning_amber,
          'Produtos sem roteiro',
          e.withoutRouting.length,
          _showList('Produtos sem roteiro', e.withoutRouting, productLabel, _openProduct),
        ),
      ],
    ].where((a) => a.count > 0).toList();
  }

  Widget _attention() {
    return FutureBuilder<List<Object?>>(
      future: _all,
      builder: (context, snap) {
        final theme = Theme.of(context);
        final updated = _updated;
        final header = Row(
          children: [
            Expanded(
              child: Text('Atenção', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (updated != null) Text('Atualizado às ${_hhmm(updated)}', style: theme.textTheme.bodySmall),
            IconButton(tooltip: 'Atualizar (F5)', onPressed: _refresh, icon: const Icon(Icons.refresh)),
          ],
        );
        final Widget content;
        if (!snap.hasData) {
          content = const LinearProgressIndicator();
        } else {
          final d = snap.data!;
          final alerts = _alerts(d[0] as DashboardData?, d[1] as StockDashboard?, d[2] as PurchasingDashboard?, d[3] as ProductionDashboard?);
          content = alerts.isEmpty
              ? _Notice(icon: Icons.check_circle_outline, title: 'Nada pendente', subtitle: 'Nenhuma OF atrasada, entrega em atraso, aprovação ou bloqueio.')
              : _Grid(
                  items: [for (final a in alerts) _GridItem(_Tile(icon: a.icon, label: a.label, value: '${a.count}', alert: true, onTap: a.onTap))],
                );
        }
        return Column(key: _anchors[0], crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, content, const SizedBox(height: 16)]);
      },
    );
  }

  static String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _section<T>(int index, String title, IconData icon, Future<T> future, List<Widget> Function(T data) build) {
    final theme = Theme.of(context);
    return Column(
      key: _anchors[index],
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        FutureBuilder<T>(
          future: future,
          builder: (context, snap) {
            if (snap.hasError) return Text('${snap.error}', style: TextStyle(color: theme.colorScheme.error));
            if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: build(snap.data as T));
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _empty(IconData icon, String title, String subtitle, String action, String nav) =>
      _Notice(icon: icon, title: title, subtitle: subtitle, action: widget.onNavigate == null ? null : action, onAction: _go(nav));

  List<Widget> _engineering(DashboardData d) {
    final masters = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in d.counts.entries) ActionChip(avatar: Icon(e.key.icon, size: 18), label: Text('${e.value} ${e.key.title}'), onPressed: _go(e.key.path)),
      ],
    );
    if ((d.counts[products] ?? 0) == 0) {
      return [
        _empty(
          Icons.inventory_2_outlined,
          'Nenhum produto cadastrado',
          'Cadastre produtos e roteiros para ver os indicadores de engenharia.',
          'Cadastrar produtos',
          products.path,
        ),
        const SizedBox(height: 12),
        masters,
      ];
    }
    return [
      masters,
      const SizedBox(height: 12),
      _Grid(
        items: [
          _GridItem.panel(_BarPanel(title: 'Produtos por tipo', data: d.countBy((p) => kinds[p['kind']] ?? '—'))),
          _GridItem.panel(_BarPanel(title: 'Produtos por formato', data: d.countBy((p) => shapes[p['shape']] ?? 'Sem formato'))),
          _GridItem.panel(_BarPanel(title: 'Operações por produto', data: d.countBy((p) => _bucket(p['operationCount'] as int? ?? 0)))),
        ],
      ),
    ];
  }

  List<Widget> _stockPanels(StockDashboard d) {
    if (d.locations == 0) {
      return [
        _empty(Icons.place_outlined, 'Nenhum local de estoque', 'Cadastre os locais para começar a movimentar o estoque.', 'Cadastrar locais', 'locations'),
      ];
    }
    return [
      _Grid(
        items: [
          _GridItem(_Tile(icon: Icons.bookmark_border, label: 'Reservas abertas', value: '${d.openReservations}', onTap: _go('reservations'))),
          _GridItem(
            _Tile(
              icon: Icons.lock_outline,
              label: 'Último mês fechado',
              value: d.lastClosing == null ? '—' : fmtPeriod(d.lastClosing!['period']),
              onTap: _go('closing'),
            ),
          ),
          _GridItem(_Tile(icon: Icons.place_outlined, label: 'Locais de estoque', value: '${d.locations}', onTap: _go('locations'))),
        ],
      ),
    ];
  }

  List<Widget> _purchasingPanels(PurchasingDashboard d) {
    if (d.pendingApproval + d.approved + d.openQuotations + d.openOrders + d.overdue.length == 0) {
      return [
        _empty(
          Icons.shopping_cart_outlined,
          'Nada em aberto em Suprimentos',
          'Nenhuma requisição, cotação ou pedido de compra em andamento.',
          'Abrir requisições',
          'requisitions',
        ),
      ];
    }
    final perf = {for (final p in d.performance.where((p) => (p['receivedLines'] as num) > 0)) '${p['supplierName']}': p['onTimePercent'] as num};
    return [
      _Grid(
        items: [
          _GridItem(
            _Tile(icon: Icons.assignment_turned_in_outlined, label: 'Aprovadas sem cotação', value: '${d.approved}', onTap: _go('requisitions', 'Approved')),
          ),
          _GridItem(_Tile(icon: Icons.request_quote_outlined, label: 'Cotações abertas', value: '${d.openQuotations}', onTap: _go('quotations'))),
          _GridItem(_Tile(icon: Icons.receipt_long_outlined, label: 'Pedidos abertos', value: '${d.openOrders}', onTap: _go('orders'))),
          _GridItem.panel(_BarPanel(title: 'Atrasos por fornecedor', data: d.overdueBySupplier)),
          _GridItem.panel(_BarPanel(title: 'Pontualidade 12 meses (%)', data: perf, max: 100)),
        ],
      ),
    ];
  }

  List<Widget> _productionPanels(ProductionDashboard d) {
    if (d.orders.isEmpty && d.shipments.isEmpty) {
      return [
        _empty(
          Icons.precision_manufacturing_outlined,
          'Nenhuma OF aberta',
          'Crie ordens de fabricação para acompanhar a produção aqui.',
          'Ordens de fabricação',
          'production-orders',
        ),
      ];
    }
    return [
      _Grid(
        items: [
          _GridItem(_Tile(icon: Icons.assignment_outlined, label: 'OFs a liberar', value: '${d.count('Created')}', onTap: _go('production-orders', 'Created'))),
          _GridItem(_Tile(icon: Icons.play_circle_outline, label: 'Liberadas', value: '${d.count('Released')}', onTap: _go('production-orders', 'Released'))),
          _GridItem(
            _Tile(
              icon: Icons.precision_manufacturing_outlined,
              label: 'Em produção',
              value: '${d.count('InProduction')}',
              onTap: _go('production-orders', 'InProduction'),
            ),
          ),
          _GridItem(
            _Tile(icon: Icons.local_shipping_outlined, label: 'Remessas em terceiros', value: '${d.shipments.length}', onTap: _go('outside-processing')),
          ),
          _GridItem.panel(_BarPanel(title: 'Pico de carga 4 semanas (%)', data: d.peakLoad)),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sections = [
      _section(1, 'Engenharia', Icons.architecture, _eng, _engineering),
      _section(2, 'Estoque', Icons.inventory_outlined, _stock, _stockPanels),
      _section(3, 'Suprimentos', Icons.shopping_cart_outlined, _purchasing, _purchasingPanels),
      _section(4, 'PCP', Icons.precision_manufacturing_outlined, _production, _productionPanels),
    ];
    final order = switch (widget.session.role) {
      'Stock' => [1, 3, 2, 0],
      'Purchasing' => [2, 1, 3, 0],
      'Production' => [3, 1, 2, 0],
      _ => [0, 3, 1, 2],
    };
    final api = widget.session.api;
    final actions = <(IconData, String, Future<void> Function())>[
      if (widget.session.canWrite)
        (
          Icons.add_box_outlined,
          'Novo produto',
          () async {
            final r = await submitForm(
              context,
              api: api,
              title: 'Novo: ${products.singular}',
              fields: products.fields,
              submit: (b) => api.post(products.path, b),
            );
            if (r != null && r['id'] is int && mounted) await _push(ProductDetailScreen(session: widget.session, productId: r['id'] as int));
          },
        ),
      if (widget.session.canProduce) (Icons.add_task, 'Nova OF', () => newProductionOrder(context, widget.session)),
      if (widget.session.canRequest) (Icons.post_add, 'Nova requisição', () => newRequisition(context, widget.session)),
      if (widget.session.canBuy) (Icons.add_shopping_cart, 'Novo pedido', () => newPurchaseOrder(context, widget.session)),
    ];
    final labels = ['Atenção', 'Engenharia', 'Estoque', 'Suprimentos', 'PCP'];
    final jumps = [0, ...order.map((i) => i + 1)];
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f5): _refresh},
      child: Focus(
        autofocus: true,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final a in actions) FilledButton.tonalIcon(onPressed: () => a.$3().then((_) => _refresh()), icon: Icon(a.$1), label: Text(a.$2)),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<int>(
                      emptySelectionAllowed: true,
                      showSelectedIcon: false,
                      segments: [for (final j in jumps) ButtonSegment(value: j, label: Text(labels[j]))],
                      selected: {?_anchor},
                      onSelectionChanged: (v) {
                        if (v.isEmpty) return;
                        setState(() => _anchor = v.first);
                        final ctx = _anchors[v.first].currentContext;
                        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                      },
                    ),
                  ),
                ),
                _attention(),
                for (final i in order) sections[i],
              ],
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
  const _Alert(this.icon, this.label, this.count, this.onTap);

  final IconData icon;
  final String label;
  final int count;
  final void Function()? onTap;
}

class _GridItem {
  const _GridItem(this.child) : span = 1, height = _Tile.height;
  const _GridItem.panel(this.child) : span = 2, height = _BarPanel.height;

  final Widget child;
  final int span;
  final double height;
}

class _Grid extends StatelessWidget {
  const _Grid({required this.items});

  static const gap = 12.0;
  static const minColumn = 180.0;

  final List<_GridItem> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = math.max(1, ((c.maxWidth + gap) / (minColumn + gap)).floor());
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
  const _Notice({required this.icon, required this.title, required this.subtitle, this.action, this.onAction});

  final IconData icon;
  final String title;
  final String subtitle;
  final String? action;
  final void Function()? onAction;

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
                  if (action != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: FilledButton.tonal(onPressed: onAction, child: Text(action!)),
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
