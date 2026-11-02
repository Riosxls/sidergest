import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart' show friendlyError;
import '../entities.dart';
import '../session.dart';
import '../widgets/alerts.dart';
import '../widgets/command_palette.dart';
import '../widgets/record_nav.dart';
import '../widgets/user_menu.dart';
import 'audit.dart';
import 'certificates.dart';
import 'customers.dart';
import 'dashboard.dart';
import 'deliveries.dart';
import 'entity_list.dart';
import 'fiscal.dart';
import 'low_stock.dart';
import 'modules.dart';
import 'orders.dart';
import 'permissions.dart';
import 'product_detail.dart';
import 'production_floor.dart';
import 'production_orders.dart';
import 'quick_actions.dart';
import 'quotations.dart';
import 'receipts.dart';
import 'reports.dart' show BillingSummaryScreen, MaterialConsumptionScreen;
import 'requisitions.dart';
import 'sales_common.dart' show openQuote, openSalesOrder;
import 'sales_orders.dart';
import 'sales_pipeline.dart';
import 'sales_quotes.dart';
import 'steel.dart';
import 'stock_balances.dart';
import 'stock_closing.dart';
import 'stock_documents.dart';
import 'stock_lots.dart';
import 'suppliers.dart';
import 'users.dart';
import 'viability.dart';

/// An entry of the sidebar navigation of the [Shell].
class NavItem {
  const NavItem(this.id, this.icon, this.title, this.section, this.build, {this.admin = false});

  final String id;
  final IconData icon;
  final String title;
  final String section;
  final Widget Function(Session s, String? filter, Navigate go) build;

  /// Listed only for sessions with the 'admin' permission.
  final bool admin;
}

const hiddenSection = '_module';

List<NavItem> navItems() {
  final base = _screens();
  final links = {
    for (final m in modules) m.section: [for (final i in base.where((i) => i.section == m.section)) ModuleLink(i.id, i.icon, i.title)],
  };
  return [
    ...base,
    for (final m in modules)
      NavItem(m.id, m.icon, m.section, hiddenSection, (s, f, go) => ModuleScreen(session: s, module: m, links: links[m.section]!, onNavigate: go)),
  ];
}

