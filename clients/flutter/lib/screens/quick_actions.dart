import 'package:flutter/material.dart';

import '../entities.dart';
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/actions.dart';
import 'orders.dart';
import 'product_detail.dart';
import 'production_floor.dart';
import 'production_orders.dart';
import 'requisitions.dart';
import 'sales_orders.dart';
import 'sales_quotes.dart';
import 'stock_documents.dart';
import 'stock_lots.dart';
import 'viability.dart';

/// A shortcut shown on the Painel and in the command palette.
class QuickAction {
  const QuickAction(this.icon, this.label, this.run, {this.id = ''});

  final IconData icon;
  final String label;
  final Future<void> Function(BuildContext context) run;

  /// Stable key saved in the user's choice (see [quickActionCatalog]).
  final String id;
}

Future<void> newProduct(BuildContext context, Session session) async {
  final api = session.api;
  final r = await submitForm(context, api: api, title: 'Novo: ${products.singular}', fields: products.fields, submit: (b) => api.post(products.path, b));
  if (r == null || r['id'] is! int || !context.mounted) return;
  await openProduct(context, session, r['id'] as int);
}

/// The shortcuts shown on the Painel until the user picks their own; the order is the order on screen.
const defaultQuickActionIds = ['new-quote', 'new-product', 'new-production-order', 'new-requisition', 'new-purchase-order'];

/// Every shortcut the user may put on the Painel; the ones their role cannot use are left out.
/// [go] opens a screen of the shell; without it the shortcuts that only visit a screen are left out.
List<QuickAction> quickActionCatalog(Session s, {void Function(String id)? go}) => [
  if (s.canSell) QuickAction(Icons.request_quote_outlined, 'Novo orçamento', (c) => newQuote(c, s), id: 'new-quote'),
  if (s.canSell) QuickAction(Icons.receipt_long_outlined, 'Novo pedido de venda', (c) => newSalesOrder(c, s), id: 'new-sales-order'),
  if (s.canSell) QuickAction(Icons.fact_check_outlined, 'Nova análise de viabilidade', (c) async => await newFeasibility(c, s), id: 'new-feasibility'),
  if (s.canWrite) QuickAction(Icons.add_box_outlined, 'Novo produto', (c) => newProduct(c, s), id: 'new-product'),
  if (s.canWrite) QuickAction(Icons.category_outlined, 'Nova matéria-prima', (c) => newMaterial(c, s), id: 'new-material'),
  if (s.canProduce) QuickAction(Icons.add_task, 'Nova ordem de fabricação', (c) => newProductionOrder(c, s), id: 'new-production-order'),
  if (s.canProduce) QuickAction(Icons.timer_outlined, 'Novo apontamento', (c) => newReport(c, s), id: 'new-report'),
  if (s.canRequest) QuickAction(Icons.post_add, 'Nova requisição', (c) => newRequisition(c, s), id: 'new-requisition'),
  if (s.canBuy) QuickAction(Icons.add_shopping_cart, 'Novo pedido', (c) => newPurchaseOrder(c, s), id: 'new-purchase-order'),
  if (s.canStock) QuickAction(Icons.swap_vert, 'Novo lançamento', (c) => newStockPosting(c, s), id: 'new-stock-posting'),
  if (s.canStock) QuickAction(Icons.lock_clock_outlined, 'Nova reserva', (c) => newReservation(c, s), id: 'new-reservation'),
  if (go != null) QuickAction(Icons.trending_down, 'Estoque mínimo', (c) async => go('low-stock'), id: 'low-stock'),
];

/// The shortcuts on the Painel: the user's pick (at most [Session.maxQuickActions]) or the default set. Picks the role cannot use are skipped.
List<QuickAction> quickActionsFor(Session s, {void Function(String id)? go}) {
  final byId = {for (final a in quickActionCatalog(s, go: go)) a.id: a};
  List<QuickAction> resolve(List<String> ids) => [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ].take(Session.maxQuickActions).toList();
  final picked = s.quickActionIds == null ? <QuickAction>[] : resolve(s.quickActionIds!);
  return picked.isNotEmpty ? picked : resolve(defaultQuickActionIds);
}

