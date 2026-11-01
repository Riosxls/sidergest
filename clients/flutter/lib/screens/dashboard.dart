import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities.dart';
import '../session.dart';
import '../widgets/alerts.dart';
import '../widgets/dash.dart';
import 'backup_alert.dart';
import 'dashboard_data.dart';
import 'orders.dart';
import 'product_detail.dart';
import 'production_orders.dart';
import 'quick_actions.dart';

typedef Navigate = void Function(String id, [String? filter]);

/// Static description of a module card on the Painel (section, icon and blurb).
class ModuleInfo {
  const ModuleInfo(this.section, this.icon, this.blurb);

  final String section;
  final IconData icon;
  final String blurb;

  String get id => 'module:$section';
}

const modules = [
  ModuleInfo('Comercial', Icons.storefront_outlined, 'Propostas, pedidos, entregas e análises de viabilidade'),
  ModuleInfo('Engenharia', Icons.architecture, 'Produtos, materiais, roteiros e estruturas'),
  ModuleInfo('Estoque', Icons.inventory_outlined, 'Saldos, lotes, reservas e controle de aço'),
  ModuleInfo('Suprimentos', Icons.shopping_cart_outlined, 'Requisições, cotações, pedidos e recebimentos'),
  ModuleInfo('PCP', Icons.precision_manufacturing_outlined, 'Ordens de fabricação, apontamentos e carga'),
];

ModuleInfo moduleBySection(String section) => modules.firstWhere((m) => m.section == section);

List<ModuleInfo> modulesFor(String? role) {
  final first = switch (role) {
    'Engineering' => 'Engenharia',
    'Stock' => 'Estoque',
    'Purchasing' => 'Suprimentos',
    'Production' => 'PCP',
    _ => 'Comercial',
  };
  return [moduleBySection(first), ...modules.where((m) => m.section != first)];
}

final dashboardCounted = [products, materials, machines, standardOperations, workCenters, tools];

/// Overdue items older than this are treated as legacy backlog: shown, but not counted as a fresh alarm.
const legacyOverdueDays = 30;

/// One alert shown on the Painel and in the bell, with the screen it opens.
class DashAlert {
  const DashAlert(this.module, this.icon, this.label, this.count, this.navId, this.filter, this.onTap, {this.muted = false});

  /// A known backlog (imported legacy): drawn neutral, left out of the bell and the module badge.
  final bool muted;
  final String module;
  final IconData icon;
  final String label;
  final int count;
  final String navId;
  final String? filter;
  final void Function()? onTap;
}

