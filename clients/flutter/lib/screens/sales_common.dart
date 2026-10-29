import 'package:flutter/material.dart';

import '../labels.dart';
import '../session.dart';
import '../widgets/pipeline.dart';
import 'deliveries.dart';
import 'sales_orders.dart';
import 'sales_quotes.dart';

const flowSteps = [
  PathStep('Orçamento', icon: Icons.edit_note),
  PathStep('Enviada ao cliente', icon: Icons.send_outlined),
  PathStep('Aprovada', icon: Icons.thumb_up_alt_outlined),
  PathStep('Pedido de compra', icon: Icons.assignment_turned_in_outlined),
  PathStep('Pedido de venda', icon: Icons.receipt_long_outlined),
  PathStep('Ordem de Produção', icon: Icons.precision_manufacturing_outlined),
  PathStep('Certificado', icon: Icons.verified_outlined),
  PathStep('Entrega', icon: Icons.local_shipping_outlined),
];

Tone quoteTone(Object? s) => switch (s) {
  'Draft' => Tone.neutral,
  'PendingApproval' => Tone.warning,
  'Approved' || 'Sent' || 'PurchaseOrder' => Tone.info,
  'Accepted' || 'Converted' => Tone.success,
  _ => Tone.danger,
};

Tone orderTone(Object? s) => switch (s) {
  'Created' => Tone.info,
  'Released' || 'PartiallyShipped' => Tone.progress,
  'Shipped' || 'Delivered' => Tone.success,
  _ => Tone.danger,
};

Tone deliveryTone(Object? s) => switch (s) {
  'Planned' => Tone.info,
  'Shipped' => Tone.progress,
  'Delivered' => Tone.success,
  _ => Tone.danger,
};

Tone productionTone(Object? s) => switch (s) {
  'Created' => Tone.neutral,
  'Released' || 'InProduction' => Tone.progress,
  'Stopped' || 'Cancelled' => Tone.danger,
  _ => Tone.success,
};

(int, String?) quotePath(Object? s) => switch (s) {
  'Draft' || 'PendingApproval' || 'Approved' => (0, null),
  'Sent' => (1, null),
  'Accepted' => (2, null),
  'PurchaseOrder' => (3, null),
  'Converted' => (4, null),
  'Rejected' => (2, 'Recusada'),
  'Expired' => (1, 'Expirada'),
  _ => (0, 'Cancelada'),
};

(int, String?) orderPath(Object? s, {bool ready = false, bool certified = false}) => switch (s) {
  'Created' => (4, null),
  'Released' || 'PartiallyShipped' => (ready ? (certified ? 7 : 6) : 5, null),
  'Shipped' => (7, null),
  'Delivered' => (8, null),
  _ => (4, 'Cancelado'),
};

(int, String?) deliveryPath(Object? s) => switch (s) {
  'Planned' || 'Shipped' => (7, null),
  'Delivered' => (8, null),
  _ => (7, 'Cancelada'),
};

String statusLabel(Object? s) => quoteStatuses[s] ?? salesOrderStatuses[s] ?? deliveryStatuses[s] ?? '${s ?? ''}';

List<TimelineEntry> timeline(List<dynamic> history) => [
  for (final h in history.cast<Map<String, dynamic>>())
    TimelineEntry(
      title: salesActions[h['action']] ?? '${h['action']}',
      subtitle: [
        if (h['fromStatus'] != null && h['toStatus'] != null && h['fromStatus'] != h['toStatus'])
          '${statusLabel(h['fromStatus'])} → ${statusLabel(h['toStatus'])}',
        if (h['note'] != null) '${h['note']}',
      ].join(' · '),
      user: h['user'] as String?,
      at: h['at'],
      tone: switch (h['action']) {
        'accepted' || 'converted' || 'approved' || 'delivered' => Tone.success,
        'declined' || 'cancelled' || 'expired' || 'approval-rejected' => Tone.danger,
        'submitted' || 'credit-override' => Tone.warning,
        'released' || 'shipped' => Tone.progress,
        _ => Tone.info,
      },
      icon: switch (h['action']) {
        'created' => Icons.add,
        'sent' => Icons.send,
        'accepted' || 'approved' => Icons.thumb_up_alt,
        'po-received' => Icons.assignment_turned_in,
        'declined' || 'approval-rejected' => Icons.thumb_down_alt,
        'cancelled' || 'expired' => Icons.close,
        'converted' => Icons.receipt_long,
        'released' => Icons.precision_manufacturing,
        'shipped' || 'delivery-planned' => Icons.local_shipping,
        'delivered' => Icons.check,
        'revised' || 'edited' => Icons.edit,
        _ => Icons.circle,
      },
    ),
];

Future<void> openQuote(BuildContext context, Session session, int id) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => QuoteScreen(session: session, id: id),
  ),
);

Future<void> openSalesOrder(BuildContext context, Session session, int id) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => SalesOrderScreen(session: session, id: id),
  ),
);

Future<void> openDelivery(BuildContext context, Session session, int id) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => DeliveryScreen(session: session, id: id),
  ),
);

class SideBySide extends StatelessWidget {
  const SideBySide({super.key, required this.main, required this.side});

  final List<Widget> main;
  final List<Widget> side;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 1100) {
      return ListView(padding: const EdgeInsets.all(16), children: [...main, const SizedBox(height: 12), ...side]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 8, 16), children: main),
        ),
        SizedBox(
          width: 300,
          child: ListView(padding: const EdgeInsets.fromLTRB(8, 16, 16, 16), children: side),
        ),
      ],
    );
  }
}

const gap = SizedBox(height: 12);
