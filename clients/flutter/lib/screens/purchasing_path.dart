import 'package:flutter/material.dart';

import '../widgets/pipeline.dart';
import 'sales_common.dart' show stepLink;

/// The four stages of a purchase, shared by the requisition, quotation, purchase order and receipt pages.
const purchasingSteps = [
  PathStep('Requisição', icon: Icons.assignment_outlined),
  PathStep('Cotação', icon: Icons.request_quote_outlined),
  PathStep('Pedido', icon: Icons.receipt_long_outlined),
  PathStep('Recebimento', icon: Icons.move_to_inbox_outlined),
];

/// Stage path of a purchase. A stage with a link (the record it stands for) is a button; the stage of the page itself never is.
class PurchasingPath extends StatelessWidget {
  const PurchasingPath({super.key, required this.current, required this.page, this.failedLabel, this.requisition, this.quotation, this.order, this.receipt});

  /// The stage the purchase has reached (highlighted).
  final int current;

  /// The stage this page is the record of (0 requisição … 3 recebimento); it has no link.
  final int page;
  final String? failedLabel;
  final VoidCallback? requisition;
  final VoidCallback? quotation;
  final VoidCallback? order;
  final VoidCallback? receipt;

  @override
  Widget build(BuildContext context) {
    final links = [requisition, quotation, order, receipt];
    return StagePath(steps: purchasingSteps, current: current, failedLabel: failedLabel, onStep: (i) => i == page ? null : links[i]);
  }
}

/// What a stage opens: the only record in [links] (maps with `id` and `number`), or a choice among several. Null when there is none.
VoidCallback? purchasingLink(BuildContext context, String title, String prefix, Iterable<Object?>? links, Future<void> Function(int id) open) {
  final list = (links ?? const <Object?>[]).cast<Map<String, dynamic>>();
  return stepLink(context, title, [for (final l in list) (label: '$prefix ${l['number']}', open: () => open(l['id'] as int))]);
}
