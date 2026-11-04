import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities.dart';
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/alerts.dart';
import '../widgets/dash.dart';
import '../widgets/responsive.dart';
import 'backup_alert.dart';
import 'dashboard_data.dart';
import 'orders.dart';
import 'product_detail.dart';
import 'production_orders.dart';
import 'quick_actions.dart';
import 'settings/settings_dialog.dart';

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
  ModuleInfo('Comercial', Icons.storefront_outlined, 'Orçamentos, pedidos, entregas e análises de viabilidade'),
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

/// Modules whose alerts the user may silence in Configurações > Notificações: notification key and the module title used by [DashAlert.module].
/// Keys are opaque to the server ([a-z0-9_-]); alerts that are not about a module (backup failure) are never silenceable.
const alertModules = [
  (key: 'comercial', title: 'Comercial'),
  (key: 'pcp', title: 'PCP'),
  (key: 'suprimentos', title: 'Suprimentos'),
  (key: 'estoque', title: 'Estoque'),
  (key: 'engenharia', title: 'Engenharia'),
];

/// Notification key of the module titled [title] (a [DashAlert.module]); null when it has none.
String? alertModuleKey(String title) {
  for (final m in alertModules) {
    if (m.title == title) return m.key;
  }
  return null;
}

/// One alert shown on the Painel and in the bell, with the screen it opens.
class DashAlert {
  const DashAlert(this.module, this.icon, this.label, this.count, this.navId, this.filter, this.onTap, {this.muted = false, this.silenced = false});

  /// A known backlog (imported legacy): drawn neutral, left out of the bell and the module badge.
  final bool muted;

  /// Left out because the user silenced its module (or the legacy backlog) in the notification preferences; the Painel only counts it.
  final bool silenced;
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
            width: dialogWidth(context, 560),
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
  void showProduct(Map<String, dynamic> p) => openProduct(context, session, p['id'] as int).then((_) => refresh());
  return [
    if (commercial != null) ...[
      DashAlert(
        'Comercial',
        Icons.event_busy_outlined,
        'Pedidos atrasados',
        commercial.k('lateOrders').toInt(),
        'sales-orders',
        null,
        to('sales-orders'),
      ),
      DashAlert('Comercial', Icons.gavel_outlined, 'Orçamentos a autorizar', commercial.k('pendingApprovals').toInt(), 'sales-quotes', null, to('sales-quotes')),
      DashAlert(
        'Comercial',
        Icons.draw_outlined,
        'Viabilidades em assinatura',
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
        showList('Produtos bloqueados', eng.blocked, productLabel, showProduct, all: products.path, total: eng.blockedTotal),
      ),
      DashAlert(
        'Engenharia',
        Icons.warning_amber,
        'Produtos sem roteiro',
        eng.withoutRoutingTotal,
        products.path,
        null,
        showList('Produtos sem roteiro', eng.withoutRouting, productLabel, showProduct, all: products.path, total: eng.withoutRoutingTotal),
      ),
    ],
  ].where((a) => a.count > 0).map((a) => _applyPrefs(a, session)).toList();
}

DashAlert _applyPrefs(DashAlert a, Session session) {
  final key = alertModuleKey(a.module);
  final silenced = (key != null && session.mutedAlerts.contains(key)) || (a.muted && session.hideLegacyAlerts);
  if (!silenced) return a;
  return DashAlert(a.module, a.icon, a.label, a.count, a.navId, a.filter, a.onTap, muted: a.muted, silenced: true);
}

/// What the bell needs from [alerts]: the ones that are not legacy backlog. Silenced modules stay in; [AlertCenter] filters and counts them.
List<AlertInfo> bellAlerts(List<DashAlert> alerts) => [
  for (final a in alerts)
    if (!a.muted) AlertInfo(a.icon, a.label, a.count, a.navId, a.filter, alertModuleKey(a.module)),
];