Future<void> newMaterial(BuildContext context, Session session) async {
  final api = session.api;
  await submitForm(context, api: api, title: 'Novo: ${materials.singular}', fields: materials.fields, submit: (b) => api.post(materials.path, b));
}

Future<void> newStockPosting(BuildContext context, Session session) async {
  final doc = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => StockPostScreen(session: session)));
  if (doc == null || doc['id'] is! int || !context.mounted) return;
  await openStockDocument(context, session, doc['id'] as int);
}

Future<void> newReservation(BuildContext context, Session session) async {
  final api = session.api;
  await submitForm(context, api: api, title: 'Nova reserva', fields: reservationFields, submit: (b) => api.post('/api/stock/reservations', b));
}

/// Shortcuts of one module (the section names of [modules]), shown on its landing page: only things that belong to that sector.
/// [go] opens a screen of the shell for the shortcuts that are a visit rather than a new record.
List<QuickAction> moduleQuickActions(Session s, String section, {void Function(String id)? go}) => switch (section) {
  'Comercial' => [
    if (s.canSell) QuickAction(Icons.request_quote_outlined, 'Novo orçamento', (c) => newQuote(c, s)),
    if (s.canSell) QuickAction(Icons.receipt_long_outlined, 'Novo pedido de venda', (c) => newSalesOrder(c, s)),
    if (s.canSell) QuickAction(Icons.fact_check_outlined, 'Nova análise de viabilidade', (c) async => await newFeasibility(c, s)),
  ],
  'Engenharia' => [
    if (s.canWrite) QuickAction(Icons.add_box_outlined, 'Novo produto', (c) => newProduct(c, s)),
    if (s.canWrite) QuickAction(Icons.category_outlined, 'Nova matéria-prima', (c) => newMaterial(c, s)),
  ],
  'PCP' => [
    if (s.canProduce) QuickAction(Icons.add_task, 'Nova ordem de fabricação', (c) => newProductionOrder(c, s)),
    if (s.canProduce) QuickAction(Icons.timer_outlined, 'Novo apontamento', (c) => newReport(c, s)),
  ],
  'Suprimentos' => [
    if (s.canRequest) QuickAction(Icons.post_add, 'Nova requisição', (c) => newRequisition(c, s)),
    if (s.canBuy) QuickAction(Icons.add_shopping_cart, 'Novo pedido de compra', (c) => newPurchaseOrder(c, s)),
    if (go != null) QuickAction(Icons.trending_down, 'Estoque mínimo', (c) async => go('low-stock')),
  ],
  'Estoque' => [
    if (s.canStock) QuickAction(Icons.swap_vert, 'Novo lançamento', (c) => newStockPosting(c, s)),
    if (s.canStock) QuickAction(Icons.lock_clock_outlined, 'Nova reserva', (c) => newReservation(c, s)),
    if (go != null) QuickAction(Icons.trending_down, 'Estoque mínimo', (c) async => go('low-stock')),
  ],
  _ => const [],
};

/// Row of quick-action buttons. It wraps onto more lines instead of scrolling sideways, so no action is hidden off screen on a phone.
class QuickActionBar extends StatelessWidget {
  const QuickActionBar({super.key, required this.actions, this.onDone, this.onEdit});

  final List<QuickAction> actions;

  /// Called after an action ends, e.g. to reload the numbers on the page.
  final VoidCallback? onDone;

  /// When set, a last button lets the user choose which shortcuts are shown.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty && onEdit == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final a in actions)
            FilledButton.tonalIcon(onPressed: () => a.run(context).then((_) => onDone?.call()), icon: Icon(a.icon), label: Text(a.label)),
          if (onEdit != null) IconButton(key: const ValueKey('quick-actions-edit'), tooltip: 'Editar atalhos', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
    );
  }
}
