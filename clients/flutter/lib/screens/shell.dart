import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities.dart';
import '../session.dart';
import '../widgets/global_search.dart';
import 'dashboard.dart';
import 'deliveries.dart';
import 'entity_list.dart';
import 'orders.dart';
import 'product_detail.dart';
import 'production_floor.dart';
import 'production_orders.dart';
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
  const NavItem(this.id, this.icon, this.title, this.section, this.build);

  final String id;
  final IconData icon;
  final String title;
  final String section;
  final Widget Function(Session s, String? filter, Navigate go) build;
}

List<NavItem> navItems() => [
  NavItem('dashboard', Icons.dashboard_outlined, 'Painel', '', (s, f, go) => DashboardScreen(session: s, onNavigate: go)),
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
  NavItem('settings', Icons.tune, 'Parâmetros', 'Sistema', (s, f, go) => SettingsScreen(session: s)),
];

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
  final _search = SearchController();

  @override
  void initState() {
    super.initState();
    _restoreCollapsed();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _restoreCollapsed() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted && (p.getBool('navCollapsed') ?? false)) setState(() => _collapsed = true);
    } catch (_) {}
  }

  Future<void> _toggleCollapsed() async {
    setState(() => _collapsed = !_collapsed);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('navCollapsed', _collapsed);
    } catch (_) {}
  }

  void _openProduct(int id) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProductDetailScreen(session: widget.session, productId: id),
    ),
  );

  void _go(String id, [String? filter]) => setState(() {
    _current = id;
    _filter = filter;
  });

  NavItem get _item => _items.firstWhere((i) => i.id == _current);

  Widget _menu({bool closeDrawer = false, bool rail = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final children = <Widget>[];
    String? section;
    for (final d in _items) {
      if (d.section != section) {
        section = d.section;
        if (section.isNotEmpty) {
          children.add(const Divider());
          if (!rail) {
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(section, style: theme.textTheme.labelMedium?.copyWith(color: cs.primary)),
              ),
            );
          }
        }
      }
      final active = d.id == _current;
      void tap() {
        _go(d.id);
        if (closeDrawer) Navigator.pop(context);
      }

      children.add(
        rail
            ? Tooltip(
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
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: Icon(d.icon),
                  title: Text(d.title, style: active ? const TextStyle(fontWeight: FontWeight.w600) : null),
                  selected: active,
                  selectedTileColor: cs.secondaryContainer,
                  selectedColor: cs.onSecondaryContainer,
                  onTap: tap,
                ),
              ),
      );
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: children);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final s = widget.session;
    final page = KeyedSubtree(key: ValueKey('$_current/$_filter'), child: _item.build(s, _filter, _go));
    final targets = [for (final i in _items) SearchTarget(i.id, i.icon, i.title, i.section)];
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyK, control: true): _search.openView},
      child: Scaffold(
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
            GlobalSearch(session: s, controller: _search, targets: targets, onNavigate: _go, onOpenProduct: _openProduct, compact: !wide),
            const SizedBox(width: 8),
            UserMenu(session: s),
            const SizedBox(width: 8),
          ],
        ),
        drawer: wide ? null : Drawer(child: SafeArea(child: _menu(closeDrawer: true))),
        body: wide
            ? Row(
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
      ),
    );
  }
}
