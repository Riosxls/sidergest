import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities.dart';
import '../session.dart';
import '../widgets/alerts.dart';
import '../widgets/command_palette.dart';
import '../widgets/user_menu.dart';
import 'access_placeholder.dart';
import 'dashboard.dart';
import 'deliveries.dart';
import 'entity_list.dart';
import 'orders.dart';
import 'product_detail.dart';
import 'production_floor.dart';
import 'production_orders.dart';
import 'quick_actions.dart';
import 'quotations.dart';
import 'receipts.dart';
import 'requisitions.dart';
import 'sales_orders.dart';
import 'sales_pipeline.dart';
import 'sales_quotes.dart';
import 'stock_balances.dart';
import 'stock_closing.dart';
import 'stock_documents.dart';
import 'stock_lots.dart';
import 'suppliers.dart';

class NavItem {
  const NavItem(this.id, this.icon, this.title, this.section, this.build, {this.hidden = false});

  final String id;
  final IconData icon;
  final String title;
  final String section;
  final Widget Function(Session s, String? filter, Navigate go) build;
  final bool hidden;
}

List<NavItem> navItems() => [
  NavItem('dashboard', Icons.dashboard_outlined, 'Painel', '', (s, f, go) => DashboardScreen(session: s, onNavigate: go)),
  for (final m in moduleInfos)
    NavItem(
      m.navId,
      m.icon,
      m.title,
      '',
      (s, f, go) => DashboardScreen(
        session: s,
        onNavigate: go,
        module: m.id,
        links: [
          for (final i in navItems())
            if (i.section == m.title) ModuleLink(i.id, i.icon, i.title),
        ],
      ),
      hidden: true,
    ),
  NavItem('sales-pipeline', Icons.view_kanban_outlined, 'Funil de vendas', 'Comercial', (s, f, go) => SalesPipelineScreen(session: s)),
  NavItem('sales-quotes', Icons.request_quote_outlined, 'Propostas', 'Comercial', (s, f, go) => QuotesScreen(session: s)),
  NavItem('sales-orders', Icons.receipt_long_outlined, 'Pedidos de venda', 'Comercial', (s, f, go) => SalesOrdersScreen(session: s)),
  NavItem('deliveries', Icons.local_shipping_outlined, 'Entregas', 'Comercial', (s, f, go) => DeliveriesScreen(session: s)),
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
  NavItem('closing', Icons.calculate_outlined, 'Fechamento e custo médio', 'Estoque', (s, f, go) => ClosingScreen(session: s)),
  NavItem('locations', stockLocations.icon, stockLocations.title, 'Estoque', (s, f, go) => EntityListScreen(session: s, spec: stockLocations)),
  NavItem('requisitions', Icons.assignment_outlined, 'Requisições', 'Suprimentos', (s, f, go) => RequisitionsScreen(session: s, initialStatus: f)),
  NavItem('quotations', Icons.request_quote_outlined, 'Cotações', 'Suprimentos', (s, f, go) => QuotationsScreen(session: s)),
  NavItem('orders', Icons.receipt_long_outlined, 'Pedidos de compra', 'Suprimentos', (s, f, go) => OrdersScreen(session: s)),
  NavItem('receipts', Icons.move_to_inbox_outlined, 'Recebimentos', 'Suprimentos', (s, f, go) => ReceiptsView(session: s, allowNew: true)),
  NavItem('overdue', Icons.schedule, 'Entregas em atraso', 'Suprimentos', (s, f, go) => OverdueScreen(session: s)),
  NavItem('suppliers', Icons.local_shipping_outlined, 'Fornecedores', 'Suprimentos', (s, f, go) => SuppliersScreen(session: s)),
  NavItem('production-orders', Icons.assignment_outlined, 'Ordens de fabricação', 'PCP', (s, f, go) => ProductionOrdersScreen(session: s, initialStatus: f)),
  NavItem('production-reports', Icons.edit_note, 'Apontamentos', 'PCP', (s, f, go) => ReportsScreen(session: s)),
  NavItem('outside-processing', Icons.local_shipping_outlined, 'Beneficiamento externo', 'PCP', (s, f, go) => OutsideProcessingScreen(session: s)),
  NavItem('planning', Icons.view_timeline_outlined, 'Programação e carga', 'PCP', (s, f, go) => PlanningScreen(session: s)),
  for (final spec in productionMasters) NavItem(spec.path, spec.icon, spec.title, 'PCP', (s, f, go) => EntityListScreen(session: s, spec: spec)),
  NavItem('report-portfolio', Icons.assessment_outlined, 'Carteira de pedidos', 'Relatórios', (s, f, go) => SalesOrdersScreen(session: s)),
  NavItem('report-abc', Icons.bar_chart, 'Curva ABC', 'Relatórios', (s, f, go) => BalancesScreen(session: s)),
  NavItem('report-balance', Icons.inventory_outlined, 'Saldo de estoque', 'Relatórios', (s, f, go) => BalancesScreen(session: s)),
  NavItem('settings', Icons.tune, 'Parâmetros', 'Sistema', (s, f, go) => SettingsScreen(session: s)),
  NavItem(
    'users',
    Icons.group_outlined,
    'Usuários',
    'Sistema',
    (s, f, go) => const AccessPlaceholderScreen(icon: Icons.group_outlined, title: 'Usuários', description: 'Gestão de usuários em breve.'),
  ),
  NavItem(
    'permissions',
    Icons.lock_outline,
    'Permissões',
    'Sistema',
    (s, f, go) => const AccessPlaceholderScreen(icon: Icons.lock_outline, title: 'Permissões', description: 'Gestão de permissões por perfil em breve.'),
  ),
];

