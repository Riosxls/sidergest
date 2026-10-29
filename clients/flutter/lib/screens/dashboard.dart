import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities.dart';
import '../session.dart';
import '../widgets/alerts.dart';
import 'orders.dart';
import 'production_orders.dart';
import 'product_detail.dart';
import 'production_floor.dart';
import 'quick_actions.dart';
import 'sales_orders.dart';
import 'sales_quotes.dart';
import 'requisitions.dart';
import 'dashboard/cards.dart';
import 'dashboard/loader.dart';
import 'dashboard/models.dart';
import 'dashboard/widgets.dart';

export 'dashboard/models.dart';


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
  late Future<DashboardData> _eng = _loader.engineering();
  late Future<StockDashboard> _stock = _loader.stock();
  late Future<PurchasingDashboard> _purchasing = _loader.purchasing();
  late Future<ProductionDashboard> _production = _loader.production();
  late Future<SalesDashboard> _sales = _loader.sales();
  late Future<List<Object?>> _all = _combine();
  DateTime? _updated;
  final _focus = FocusNode();
  Timer? _timer;
  bool? _tutorialHidden;
  static const _tutorialKey = 'tutorialDismissed';

  DashboardLoader get _loader => DashboardLoader(widget.session.api);

  bool _need(String m) => widget.module == null || widget.module == m;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _loadTutorialPref();
    _settle();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadTutorialPref() async {
    var hidden = false;
    try {
      hidden = (await SharedPreferences.getInstance()).getBool(_tutorialKey) ?? false;
    } catch (_) {}
    if (mounted) setState(() => _tutorialHidden = hidden);
  }

  Future<void> _dismissTutorial() async {
    setState(() => _tutorialHidden = true);
    try {
      await (await SharedPreferences.getInstance()).setBool(_tutorialKey, true);
    } catch (_) {}
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
      if (_need('engineering')) _eng = _loader.engineering();
      if (_need('stock')) _stock = _loader.stock();
      if (_need('purchasing')) _purchasing = _loader.purchasing();
      if (_need('production')) _production = _loader.production();
      if (_need('sales')) _sales = _loader.sales();
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

  List<DashAlert> _alerts(List<Object?> d) {
    final e = _e(d), s = _s(d), p = _p(d), o = _o(d), c = _c(d);
    final late = o == null ? <Map<String, dynamic>>[] : (o.late..sort((a, b) => '${a['dueDate']}'.compareTo('${b['dueDate']}')));
    final overdue = p == null ? <Map<String, dynamic>>[] : ([...p.overdue]..sort((a, b) => (b['daysLate'] as num).compareTo(a['daysLate'] as num)));
    String productLabel(Map<String, dynamic> x) => '${x['code']}  ${x['name']}';
    return [
      if (c != null) ...[
        DashAlert('sales', Icons.event_busy_outlined, 'Pedidos atrasados', c.lateOrders, 'sales-orders', null, _go('sales-orders')),
        DashAlert('sales', Icons.gavel_outlined, 'Propostas a aprovar', c.pendingApprovals, 'sales-quotes', null, _go('sales-quotes')),
      ],
      if (o != null) ...[
        DashAlert(
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
        DashAlert(
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
        DashAlert(
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
        DashAlert(
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
        DashAlert(
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
        DashAlert('stock', Icons.verified_outlined, 'Lotes em quarentena', s.quarantine, 'lots', 'Quarantine', _go('lots', 'Quarantine')),
      ],
      if (e != null) ...[
        DashAlert(
          'engineering',
          Icons.block,
          'Produtos bloqueados',
          e.blocked.length,
          products.path,
          null,
          _showList('Produtos bloqueados', e.blocked, productLabel, _openProduct),
        ),
        DashAlert(
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

  List<QuickAction> _painelActions() {
    final s = widget.session;
    return [
      if (s.canSell) QuickAction(Icons.receipt_long_outlined, 'Novo pedido', (c) => newSalesOrder(c, s)),
      if (s.canSell) QuickAction(Icons.request_quote_outlined, 'Novo Orçamento', (c) => newQuote(c, s)),
      if (s.canProduce) QuickAction(Icons.add_task, 'Nova Ordem de Fabricação', (c) => newProductionOrder(c, s)),
      if (s.canRequest) QuickAction(Icons.post_add, 'Nova requisição de compra', (c) => newRequisition(c, s)),
    ];
  }

  Widget _quickActionsCard() => QuickActionsCard(_painelActions());

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
    if (_tutorialHidden != false) return const SizedBox.shrink();
    return OnboardingCard(steps: steps, onDismiss: _dismissTutorial, onOpen: _go);
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

  List<DashModuleCard> _cards(List<Object?> d) {
    final alerts = _alerts(d);
    int badge(String m) => alerts.where((a) => a.module == m).fold(0, (n, a) => n + a.count);
    final e = _e(d), s = _s(d), p = _p(d), o = _o(d), c = _c(d);
    return [
      for (final m in moduleInfos)
        switch (m.id) {
          'sales' => DashModuleCard(m, c?.openOrders, 'pedidos abertos', badge(m.id), _go(m.navId)),
          'engineering' => DashModuleCard(m, e == null ? null : e.products.length - e.blocked.length, 'produtos ativos', badge(m.id), _go(m.navId)),
          'stock' => DashModuleCard(m, s?.belowMinimum.length, 'itens abaixo do mínimo', badge(m.id), _go(m.navId)),
          'purchasing' => DashModuleCard(m, p?.openOrders, 'OCs pendentes', badge(m.id), _go(m.navId)),
          _ => DashModuleCard(m, o?.count('InProduction'), 'OFs em produção', badge(m.id), _go(m.navId)),
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
          _quickActionsCard(),
          _heading(
            'Módulos',
            trailing: Row(
              children: [
                _updatedLabel(),
                IconButton(tooltip: 'Atualizar (F5)', onPressed: _refresh, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          DashGrid(minColumn: 260, items: [for (final c in cards) DashGridItem.sized(c, DashModuleCard.height)]),
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
        if (s.canProduce) QuickAction(Icons.add_task, 'Nova Ordem de Fabricação', (c) => newProductionOrder(c, s)),
        if (s.canProduce) QuickAction(Icons.edit_note, 'Novo apontamento', (c) => newReport(c, s)),
      ],
      _ => const [],
    };
  }

  List<DashGridItem> _kpis(String m, List<Object?> d) {
    switch (m) {
      case 'sales':
        final c = _c(d)!;
        return [
          DashGridItem(DashTile(icon: Icons.receipt_long_outlined, label: 'Pedidos abertos', value: '${c.openOrders}', onTap: _go('sales-orders'))),
          DashGridItem(DashTile(icon: Icons.request_quote_outlined, label: 'Propostas pendentes', value: '${c.openQuotes}', onTap: _go('sales-quotes'))),
          DashGridItem(DashTile(icon: Icons.event_busy_outlined, label: 'Entregas atrasadas', value: '${c.lateOrders}', onTap: _go('sales-orders'))),
          DashGridItem(DashTile(icon: Icons.local_shipping_outlined, label: 'Prontos para entregar', value: '${c.readyToShip}', onTap: _go('deliveries'))),
        ];
      case 'engineering':
        final e = _e(d)!;
        final pendingRevision = e.products.where((p) => p['drawingRevision'] == null || p['processRevision'] == null).length;
        return [
          DashGridItem(DashTile(icon: Icons.architecture, label: 'Produtos ativos', value: '${e.products.length - e.blocked.length}', onTap: _go(products.path))),
          DashGridItem(DashTile(icon: Icons.rate_review_outlined, label: 'Revisões pendentes', value: '$pendingRevision', onTap: _go(products.path))),
          DashGridItem(DashTile(icon: Icons.warning_amber, label: 'Sem roteiro', value: '${e.withoutRouting.length}', onTap: _go(products.path))),
          for (final x in e.counts.entries.where((x) => x.key != products))
            DashGridItem(DashTile(icon: x.key.icon, label: x.key.title, value: '${x.value}', onTap: _go(x.key.path))),
          DashGridItem.panel(DashBarPanel(title: 'Produtos por tipo', data: e.countBy((p) => kinds[p['kind']] ?? '—'))),
          DashGridItem.panel(DashBarPanel(title: 'Produtos por formato', data: e.countBy((p) => shapes[p['shape']] ?? 'Sem formato'))),
          DashGridItem.panel(DashBarPanel(title: 'Operações por produto', data: e.countBy((p) => _bucket(p['operationCount'] as int? ?? 0)))),
        ];
      case 'stock':
        final s = _s(d)!;
        return [
          DashGridItem(DashTile(icon: Icons.trending_down, label: 'Itens abaixo do mínimo', value: '${s.belowMinimum.length}', onTap: _go('balances'))),
          DashGridItem(DashTile(icon: Icons.verified_outlined, label: 'Lotes em quarentena', value: '${s.quarantine}', onTap: _go('lots', 'Quarantine'))),
          DashGridItem(DashTile(icon: Icons.bookmark_border, label: 'Reservas abertas', value: '${s.openReservations}', onTap: _go('reservations'))),
          DashGridItem(
            DashTile(
              icon: Icons.lock_outline,
              label: 'Último mês fechado',
              value: s.lastClosing == null ? '—' : fmtPeriod(s.lastClosing!['period']),
              onTap: _go('closing'),
            ),
          ),
          DashGridItem(DashTile(icon: Icons.place_outlined, label: 'Locais de estoque', value: '${s.locations}', onTap: _go('locations'))),
        ];
      case 'purchasing':
        final p = _p(d)!;
        final perf = {for (final x in p.performance.where((x) => (x['receivedLines'] as num) > 0)) '${x['supplierName']}': x['onTimePercent'] as num};
        return [
          DashGridItem(
            DashTile(icon: Icons.assignment_outlined, label: 'Requisições abertas', value: '${p.pendingApproval + p.approved}', onTap: _go('requisitions')),
          ),
          DashGridItem(DashTile(icon: Icons.receipt_long_outlined, label: 'OCs pendentes', value: '${p.openOrders}', onTap: _go('orders'))),
          DashGridItem(
            DashTile(icon: Icons.assignment_turned_in_outlined, label: 'Aprovadas sem cotação', value: '${p.approved}', onTap: _go('requisitions', 'Approved')),
          ),
          DashGridItem(DashTile(icon: Icons.request_quote_outlined, label: 'Cotações abertas', value: '${p.openQuotations}', onTap: _go('quotations'))),
          DashGridItem.panel(DashBarPanel(title: 'Atrasos por fornecedor', data: p.overdueBySupplier)),
          DashGridItem.panel(DashBarPanel(title: 'Pontualidade 12 meses (%)', data: perf, max: 100)),
        ];
      default:
        final o = _o(d)!;
        return [
          DashGridItem(
            DashTile(
              icon: Icons.precision_manufacturing_outlined,
              label: 'OFs em produção',
              value: '${o.count('InProduction')}',
              onTap: _go('production-orders', 'InProduction'),
            ),
          ),
          DashGridItem(DashTile(icon: Icons.schedule, label: 'OFs atrasadas', value: '${o.late.length}', onTap: _go('production-orders'))),
          DashGridItem(DashTile(icon: Icons.assignment_outlined, label: 'OFs a liberar', value: '${o.count('Created')}', onTap: _go('production-orders', 'Created'))),
          DashGridItem(DashTile(icon: Icons.play_circle_outline, label: 'Liberadas', value: '${o.count('Released')}', onTap: _go('production-orders', 'Released'))),
          DashGridItem(
            DashTile(icon: Icons.local_shipping_outlined, label: 'Remessas em terceiros', value: '${o.shipments.length}', onTap: _go('outside-processing')),
          ),
          DashGridItem.panel(DashBarPanel(title: 'Pico de carga 4 semanas (%)', data: o.peakLoad)),
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
            IconButton(tooltip: 'Voltar ao Painel', onPressed: _go('dashboard'), icon: const Icon(Icons.arrow_back)),
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
              const DashNotice(
                icon: Icons.cloud_off_outlined,
                title: 'Indicadores indisponíveis',
                subtitle: 'Não foi possível carregar os dados deste módulo. Tente atualizar.',
              ),
            );
          } else {
            final alerts = _alerts(d).where((a) => a.module == m.id).toList();
            body.addAll([
              _heading('Atenção'),
              alerts.isEmpty
                  ? const DashNotice(icon: Icons.check_circle_outline, title: 'Nada pendente', subtitle: 'Nenhum alerta neste módulo.')
                  : DashGrid(
                      items: [for (final a in alerts) DashGridItem(DashTile(icon: a.icon, label: a.label, value: '${a.count}', alert: true, onTap: a.onTap))],
                    ),
              const SizedBox(height: 16),
              _heading('Indicadores'),
              DashGrid(items: _kpis(m.id, d)),
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
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Center(
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