List<NavItem> _screens() => [
  NavItem('dashboard', Icons.dashboard_outlined, 'Painel', '', (s, f, go) => DashboardScreen(session: s, onNavigate: go)),
  NavItem('customers', Icons.people_outline, 'Clientes', 'Comercial', (s, f, go) => CustomersScreen(session: s)),
  NavItem('sales-pipeline', Icons.view_kanban_outlined, 'Funil de vendas', 'Comercial', (s, f, go) => SalesPipelineScreen(session: s)),
  NavItem('sales-quotes', Icons.request_quote_outlined, 'Orçamentos', 'Comercial', (s, f, go) => QuotesScreen(session: s)),
  NavItem('viability', Icons.fact_check_outlined, 'Análises de viabilidade', 'Comercial', (s, f, go) => ViabilityScreen(session: s, initialStatus: f)),
  NavItem('sales-orders', Icons.receipt_long_outlined, 'Pedidos de venda', 'Comercial', (s, f, go) => SalesOrdersScreen(session: s)),
  NavItem('deliveries', Icons.local_shipping_outlined, 'Entregas', 'Comercial', (s, f, go) => DeliveriesScreen(session: s)),
  NavItem('certificates', Icons.verified_outlined, 'Certificados de qualidade', 'Comercial', (s, f, go) => CertificatesScreen(session: s)),
  NavItem('fiscal-documents', Icons.description_outlined, 'Notas fiscais', 'Comercial', (s, f, go) => FiscalDocumentsScreen(session: s)),
  NavItem('report-material-consumption', Icons.scale_outlined, 'Consumo de material vendido', 'Comercial', (s, f, go) => MaterialConsumptionScreen(session: s)),
  NavItem('report-billing', Icons.bar_chart_outlined, 'Faturamento consolidado', 'Comercial', (s, f, go) => BillingSummaryScreen(session: s)),
  for (final spec in salesMasters) NavItem(spec.path, spec.icon, spec.title, 'Comercial', (s, f, go) => EntityListScreen(session: s, spec: spec)),
  for (final spec in masterData) NavItem(spec.path, spec.icon, spec.title, 'Engenharia', (s, f, go) => EntityListScreen(session: s, spec: spec)),
  NavItem('balances', Icons.inventory_outlined, 'Saldos', 'Estoque', (s, f, go) => BalancesScreen(session: s)),
  NavItem('documents', Icons.swap_horiz, 'Movimentações', 'Estoque', (s, f, go) => DocumentsScreen(session: s)),
  NavItem(
    'lots',
    Icons.verified_outlined,
    'Lotes e inspeção',
    'Estoque',
    (s, f, go) => LotsView(session: s, initialStatus: f ?? (s.canStock ? 'Quarantine' : null)),
  ),
  NavItem('reservations', Icons.bookmark_border, 'Reservas', 'Estoque', (s, f, go) => ReservationsView(session: s)),
  NavItem('low-stock', Icons.trending_down, 'Estoque mínimo', 'Estoque', (s, f, go) => LowStockScreen(session: s)),
  NavItem('steel', Icons.layers_outlined, 'Controle de aço', 'Estoque', (s, f, go) => SteelScreen(session: s)),
  NavItem('closing', Icons.calculate_outlined, 'Fechamento e custo médio', 'Estoque', (s, f, go) => ClosingScreen(session: s)),
  NavItem('locations', stockLocations.icon, stockLocations.title, 'Estoque', (s, f, go) => EntityListScreen(session: s, spec: stockLocations)),
  NavItem('requisitions', Icons.assignment_outlined, 'Requisições', 'Suprimentos', (s, f, go) => RequisitionsScreen(session: s, initialStatus: f)),
  NavItem('quotations', Icons.request_quote_outlined, 'Cotações', 'Suprimentos', (s, f, go) => QuotationsScreen(session: s)),
  NavItem('orders', Icons.receipt_long_outlined, 'Pedidos de compra', 'Suprimentos', (s, f, go) => OrdersScreen(session: s)),
  NavItem('receipts', Icons.move_to_inbox_outlined, 'Recebimentos', 'Suprimentos', (s, f, go) => ReceiptsView(session: s, allowNew: true)),
  NavItem('overdue', Icons.schedule, 'Entregas em atraso', 'Suprimentos', (s, f, go) => OverdueScreen(session: s)),
  NavItem('suppliers', Icons.business_outlined, 'Fornecedores', 'Suprimentos', (s, f, go) => SuppliersScreen(session: s)),
  NavItem('production-orders', Icons.assignment_outlined, 'Ordens de fabricação', 'PCP', (s, f, go) => ProductionOrdersScreen(session: s, initialStatus: f)),
  NavItem('production-reports', Icons.edit_note, 'Apontamentos', 'PCP', (s, f, go) => ReportsScreen(session: s)),
  NavItem('outside-processing', Icons.outbox_outlined, 'Beneficiamento externo', 'PCP', (s, f, go) => OutsideProcessingScreen(session: s)),
  NavItem('planning', Icons.view_timeline_outlined, 'Programação e carga', 'PCP', (s, f, go) => PlanningScreen(session: s)),
  for (final spec in productionMasters) NavItem(spec.path, spec.icon, spec.title, 'PCP', (s, f, go) => EntityListScreen(session: s, spec: spec)),
  NavItem('settings', Icons.tune, 'Parâmetros', 'Sistema', (s, f, go) => SettingsScreen(session: s)),
  NavItem('fiscal-settings', Icons.receipt_outlined, 'Parâmetros fiscais', 'Sistema', (s, f, go) => FiscalSettingsScreen(session: s)),
  NavItem('users', Icons.group_outlined, 'Usuários', 'Sistema', (s, f, go) => UsersScreen(session: s), admin: true),
  NavItem('permissions', Icons.lock_outline, 'Permissões', 'Sistema', (s, f, go) => PermissionsScreen(session: s), admin: true),
  NavItem('audit', Icons.history, 'Auditoria', 'Sistema', (s, f, go) => AuditScreen(session: s), admin: true),
];

/// Screens a user may pick as the one that opens after sign-in, with the label shown in the setting.
List<({String id, String label})> homeScreenChoices(Session s) => [
  for (final i in navItems())
    if (!i.admin || s.isAdmin) (id: i.id, label: i.section.isEmpty ? i.title : (i.section == hiddenSection ? 'Visão geral de ${i.title}' : '${i.section}: ${i.title}')),
];