List<DashAlert> buildAlerts(
  BuildContext context, {
  required Session session,
  required Future<void> Function() refresh,
  Navigate? go,
  DashboardData? eng,
  StockDashboard? stock,
  PurchasingDashboard? purchasing,
  ProductionDashboard? production,
  CommercialDashboard? commercial,
}) {
  void Function()? to(String id, [String? filter]) => go == null ? null : () => go(id, filter);
  Future<void> push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) => refresh());

  void Function() showList(
    String title,
    List<Map<String, dynamic>> items,
    String Function(Map<String, dynamic>) label,
    void Function(Map<String, dynamic>) open, {
    String? all,
    int? total,
  }) =>
      () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$title (${total ?? items.length})'),
          content: SizedBox(
            width: 560,
            child: ListView(
              shrinkWrap: true,
              children: [
                // The server caps the list; say so and send the user to the full screen.
                if (total != null && total > items.length)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Mostrando as ${items.length} primeiras de $total.', style: Theme.of(ctx).textTheme.bodySmall),
                  ),
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
            if (all != null && go != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  go(all);
                },
                child: const Text('Ver todos'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          ],
        ),
      );

  final late = production?.lateFresh ?? const LateOrders(0, []);
  final lateLegacy = production?.lateLegacy ?? const LateOrders(0, []);
  final allOverdue = purchasing == null
      ? <Map<String, dynamic>>[]
      : ([...purchasing.overdue]..sort((a, b) => (b['daysLate'] as num).compareTo(a['daysLate'] as num)));
  final overdue = allOverdue.where((l) => (l['daysLate'] as num) <= legacyOverdueDays).toList();
  final overdueLegacy = allOverdue.where((l) => (l['daysLate'] as num) > legacyOverdueDays).toList();
  String productLabel(Map<String, dynamic> x) => '${x['code']}  ${x['name']}';
  void openProduct(Map<String, dynamic> p) => push(ProductDetailScreen(session: session, productId: p['id'] as int));
  return [
    if (commercial != null) ...[
      DashAlert(
        'Comercial',
        Icons.event_busy_outlined,
        'Pedidos de venda atrasados',
        commercial.k('lateOrders').toInt(),
        'sales-orders',
        null,
        to('sales-orders'),
      ),
      DashAlert('Comercial', Icons.gavel_outlined, 'Orçamentos a aprovar', commercial.k('pendingApprovals').toInt(), 'sales-quotes', null, to('sales-quotes')),
      DashAlert(
        'Comercial',
        Icons.draw_outlined,
        'Análises de viabilidade em assinatura',
        commercial.feasibilityInReview,
        'viability',
        'InReview',
        to('viability', 'InReview'),
      ),
    ],
    if (production != null) ...[
      DashAlert(
        'PCP',
        Icons.schedule,
        'OFs atrasadas',
        late.total,
        'production-orders',
        null,
        showList(
          'OFs atrasadas',
          late.items,
          (x) => '${x['reference']} · ${x['productCode']} · ${fmt(x['quantity'])} · ${fmtDay(x['dueDate'])}',
          (x) => openProductionOrder(context, session, x['id'] as int).then((_) => refresh()),
          all: 'production-orders',
          total: late.total,
        ),
      ),
      DashAlert(
        'PCP',
        Icons.history,
        'OFs atrasadas há mais de $legacyOverdueDays dias',
        lateLegacy.total,
        'production-orders',
        null,
        showList(
          'OFs atrasadas há mais de $legacyOverdueDays dias',
          lateLegacy.items,
          (x) => '${x['reference']} · ${x['productCode']} · ${fmt(x['quantity'])} · ${fmtDay(x['dueDate'])}',
          (x) => openProductionOrder(context, session, x['id'] as int).then((_) => refresh()),
          all: 'production-orders',
          total: lateLegacy.total,
        ),
        muted: true,
      ),
      DashAlert(
        'PCP',
        Icons.pause_circle_outline,
        'OFs paradas',
        production.count('Stopped'),
        'production-orders',
        'Stopped',
        to('production-orders', 'Stopped'),
      ),
    ],
    if (purchasing != null) ...[
      DashAlert(
        'Suprimentos',
        Icons.local_shipping_outlined,
        'Entregas em atraso',
        overdue.length,
        'overdue',
        null,
        showList(
          'Entregas em atraso',
          overdue,
          (l) => '${l['daysLate']} d · ped. ${l['purchaseOrderNumber']} · ${l['supplierName']} · ${l['description']}',
          (l) => push(OrderScreen(session: session, id: l['purchaseOrderId'] as int)),
          all: 'overdue',
        ),
      ),
      DashAlert(
        'Suprimentos',
        Icons.history,
        'Entregas atrasadas há mais de $legacyOverdueDays dias',
        overdueLegacy.length,
        'overdue',
        null,
        showList(
          'Entregas atrasadas há mais de $legacyOverdueDays dias',
          overdueLegacy,
          (l) => '${l['daysLate']} d · ped. ${l['purchaseOrderNumber']} · ${l['supplierName']} · ${l['description']}',
          (l) => push(OrderScreen(session: session, id: l['purchaseOrderId'] as int)),
          all: 'overdue',
        ),
        muted: true,
      ),
      DashAlert(
        'Suprimentos',
        Icons.assignment_late_outlined,
        'Requisições a aprovar',
        purchasing.pendingApproval,
        'requisitions',
        'PendingApproval',
        to('requisitions', 'PendingApproval'),
      ),
    ],
    if (stock != null) ...[
      DashAlert('Estoque', Icons.verified_outlined, 'Lotes em quarentena', stock.quarantine, 'lots', 'Quarantine', to('lots', 'Quarantine')),
      DashAlert(
        'Estoque',
        Icons.trending_down,
        'Materiais abaixo do estoque mínimo',
        stock.lowStock.length,
        'low-stock',
        null,
        to('low-stock'),
      ),
      DashAlert('Estoque', Icons.content_cut, 'Aço aguardando retorno do slitter', stock.steelPending, 'steel', null, to('steel')),
    ],
    if (eng != null) ...[
      DashAlert(
        'Engenharia',
        Icons.block,
        'Produtos bloqueados',
        eng.blockedTotal,
        products.path,
        null,
        showList('Produtos bloqueados', eng.blocked, productLabel, openProduct, all: products.path, total: eng.blockedTotal),
      ),
      DashAlert(
        'Engenharia',
        Icons.warning_amber,
        'Produtos sem roteiro',
        eng.withoutRoutingTotal,
        products.path,
        null,
        showList('Produtos sem roteiro', eng.withoutRouting, productLabel, openProduct, all: products.path, total: eng.withoutRoutingTotal),
      ),
    ],
  ].where((a) => a.count > 0).toList();
}