/// Reads the five sections and puts the alerts on the bell. The Painel does this itself; the shell calls it when another screen is the one
/// in use, so the bell and the Alertas button do not stay empty or stale. A section that fails counts as no news; if none loads the bell stays as it was.
Future<void> refreshAlertCenter(BuildContext context, Session session) async {
  final api = session.api;
  Future<T?> safe<T>(Future<T> f) => f.then<T?>(
    (v) => v,
    onError: (Object e) {
      debugPrint('dashboard: alert section failed: $e');
      return null;
    },
  );
  final d = await Future.wait<Object?>([
    safe(fetchEngineering(api, dashboardCounted)),
    safe(fetchStock(api)),
    safe(fetchPurchasing(api)),
    safe(fetchProduction(api, legacyDays: legacyOverdueDays)),
    safe(fetchCommercial(api)),
  ]);
  if (!context.mounted || !session.loggedIn || d.every((s) => s == null)) return;
  // The closures of an alert only matter on the Painel; here only its icon, label, count and target are used.
  final alerts = buildAlerts(
    context,
    session: session,
    refresh: () async {},
    eng: d[0] as DashboardData?,
    stock: d[1] as StockDashboard?,
    purchasing: d[2] as PurchasingDashboard?,
    production: d[3] as ProductionDashboard?,
    commercial: d[4] as CommercialDashboard?,
  );
  session.alerts.update(all: bellAlerts(alerts), muted: session.mutedAlerts);
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
  // The last numbers read: they stay on screen while a refresh runs (a small spinner says so) instead of blanking the page.
  List<Object?>? _last;
  bool _refreshing = false;
  final _focus = FocusNode();
  Timer? _timer;
  // Primeiros passos can be folded or dismissed; both are remembered on this device, per user (two people share a computer).
  bool _stepsCollapsed = false;
  bool _stepsDismissed = false;

  String _stepsKey(String name) => '$name:${widget.session.username ?? ''}';

  Future<void> _loadStepsState() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        // Seen once, the card starts folded on the next visits: it stays a reminder, not the first thing on the page.
        _stepsCollapsed = p.getBool(_stepsKey('onboardingCollapsed')) ?? (p.getBool(_stepsKey('onboardingSeen')) ?? false);
        _stepsDismissed = p.getBool(_stepsKey('onboardingDismissed')) ?? false;
      });
      await p.setBool(_stepsKey('onboardingSeen'), true);
    } catch (e) {
      debugPrint('dashboard: Local storage is best effort; the card stays open: $e');
    }
  }

  Future<void> _saveStepsState(String key, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_stepsKey(key), value);
    } catch (e) {
      debugPrint('dashboard: Local storage is best effort; the choice lasts until the app closes: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadStepsState());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _settle();
    widget.session.addListener(_armTimer);
    _armTimer();
  }

  bool _active = true;

  /// A page brought back from behind another one (the shell keeps visited screens alive) has lost the keyboard focus: F5 would do nothing until a click.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on = TickerMode.valuesOf(context).enabled;
    if (on && !_active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
    _active = on;
  }

  int _armedMinutes = -1;

  /// Starts (or stops) the automatic refresh when the personal setting changes.
  void _armTimer() {
    final minutes = widget.session.dashboardRefreshMinutes;
    if (minutes == _armedMinutes) return;
    _armedMinutes = minutes;
    _timer?.cancel();
    _timer = minutes > 0 ? Timer.periodic(Duration(minutes: minutes), (_) {
      // A screen kept alive behind another one does not poll.
      if (mounted && TickerMode.valuesOf(context).enabled) _refresh();
    }) : null;
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
    // Nothing loaded (server down): keep the bell as it was instead of emptying it.
    if (d.any((s) => s != null)) {
      widget.session.alerts.update(all: bellAlerts(_alerts(d)), muted: widget.session.mutedAlerts);
    }
    // "Atualizado às" only when something was read; a Painel where every section failed is not up to date.
    setState(() {
      _refreshing = false;
      if (d.any((s) => s != null)) _last = d;
      _updated = d.any((s) => s != null) ? DateTime.now() : null;
    });
  }

  Future<void> _refresh() {
    setState(() {
      _refreshing = true;
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
      final d = snap.data ?? _last;
      if (d == null) return const SizedBox.shrink();
      final e = d[0] as DashboardData?, st = d[1] as StockDashboard?, pu = d[2] as PurchasingDashboard?, pr = d[3] as ProductionDashboard?;
      // A section that did not load says nothing about its step: it is left out, not counted as done (that could hide the card for good).
      final all = [
        ('Cadastrar produtos', 'products', e == null ? null : (e.counts[products] ?? 0) > 0, products.path),
        ('Cadastrar locais de estoque', 'locations', st == null ? null : st.locations > 0, 'locations'),
        (
          'Registrar a primeira requisição ou pedido de compra',
          'purchasing',
          pu == null ? null : pu.pendingApproval + pu.approved + pu.openQuotations + pu.openOrders + pu.overdue.length > 0,
          'requisitions',
        ),
        ('Criar a primeira ordem de fabricação', 'production', pr == null ? null : pr.openTotal > 0 || pr.shipments.isNotEmpty, 'production-orders'),
      ];
      final steps = [
        for (final s in all)
          if (s.$3 != null) (s.$1, s.$2, s.$3!, s.$4),
      ];
      final done = steps.where((s) => s.$3).length;
      if (steps.isEmpty || done == steps.length || _stepsDismissed) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg),
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
                    IconButton(
                      key: const ValueKey('steps-collapse'),
                      tooltip: _stepsCollapsed ? 'Expandir' : 'Recolher',
                      icon: Icon(_stepsCollapsed ? Icons.expand_more : Icons.expand_less),
                      onPressed: () {
                        setState(() => _stepsCollapsed = !_stepsCollapsed);
                        unawaited(_saveStepsState('onboardingCollapsed', _stepsCollapsed));
                      },
                    ),
                    IconButton(
                      key: const ValueKey('steps-dismiss'),
                      tooltip: 'Dispensar',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() => _stepsDismissed = true);
                        unawaited(_saveStepsState('onboardingDismissed', true));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: done / steps.length, semanticsLabel: 'Primeiros passos: $done de ${steps.length} concluídos'),
                if (!_stepsCollapsed) const SizedBox(height: 8),
                if (!_stepsCollapsed)
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

  /// Alert tiles grouped under a sub-header per module (in the order of the user's modules); known legacy backlog is folded into one row.
  Widget _alertGroups(List<DashAlert> alerts) {
    final theme = Theme.of(context);
    final fresh = alerts.where((a) => !a.muted && !a.silenced).toList();
    final legacy = alerts.where((a) => a.muted && !a.silenced).toList();
    GridItem tile(DashAlert a) => GridItem(
      DashTile(
        icon: a.icon,
        label: a.label,
        value: '${a.count}',
        // A tile that opens nothing is information, not a call to act: it drops the alarm look.
        alert: !a.muted && a.onTap != null,
        onTap: a.onTap,
      ),
    );
    final order = [for (final m in modulesFor(widget.session.role)) m.section];
    final groups = <Widget>[];
    for (final section in order) {
      final mine = fresh.where((a) => a.module == section).toList();
      if (mine.isEmpty) continue;
      groups.add(
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.sm),
          child: Text(section, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
      groups.add(DashGrid(items: [for (final a in mine) tile(a)]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...groups,
        if (legacy.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              shape: dashCardShape(context),
              color: theme.colorScheme.surfaceContainerHigh,
              child: ExpansionTile(
                key: const ValueKey('legacy-alerts'),
                leading: const Icon(Icons.history),
                title: Text('Pendências antigas (${legacy.length})'),
                subtitle: const Text('Atrasos de mais de $legacyOverdueDays dias, do sistema antigo; não entram no sino'),
                shape: const Border(),
                collapsedShape: const Border(),
                childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                children: [DashGrid(items: [for (final a in legacy) tile(a)])],
              ),
            ),
          ),
      ],
    );
  }

  Widget _attention() => FutureBuilder<List<Object?>>(
    future: _all,
    builder: (context, snap) {
      final theme = Theme.of(context);
      final updated = _updated;
      final data = snap.data ?? _last;
      final all = data == null ? const <DashAlert>[] : _alerts(data);
      final alerts = all.where((a) => !a.silenced).toList();
      final silenced = all.length - alerts.length;
      final count = alerts.where((a) => !a.muted).length;
      final header = Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'Atenção',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                children: [
                  if (data != null && count > 0)
                    TextSpan(
                      text: '  $count ${count == 1 ? 'alerta' : 'alertas'}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
          if (updated != null) Text('Atualizado às ${hhmm(updated)}', style: theme.textTheme.bodySmall),
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Atualizando')),
            )
          else
            IconButton(tooltip: 'Atualizar (F5)', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      );
      final Widget content;
      if (data == null) {
        content = const LinearProgressIndicator();
      } else {
        final fresh = alerts.where((a) => !a.muted).toList();
        // A section that failed to load is null; "Nada pendente" would then hide a problem instead of reporting it.
        final failed = data.where((s) => s == null).length;
        final failedNotice = failed == 0
            ? null
            : DashNotice(
                icon: Icons.cloud_off_outlined,
                title: failed == data.length ? 'Não foi possível carregar o painel' : 'Parte do painel não carregou',
                subtitle: '$failed de ${data.length} seções falharam. Use Atualizar para tentar de novo.',
              );
        content = alerts.isEmpty && failedNotice != null
            ? failedNotice
            : alerts.isEmpty
            ? FutureBuilder<BackupAlert?>(
                future: _backup,
                builder: (context, b) => b.data != null
                    ? const SizedBox.shrink()
                    : const DashNotice(
                        icon: Icons.check_circle_outline,
                        title: 'Nada pendente',
                        subtitle: 'Nenhum alerta nas áreas que você acompanha agora.',
                      ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (failedNotice != null) ...[failedNotice, const SizedBox(height: AppSpacing.md)],
                  if (fresh.isEmpty)
                    const DashNotice(
                      icon: Icons.check_circle_outline,
                      title: 'Nada novo pendente',
                      subtitle: 'Só restam as pendências antigas abaixo.',
                    ),
                  _alertGroups(alerts),
                ],
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
      final silencedNote = silenced == 0
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('silenced-alerts'),
                  onPressed: () => showUserSettings(context, widget.session, section: 'notifications'),
                  icon: const Icon(Icons.notifications_off_outlined, size: 18),
                  label: Text('$silenced ${silenced == 1 ? 'alerta silenciado' : 'alertas silenciados'} · Notificações'),
                ),
              ),
            );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, backup, content, silencedNote, const SizedBox(height: 16)]);
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
            : ['${co.k('openQuotes').toInt()} orçamentos abertos', '${co.k('openOrders').toInt()} pedidos abertos · ${fmtMoney(co.k('openOrdersValue'))}'];
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
      final data = snap.data ?? _last;
      final alerts = data != null ? _alerts(data).where((a) => !a.silenced).toList() : const <DashAlert>[];
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
              // Columns follow the number of modules: no lone card on the last row when a different count would fill it.
              final count = modulesFor(widget.session.role).length;
              var cols = math.max(1, math.min(count, ((c.maxWidth + gap) / (300 + gap)).floor()));
              while (cols > 2 && count % cols == 1) {
                cols--;
              }
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
                        lines: _summary(m.section, data),
                        loading: data == null,
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
                    QuickActionBar(actions: actions, onDone: _refresh),
                    ListenableBuilder(listenable: widget.session, builder: (_, _) => _attention()),
                    ListenableBuilder(listenable: widget.session, builder: (_, _) => _modules()),
                    _onboarding(),
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
    // One announcement for the whole card; its texts would otherwise be read again after the label.
    final status = attention > 0
        ? '$attention ${attention == 1 ? 'pendência' : 'pendências'}'
        : loading
        ? 'Carregando'
        : lines == null
        ? 'Indisponível no momento'
        : 'Nada pendente';
    return Semantics(
      button: onTap != null,
      container: true,
      excludeSemantics: true,
      label: ['Módulo ${module.section}', module.blurb, status, ...?(loading ? null : lines)].join('. '),
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
                  for (final l in lines!) _MetricLine(l),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One summary line of a module card: each "N label" part shows the number in a larger weight so the figures can be scanned.
class _MetricLine extends StatelessWidget {
  const _MetricLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final big = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]);
    final spans = <InlineSpan>[];
    final parts = text.split(' · ');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) spans.add(TextSpan(text: ' · ', style: theme.textTheme.bodyMedium));
      final m = RegExp(r'^(\S*\d\S*)(\s.*)?$').firstMatch(parts[i]);
      if (m == null) {
        spans.add(TextSpan(text: parts[i], style: theme.textTheme.bodyMedium));
      } else {
        spans.add(TextSpan(text: m.group(1), style: big));
        if (m.group(2) != null) spans.add(TextSpan(text: m.group(2), style: theme.textTheme.bodyMedium));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }
}