/// Sections shown in the global sidebar; any other section belongs to a module.
const globalSections = {'', 'Relatórios', 'Sistema'};

class Shell extends StatefulWidget {
  const Shell({super.key, required this.session});

  final Session session;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _items = navItems();
  String _current = 'dashboard';
  String? _filter;
  bool _collapsed = false;
  bool _prefsLoaded = false;
  final _closedGroups = <String>{};

  @override
  void initState() {
    super.initState();
    _restorePrefs();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _paletteOpen = false;

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.keyK || !HardwareKeyboard.instance.isControlPressed) return false;
    if (_paletteOpen || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    _openPalette();
    return true;
  }

  Future<void> _restorePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _collapsed = p.getBool('navCollapsed') ?? false;
        _closedGroups.addAll(p.getStringList('navClosedGroups') ?? const []);
        _prefsLoaded = true;
      });
    } catch (_) {}
  }

  Future<void> _toggleCollapsed() async {
    setState(() => _collapsed = !_collapsed);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('navCollapsed', _collapsed);
    } catch (_) {}
  }

  Future<void> _groupToggled(String section, bool open) async {
    open ? _closedGroups.remove(section) : _closedGroups.add(section);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('navClosedGroups', _closedGroups.toList());
    } catch (_) {}
  }

  void _go(String id, [String? filter]) {
    setState(() {
      _current = id;
      _filter = filter;
    });
    if (id != 'dashboard') RecentStore.add(RecentItem('screen', id, _items.firstWhere((i) => i.id == id).title));
  }

  void _openProduct(int id) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProductDetailScreen(session: widget.session, productId: id),
    ),
  );

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
    targets: [for (final i in _items.where((i) => !i.hidden)) SearchTarget(i.id, i.icon, i.title, i.section)],
    actions: [for (final a in quickActionsFor(widget.session)) PaletteAction(a.icon, a.label, () => a.run(context))],
    onNavigate: _go,
    onOpenProduct: _openProduct,
  );

  NavItem get _item => _items.firstWhere((i) => i.id == _current);

  ModuleInfo? get _currentModule {
    for (final m in moduleInfos) {
      if (m.navId == _current || m.title == _item.section) return m;
    }
    return null;
  }

  Widget _railItem(NavItem d, ColorScheme cs, VoidCallback tap) {
    final active = d.id == _current || (d.id == 'dashboard' && _current.startsWith('module-'));
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

  Widget _tile(NavItem d, ColorScheme cs, VoidCallback tap) {
    final active = d.id == _current || (d.id == 'dashboard' && _current.startsWith('module-'));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(d.icon),
        title: Text(
          d.title,
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
    );
  }

  Widget _menu({bool closeDrawer = false, bool rail = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final children = <Widget>[];
    final sections = <String, List<NavItem>>{};
    final module = _currentModule;
    Widget one(NavItem d) {
      void tap() {
        _go(d.id);
        if (closeDrawer) Navigator.pop(context);
      }

      return rail ? _railItem(d, cs, tap) : _tile(d, cs, tap);
    }

    if (module != null) {
      // Inside a module: Painel (back) + module home + that module's screens only.
      final home = _items.firstWhere((i) => i.id == module.navId);
      children.add(one(_items.firstWhere((i) => i.id == 'dashboard')));
      children.add(one(NavItem(home.id, module.icon, module.title, '', home.build)));
      children.add(rail ? const Divider() : const Divider(height: 16));
      children.addAll(_items.where((i) => !i.hidden && i.section == module.title).map(one));
      return ListView(padding: const EdgeInsets.fromLTRB(0, 16, 0, 8), children: children);
    }
    for (final d in _items.where((i) => !i.hidden && globalSections.contains(i.section))) {
      sections.putIfAbsent(d.section, () => []).add(d);
    }
    // Favoritos sits between Painel and Relatórios; empty until the user pins screens.
    final ordered = <MapEntry<String, List<NavItem>>>[
      ...sections.entries.where((e) => e.key.isEmpty),
      const MapEntry('Favoritos', <NavItem>[]),
      ...sections.entries.where((e) => e.key.isNotEmpty),
    ];
    for (final entry in ordered) {
      final section = entry.key;
      if (entry.value.isEmpty) {
        if (rail) continue;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(section, style: theme.textTheme.labelMedium?.copyWith(color: cs.primary)),
          ),
        );
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Nenhum favorito ainda', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        );
        continue;
      }
      if (section.isEmpty) {
        children.addAll(entry.value.map(one));
      } else if (rail) {
        children.add(const Divider());
        children.addAll(entry.value.map(one));
      } else {
        children.add(
          ExpansionTile(
            key: ValueKey('$section/$_prefsLoaded'),
            initiallyExpanded: !_closedGroups.contains(section),
            onExpansionChanged: (open) => _groupToggled(section, open),
            dense: true,
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: EdgeInsets.zero,
            title: Text(
              section,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: cs.primary),
            ),
            children: entry.value.map(one).toList(),
          ),
        );
      }
    }
    return ListView(padding: const EdgeInsets.fromLTRB(0, 16, 0, 8), children: children);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final s = widget.session;
    final page = KeyedSubtree(key: ValueKey('$_current/$_filter'), child: _item.build(s, _filter, _go));
    return Scaffold(
      appBar: AppBar(
        leading: wide
            ? IconButton(
                tooltip: _collapsed ? 'Expandir menu' : 'Recolher menu',
                onPressed: _toggleCollapsed,
                icon: Icon(_collapsed ? Icons.menu : Icons.menu_open),
              )
            : null,
        title: Text(_item.title),
        actions: [
          SearchLauncher(onOpen: _openPalette, compact: !wide),
          const SizedBox(width: 4),
          AlertBell(center: s.alerts, onNavigate: _go),
          UserMenu(session: s),
          const SizedBox(width: 8),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: _menu(closeDrawer: true))),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _collapsed ? 72 : 248,
                  child: _menu(rail: _collapsed),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ],
            )
          : page,
    );
  }
}