String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Painel: module cards with badges, alerts and quick actions; each module loads its numbers independently.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session, this.onNavigate});

  final Session session;
  final Navigate? onNavigate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _maxWidth = 1280.0;
  late Future<DashboardData> _eng = fetchEngineering(widget.session.api, dashboardCounted);
  late Future<StockDashboard> _stock = fetchStock(widget.session.api);
  late Future<PurchasingDashboard> _purchasing = fetchPurchasing(widget.session.api);
  late Future<ProductionDashboard> _production = fetchProduction(widget.session.api, legacyDays: legacyOverdueDays);
  late Future<CommercialDashboard> _commercial = fetchCommercial(widget.session.api);
  late Future<List<Object?>> _all = _combine();
  late Future<BackupAlert?> _backup = fetchBackupAlert(widget.session);
  DateTime? _updated;
  final _focus = FocusNode();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _settle();
    widget.session.addListener(_armTimer);
    _armTimer();
  }

  int _armedMinutes = -1;

  /// Starts (or stops) the automatic refresh when the personal setting changes.
  void _armTimer() {
    final minutes = widget.session.dashboardRefreshMinutes;
    if (minutes == _armedMinutes) return;
    _armedMinutes = minutes;
    _timer?.cancel();
    _timer = minutes > 0 ? Timer.periodic(Duration(minutes: minutes), (_) => _refresh()) : null;
  }

  @override
  void dispose() {
    widget.session.removeListener(_armTimer);
    _timer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  Future<List<Object?>> _combine() =>
      Future.wait<Object?>([_eng, _stock, _purchasing, _production, _commercial].map((f) => f.then<Object?>((v) => v, onError: (Object e) {
        debugPrint('dashboard: section failed: $e');
        return null;
      })));

  List<DashAlert> _alerts(List<Object?> d) => buildAlerts(
    context,
    session: widget.session,
    refresh: _refresh,
    go: widget.onNavigate,
    eng: d[0] as DashboardData?,
    stock: d[1] as StockDashboard?,
    purchasing: d[2] as PurchasingDashboard?,
    production: d[3] as ProductionDashboard?,
    commercial: d[4] as CommercialDashboard?,
  );

  Future<void> _settle() async {
    final d = await _all;
    if (!mounted) return;
    widget.session.alerts.value = [for (final a in _alerts(d).where((a) => !a.muted)) AlertInfo(a.icon, a.label, a.count, a.navId, a.filter)];
    setState(() => _updated = DateTime.now());
  }

  Future<void> _refresh() {
    setState(() {
      _eng = fetchEngineering(widget.session.api, dashboardCounted);
      _stock = fetchStock(widget.session.api);
      _purchasing = fetchPurchasing(widget.session.api);
      _production = fetchProduction(widget.session.api, legacyDays: legacyOverdueDays);
      _commercial = fetchCommercial(widget.session.api);
      _backup = fetchBackupAlert(widget.session);
      _all = _combine();
    });
    return _settle();
  }

  void Function()? _go(String id, [String? filter]) => widget.onNavigate == null ? null : () => widget.onNavigate!(id, filter);

  Widget _onboarding() => FutureBuilder<List<Object?>>(
    future: _all,
    builder: (context, snap) {
      if (!snap.hasData) return const SizedBox.shrink();
      final d = snap.data!;
      final e = d[0] as DashboardData?, st = d[1] as StockDashboard?, pu = d[2] as PurchasingDashboard?, pr = d[3] as ProductionDashboard?;
      final steps = [
        ('Cadastrar produtos', 'products', e == null || (e.counts[products] ?? 0) > 0, products.path),
        ('Cadastrar locais de estoque', 'locations', st == null || st.locations > 0, 'locations'),
        (
          'Registrar a primeira requisição ou pedido de compra',
          'purchasing',
          pu == null || pu.pendingApproval + pu.approved + pu.openQuotations + pu.openOrders + pu.overdue.length > 0,
          'requisitions',
        ),
        ('Criar a primeira ordem de fabricação', 'production', pr == null || pr.openTotal > 0 || pr.shipments.isNotEmpty, 'production-orders'),
      ];
      final done = steps.where((s) => s.$3).length;
      if (done == steps.length) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          margin: EdgeInsets.zero,
          shape: dashCardShape(context),
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
    },
  );

  Widget _attention() => FutureBuilder<List<Object?>>(
    future: _all,
    builder: (context, snap) {
      final theme = Theme.of(context);
      final updated = _updated;
      final header = Row(
        children: [
          Expanded(
            child: Text('Atenção', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (updated != null) Text('Atualizado às ${hhmm(updated)}', style: theme.textTheme.bodySmall),
          IconButton(tooltip: 'Atualizar (F5)', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      );
      final Widget content;
      if (!snap.hasData) {
        content = const LinearProgressIndicator();
      } else {
        final alerts = _alerts(snap.data!);
        content = alerts.isEmpty
            ? FutureBuilder<BackupAlert?>(
                future: _backup,
                builder: (context, b) => b.data != null
                    ? const SizedBox.shrink()
                    : const DashNotice(
                        icon: Icons.check_circle_outline,
                        title: 'Nada pendente',
                        subtitle: 'Nenhuma OF atrasada, entrega em atraso, aprovação ou bloqueio.',
                      ),
              )
            : DashGrid(
                items: [for (final a in alerts) GridItem(DashTile(icon: a.icon, label: a.label, value: '${a.count}', alert: !a.muted, onTap: a.onTap))],
              );
      }
      final backup = FutureBuilder<BackupAlert?>(
        future: _backup,
        builder: (context, b) => b.data == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BackupAlertCard(alert: b.data!, session: widget.session),
              ),
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, backup, content, const SizedBox(height: 16)]);
    },
  );

  List<String>? _summary(String module, List<Object?>? d) {
    if (d == null) return null;
    final e = d[0] as DashboardData?,
        st = d[1] as StockDashboard?,
        pu = d[2] as PurchasingDashboard?,
        pr = d[3] as ProductionDashboard?,
        co = d[4] as CommercialDashboard?;
    switch (module) {
      case 'Comercial':
        return co == null
            ? null
            : ['${co.k('openQuotes').toInt()} propostas abertas', '${co.k('openOrders').toInt()} pedidos abertos · ${fmtMoney(co.k('openOrdersValue'))}'];
      case 'Engenharia':
        return e == null ? null : ['${e.total} produtos', '${e.counts[materials] ?? 0} materiais · ${e.counts[machines] ?? 0} máquinas'];
      case 'Estoque':
        return st == null ? null : ['${st.openReservations} reservas abertas', '${st.steelLots} bobinas · ${fmt(st.steelBalanceKg)} kg de aço'];
      case 'Suprimentos':
        return pu == null ? null : ['${pu.openOrders} pedidos de compra abertos', '${pu.openQuotations} cotações abertas'];
      default:
        return pr == null
            ? null
            : [
                '${pr.count('InProduction')} em produção · ${pr.count('Released')} liberadas',
                '${pr.count('Created')} a liberar · ${pr.shipments.length} em terceiros',
              ];
    }
  }

  Widget _modules() => FutureBuilder<List<Object?>>(
    future: _all,
    builder: (context, snap) {
      final theme = Theme.of(context);
      final alerts = snap.hasData ? _alerts(snap.data!) : const <DashAlert>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Módulos', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          ),
          LayoutBuilder(
            builder: (context, c) {
              const gap = 12.0;
              final cols = math.max(1, ((c.maxWidth + gap) / (300 + gap)).floor());
              final width = (c.maxWidth - gap * (cols - 1)) / cols - 0.01;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final m in modulesFor(widget.session.role))
                    SizedBox(
                      width: width,
                      child: ModuleCard(
                        module: m,
                        lines: _summary(m.section, snap.data),
                        loading: !snap.hasData,
                        attention: alerts.where((a) => a.module == m.section && !a.muted).fold<int>(0, (n, a) => n + a.count),
                        onTap: _go(m.id),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final actions = quickActionsFor(widget.session);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f5): _refresh},
      child: Focus(
        focusNode: _focus,
        child: PullRefresh(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (actions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final buttons = [
                              for (final a in actions)
                                FilledButton.tonalIcon(onPressed: () => a.run(context).then((_) => _refresh()), icon: Icon(a.icon), label: Text(a.label)),
                            ];
                            // On a phone the buttons scroll sideways in one row so the alerts and modules stay on the first screen.
                            if (c.maxWidth < 600) {
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(children: [for (final b in buttons) Padding(padding: const EdgeInsets.only(right: 8), child: b)]),
                              );
                            }
                            return Wrap(spacing: 8, runSpacing: 8, children: buttons);
                          },
                        ),
                      ),
                    _onboarding(),
                    _attention(),
                    _modules(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Card of one module on the Painel.
class ModuleCard extends StatelessWidget {
  const ModuleCard({super.key, required this.module, required this.lines, required this.loading, required this.attention, this.onTap});

  final ModuleInfo module;
  final List<String>? lines;
  final bool loading;
  final int attention;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: onTap != null,
      label: 'Módulo ${module.section}',
      child: Card(
        key: ValueKey('module-${module.section}'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: dashCardShape(context),
        color: cs.surfaceContainerHigh,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(backgroundColor: cs.primaryContainer, foregroundColor: cs.onPrimaryContainer, child: Icon(module.icon)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(module.section, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (attention > 0)
                      Badge(label: Text('$attention'), backgroundColor: cs.error, textColor: cs.onError)
                    else if (!loading && lines != null)
                      Tooltip(message: 'Nada pendente', child: Icon(Icons.check_circle_outline, size: 20, color: cs.primary)),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 8),
                Text(module.blurb, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                if (loading)
                  const LinearProgressIndicator()
                else if (lines == null)
                  Text('Indisponível no momento', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
                else
                  for (final l in lines!) Text(l, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