/// Main frame after sign-in: sidebar, module routing and the avatar menu.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.session});

  final Session session;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late final _items = [
    for (final i in navItems())
      if (!i.admin || widget.session.isAdmin) i,
  ];
  String _current = 'dashboard';
  String? _filter;
  bool _collapsed = false;

  /// Screens left behind by [_go], newest last, so Esc and Back return to the previous screen and not always to the Painel.
  final _history = <({String id, String? filter})>[];

  /// Screens kept alive (filters, sort and scroll survive a visit elsewhere), keyed by [_key]. Oldest first.
  final _mounted = <String, ({String id, String? filter})>{};
  final _left = <String, DateTime>{};
  static const _keepFor = Duration(minutes: 3);
  static const _keepMax = 8;

  /// Wide layout: record pages open inside the content area so the sidebar and the app bar stay.
  final _innerKey = GlobalKey<NavigatorState>();
  final _innerTrail = RecordTrail();
  final _hero = MaterialApp.createMaterialHeroController();
  final _rev = ValueNotifier<int>(0);
  int _inner = 0;

  static String _key(String id, String? filter) => '$id/${filter ?? ''}';

  NavigatorState? get _innerNav => _innerKey.currentState;

  /// Context whose Navigator receives pushed record pages: the inner one when it exists.
  BuildContext get _navContext => _innerNav?.overlay?.context ?? context;

  bool get _canBack => _inner > 0 || _history.isNotEmpty || _current != 'dashboard';

  @override
  void initState() {
    super.initState();
    if (_items.any((i) => i.id == widget.session.homeScreen)) _current = widget.session.homeScreen;
    _mount(_current, null);
    _restorePrefs();
    HardwareKeyboard.instance.addHandler(_onKey);
    _innerTrail.pages.addListener(_onInnerPages);
    widget.session.addListener(_refreshPages);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _innerTrail.pages.removeListener(_onInnerPages);
    widget.session.removeListener(_refreshPages);
    _rev.dispose();
    super.dispose();
  }

  void _onInnerPages() {
    final n = (_innerTrail.pages.value - 1).clamp(0, 99);
    if (mounted && n != _inner) setState(() => _inner = n);
  }

  void _refreshPages() {
    if (mounted) _rev.value++;
  }

  /// Marks a screen as alive. One left for a while, and the Painel, start over so they show fresh data.
  void _mount(String id, String? filter) {
    final k = _key(id, filter);
    final seen = _left[k];
    if (id == 'dashboard' || (seen != null && DateTime.now().difference(seen) > _keepFor)) _mounted.remove(k);
    _mounted.removeWhere((key, t) => key != k && t.id == id);
    _mounted[k] = (id: id, filter: filter);
    while (_mounted.length > _keepMax) {
      _mounted.remove(_mounted.keys.firstWhere((key) => key != k));
    }
  }

  bool _paletteOpen = false;

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) return _onEsc();
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.keyK || !HardwareKeyboard.instance.isControlPressed) return false;
    if (_paletteOpen || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    _openPalette();
    return true;
  }

  /// Esc: leave a text field first, then go back one step (open record, previous screen, Painel).
  bool _onEsc() {
    final k = HardwareKeyboard.instance;
    if (k.isControlPressed || k.isAltPressed || k.isShiftPressed || k.isMetaPressed) return false;
    if (_paletteOpen || !mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      focus!.unfocus();
      return true;
    }
    return _back();
  }

  Future<void> _restorePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _collapsed = p.getBool('navCollapsed') ?? false;
      });
    } catch (e) {
      debugPrint('shell: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
  }

  Future<void> _toggleCollapsed() async {
    setState(() => _collapsed = !_collapsed);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('navCollapsed', _collapsed);
    } catch (e) {
      debugPrint('shell: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
  }

  /// Goes to a screen from the sidebar, the Painel, the bell or the palette: closes open record pages and remembers where it came from.
  void _go(String id, [String? filter]) {
    _innerNav?.popUntil((r) => r.isFirst);
    if (id == _current && filter == _filter) return;
    if (id == 'dashboard') {
      _history.clear();
    } else {
      _history.add((id: _current, filter: _filter));
      if (_history.length > 30) _history.removeAt(0);
    }
    _show(id, filter);
  }

  /// One step back: the open record page, else the previous screen, else the Painel. False when there is nowhere to go.
  bool _back() {
    final inner = _innerNav;
    if (inner != null && inner.canPop()) {
      inner.maybePop();
      return true;
    }
    if (_history.isNotEmpty) {
      final t = _history.removeLast();
      _show(t.id, t.filter);
      return true;
    }
    if (_current != 'dashboard') {
      _show('dashboard', null);
      return true;
    }
    return false;
  }

  void _show(String id, String? filter) {
    _left[_key(_current, _filter)] = DateTime.now();
    _mount(id, filter);
    setState(() {
      _current = id;
      _filter = filter;
    });
    _rev.value++;
    if (id != 'dashboard') RecentStore.add(RecentItem('screen', id, _items.firstWhere((i) => i.id == id).title));
  }

  void _openProduct(int id) => Navigator.of(_navContext).push(
    MaterialPageRoute(
      builder: (_) => ProductDetailScreen(session: widget.session, productId: id),
    ),
  );

  Future<void> _openHit(String group, int id) async {
    final s = widget.session;
    Future<void> push(Widget screen) => Navigator.of(_navContext).push(MaterialPageRoute(builder: (_) => screen));
    try {
      switch (group) {
        case 'products':
          _openProduct(id);
        case 'production-orders':
          await openProductionOrder(_navContext, s, id);
        case 'sales-orders':
          await openSalesOrder(_navContext, s, id);
        case 'quotes':
          await openQuote(_navContext, s, id);
        case 'customers':
          final customer = await s.api.get('/api/customers/$id') as Map<String, dynamic>;
          if (mounted) await push(CustomerScreen(session: s, customer: customer));
        case 'fiscal-documents':
          await push(FiscalDocumentScreen(session: s, id: id));
        case 'certificates':
          await push(CertificateScreen(session: s, id: id));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _openPalette() async {
    _paletteOpen = true;
    try {
      await _showPalette();
    } finally {
      _paletteOpen = false;
    }
  }

  Future<void> _showPalette() => showCommandPalette(
    context,
    session: widget.session,
    targets: [for (final i in _items) SearchTarget(i.id, i.icon, i.title, i.section == hiddenSection ? 'Módulos' : i.section)],
    actions: [for (final a in quickActionsFor(widget.session)) PaletteAction(a.icon, a.label, () => a.run(_navContext))],
    onNavigate: _go,
    onOpenHit: _openHit,
  );

  NavItem get _item => _items.firstWhere((i) => i.id == _current);

  Widget _railItem(NavItem d, ColorScheme cs, VoidCallback tap) {
    final active = d.id == _current;
    return Tooltip(
      message: d.title,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Material(
          color: active ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: tap,
            child: SizedBox(height: 40, child: Icon(d.icon, color: active ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
          ),
        ),
      ),
    );
  }

  Widget _tile(NavItem d, ColorScheme cs, VoidCallback tap, {String? title}) {
    final active = d.id == _current;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: title ?? d.title,
        waitDuration: const Duration(milliseconds: 600),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Icon(d.icon),
          title: Text(
            title ?? d.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: active ? const TextStyle(fontWeight: FontWeight.w600) : null,
          ),
          selected: active,
          selectedTileColor: cs.secondaryContainer,
          selectedColor: cs.onSecondaryContainer,
          onTap: tap,
        ),
      ),
    );
  }

  String? get _moduleSection =>
      _item.section == hiddenSection ? _item.id.substring('module:'.length) : (modules.any((m) => m.section == _item.section) ? _item.section : null);

  /// Comercial has too many screens for one flat list; the rest of the modules are short enough to stay ungrouped.
  static const _comercialGroups = {
    'Vendas': ['customers', 'sales-pipeline', 'sales-quotes', 'viability', 'sales-orders', 'deliveries'],
    'Fiscal e qualidade': ['certificates', 'fiscal-documents'],
    'Relatórios': ['report-material-consumption', 'report-billing'],
  };

  String? _group(NavItem i) {
    if (i.section != 'Comercial') return null;
    for (final e in _comercialGroups.entries) {
      if (e.value.contains(i.id)) return e.key;
    }
    return 'Preços e regras';
  }

  Widget _groupLabel(String text, ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
    child: Text(text, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
  );

  Widget _menu({bool closeDrawer = false, bool rail = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final children = <Widget>[];

    Widget one(NavItem d, {String? title}) {
      void tap() {
        _go(d.id);
        if (closeDrawer) Navigator.pop(context);
      }

      return rail ? _railItem(d, cs, tap) : _tile(d, cs, tap, title: title);
    }

    final dashboard = _items.firstWhere((i) => i.id == 'dashboard');
    children.add(one(dashboard));
    final section = _moduleSection;
    if (section != null) {
      final module = moduleBySection(section);
      final home = _items.firstWhere((i) => i.id == module.id);
      if (rail) {
        children.add(const Divider());
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(module.section, style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          ),
        );
      }
      children.add(one(home, title: 'Visão geral'));
      String? lastGroup;
      for (final i in _items.where((i) => i.section == section)) {
        final g = _group(i);
        if (g != null && g != lastGroup) children.add(rail ? const Divider(indent: 16, endIndent: 16) : _groupLabel(g, theme));
        lastGroup = g;
        children.add(one(i));
      }
    }
    final system = _items.where((i) => i.section == 'Sistema');
    if (system.isNotEmpty) {
      children.add(const Divider());
      if (!rail) children.add(_groupLabel('Administração', theme));
      children.addAll(system.map(one));
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: children);
  }

  Widget _pages() {
    final s = widget.session;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final e in _mounted.entries)
          _PageSlot(
            key: ValueKey(e.key),
            active: e.key == _key(_current, _filter),
            child: _items.firstWhere((i) => i.id == e.value.id).build(s, e.value.filter, _go),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final s = widget.session;
    // Wide: record pages open inside the content area, under the sidebar. Narrow: they cover the whole screen.
    final page = wide
        ? HeroControllerScope(
            controller: _hero,
            child: Navigator(
              key: _innerKey,
              observers: [_innerTrail],
              onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => ListenableBuilder(listenable: _rev, builder: (_, _) => _pages())),
            ),
          )
        : _pages();
    // Back (Android, browser) steps back through open records and visited screens before leaving the app.
    return PopScope(
      canPop: !_canBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: wide
              ? IconButton(
                  tooltip: _collapsed ? 'Expandir menu' : 'Recolher menu',
                  onPressed: _toggleCollapsed,
                  icon: Icon(_collapsed ? Icons.menu : Icons.menu_open),
                )
              : null,
          title: Row(
            children: [
              if (_canBack) IconButton(tooltip: _inner > 0 || _history.isNotEmpty ? 'Voltar' : 'Voltar ao Painel', onPressed: _back, icon: const Icon(Icons.arrow_back)),
              Flexible(
                child: Text(
                  _moduleSection == null || _item.section == hiddenSection ? _item.title : '${_item.section} › ${_item.title}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            SearchLauncher(onOpen: _openPalette, compact: !wide),
            const SizedBox(width: 4),
            AlertBell(center: s.alerts, onNavigate: _go),
            const SizedBox(width: 12),
            UserMenu(session: s),
            const SizedBox(width: 8),
          ],
        ),
        drawer: wide ? null : Drawer(child: SafeArea(child: _menu(closeDrawer: true))),
        body: wide
            ? Row(
                children: [
                  SizedBox(
                    width: _collapsed ? 72 : 280,
                    child: _menu(rail: _collapsed),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: page),
                ],
              )
            : page,
      ),
    );
  }
}

/// Keeps a visited screen alive while another one shows: hidden, with no tickers, heroes or focus, and a short fade when it returns.
class _PageSlot extends StatefulWidget {
  const _PageSlot({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_PageSlot> createState() => _PageSlotState();
}

class _PageSlotState extends State<_PageSlot> with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 160), value: 1);
  bool _first = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_first) {
      _first = false;
      if (widget.active && !MediaQuery.disableAnimationsOf(context)) _fade.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(_PageSlot old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !MediaQuery.disableAnimationsOf(context)) _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: !widget.active,
    child: TickerMode(
      enabled: widget.active,
      child: HeroMode(
        enabled: widget.active,
        child: ExcludeFocus(
          excluding: !widget.active,
          child: FadeTransition(opacity: _fade, child: widget.child),
        ),
      ),
    ),
  );
}
