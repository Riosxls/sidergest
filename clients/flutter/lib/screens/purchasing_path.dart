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
    VoidCallback? link(int i) => i == page ? null : links[i];
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 480) {
          return StagePath(steps: purchasingSteps, current: current, failedLabel: failedLabel, onStep: link);
        }
        // Narrow: the chevrons would have no room for words, so the stage is said in one line and the linked stages are chips below.
        final theme = Theme.of(context);
        final label = failedLabel ?? purchasingSteps[current].label;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Etapa ${current + 1} de ${purchasingSteps.length} · $label',
              key: const ValueKey('path-compact'),
              style: theme.textTheme.titleSmall?.copyWith(color: failedLabel != null ? theme.colorScheme.error : null),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final (i, s) in purchasingSteps.indexed)
                  if (link(i) != null) ActionChip(key: ValueKey('path-tap-$i'), avatar: Icon(s.icon, size: 16), label: Text(s.label), onPressed: link(i)),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// What a stage opens: the only record in [links] (maps with `id` and `number`), or a choice among several. Null when there is none.
VoidCallback? purchasingLink(BuildContext context, String title, String prefix, Iterable<Object?>? links, Future<void> Function(int id) open) {
  final list = (links ?? const <Object?>[]).cast<Map<String, dynamic>>();
  return stepLink(context, title, [for (final l in list) (label: '$prefix ${l['number']}', open: () => open(l['id'] as int))]);
}
