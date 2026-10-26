import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../entities.dart';
import '../session.dart';
import 'dashboard.dart';
import 'deliveries.dart';
import 'entity_list.dart';
import 'orders.dart';
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
  final Widget Function(Session s) build;
}

List<NavItem> navItems() => [
  NavItem('dashboard', Icons.dashboard_outlined, 'Painel', '', (s) => DashboardScreen(session: s)),
  NavItem('sales-pipeline', Icons.view_kanban_outlined, 'Funil de vendas', 'Comercial', (s) => SalesPipelineScreen(session: s)),
  NavItem('sales-quotes', Icons.request_quote_outlined, 'Propostas', 'Comercial', (s) => QuotesScreen(session: s)),
  NavItem('sales-orders', Icons.receipt_long_outlined, 'Pedidos de venda', 'Comercial', (s) => SalesOrdersScreen(session: s)),
  NavItem('deliveries', Icons.local_shipping_outlined, 'Entregas', 'Comercial', (s) => DeliveriesScreen(session: s)),
  for (final spec in salesMasters) NavItem(spec.path, spec.icon, spec.title, 'Comercial', (s) => EntityListScreen(session: s, spec: spec)),
  for (final spec in masterData) NavItem(spec.path, spec.icon, spec.title, 'Engenharia', (s) => EntityListScreen(session: s, spec: spec)),
  NavItem('balances', Icons.inventory_outlined, 'Saldos', 'Estoque', (s) => BalancesScreen(session: s)),
  NavItem('documents', Icons.swap_horiz, 'Movimentações', 'Estoque', (s) => DocumentsScreen(session: s)),
  NavItem('lots', Icons.verified_outlined, 'Lotes e inspeção', 'Estoque', (s) => LotsView(session: s, initialStatus: s.canStock ? 'Quarantine' : null)),
  NavItem('reservations', Icons.bookmark_border, 'Reservas', 'Estoque', (s) => ReservationsView(session: s)),
  NavItem('closing', Icons.calculate_outlined, 'Fechamento e custo médio', 'Estoque', (s) => ClosingScreen(session: s)),
  NavItem('locations', stockLocations.icon, stockLocations.title, 'Estoque', (s) => EntityListScreen(session: s, spec: stockLocations)),
  NavItem('requisitions', Icons.assignment_outlined, 'Requisições', 'Suprimentos', (s) => RequisitionsScreen(session: s)),
  NavItem('quotations', Icons.request_quote_outlined, 'Cotações', 'Suprimentos', (s) => QuotationsScreen(session: s)),
  NavItem('orders', Icons.receipt_long_outlined, 'Pedidos de compra', 'Suprimentos', (s) => OrdersScreen(session: s)),
  NavItem('receipts', Icons.move_to_inbox_outlined, 'Recebimentos', 'Suprimentos', (s) => ReceiptsView(session: s, allowNew: true)),
  NavItem('overdue', Icons.schedule, 'Entregas em atraso', 'Suprimentos', (s) => OverdueScreen(session: s)),
  NavItem('suppliers', Icons.local_shipping_outlined, 'Fornecedores', 'Suprimentos', (s) => SuppliersScreen(session: s)),
  NavItem('production-orders', Icons.assignment_outlined, 'Ordens de fabricação', 'PCP', (s) => ProductionOrdersScreen(session: s)),
  NavItem('production-reports', Icons.edit_note, 'Apontamentos', 'PCP', (s) => ReportsScreen(session: s)),
  NavItem('outside-processing', Icons.local_shipping_outlined, 'Beneficiamento externo', 'PCP', (s) => OutsideProcessingScreen(session: s)),
  NavItem('planning', Icons.view_timeline_outlined, 'Programação e carga', 'PCP', (s) => PlanningScreen(session: s)),
  for (final spec in productionMasters) NavItem(spec.path, spec.icon, spec.title, 'PCP', (s) => EntityListScreen(session: s, spec: spec)),
  NavItem('settings', Icons.tune, 'Parâmetros', 'Sistema', (s) => SettingsScreen(session: s)),
];

String startPage(Session s, {bool? desktop}) {
  final isDesktop = desktop ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);
  if (!isDesktop) return 'dashboard';
  return switch (s.role) {
    'Stock' => 'balances',
    'Purchasing' => 'orders',
    'Production' => 'production-orders',
    'Sales' || 'SalesManager' => 'sales-pipeline',
    _ => products.path,
  };
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.session});

  final Session session;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _items = navItems();
  late String _current = startPage(widget.session);

  NavItem get _item => _items.firstWhere((i) => i.id == _current);

  Widget _menu({bool closeDrawer = false}) {
    final children = <Widget>[];
    String? section;
    for (final d in _items) {
      if (d.section != section) {
        section = d.section;
        if (section.isNotEmpty) {
          children.add(const Divider());
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(section, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ),
          );
        }
      }
      children.add(
        ListTile(
          dense: true,
          leading: Icon(d.icon),
          title: Text(d.title),
          selected: d.id == _current,
          onTap: () {
            setState(() => _current = d.id);
            if (closeDrawer) Navigator.pop(context);
          },
        ),
      );
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: children);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final s = widget.session;
    final page = KeyedSubtree(key: ValueKey(_current), child: _item.build(s));
    return Scaffold(
      appBar: AppBar(
        title: Text(_item.title),
        actions: [
          Center(child: Text('${s.username} · ${s.role}')),
          IconButton(tooltip: 'Sair', onPressed: s.logout, icon: const Icon(Icons.logout)),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: _menu(closeDrawer: true))),
      body: wide
          ? Row(
              children: [
                SizedBox(width: 248, child: _menu()),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ],
            )
          : page,
    );
  }
}
