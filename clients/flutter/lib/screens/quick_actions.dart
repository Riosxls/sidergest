import 'package:flutter/material.dart';

import '../entities.dart';
import '../session.dart';
import '../widgets/actions.dart';
import 'orders.dart';
import 'product_detail.dart';
import 'production_orders.dart';
import 'requisitions.dart';

class QuickAction {
  const QuickAction(this.icon, this.label, this.run);

  final IconData icon;
  final String label;
  final Future<void> Function(BuildContext context) run;
}

Future<void> newProduct(BuildContext context, Session session) async {
  final api = session.api;
  final r = await submitForm(context, api: api, title: 'Novo: ${products.singular}', fields: products.fields, submit: (b) => api.post(products.path, b));
  if (r == null || r['id'] is! int || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProductDetailScreen(session: session, productId: r['id'] as int),
    ),
  );
}

List<QuickAction> quickActionsFor(Session s) => [
  if (s.canWrite) QuickAction(Icons.add_box_outlined, 'Novo produto', (c) => newProduct(c, s)),
  if (s.canProduce) QuickAction(Icons.add_task, 'Nova OF', (c) => newProductionOrder(c, s)),
  if (s.canRequest) QuickAction(Icons.post_add, 'Nova requisição', (c) => newRequisition(c, s)),
  if (s.canBuy) QuickAction(Icons.add_shopping_cart, 'Novo pedido', (c) => newPurchaseOrder(c, s)),
];
