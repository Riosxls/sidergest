import 'dart:async';

import 'package:flutter/material.dart';

import '../entities.dart' show fmt, fmtNum;
import '../labels.dart';
import '../session.dart';
import '../widgets/pipeline.dart';
import '../widgets/record_nav.dart';
import 'deliveries.dart';
import 'sales_orders.dart';
import 'sales_quotes.dart';

const flowSteps = [
  PathStep('Orçamento', icon: Icons.edit_note),
  PathStep('Enviada ao cliente', icon: Icons.send_outlined, short: 'Enviada'),
  PathStep('Aprovada pelo cliente', icon: Icons.thumb_up_alt_outlined, short: 'Aprovada'),
  PathStep('Pedido de compra', icon: Icons.assignment_turned_in_outlined, short: 'Ped. compra'),
  PathStep('Pedido de venda', icon: Icons.receipt_long_outlined, short: 'Ped. venda'),
  PathStep('Ordem de Fabricação', icon: Icons.precision_manufacturing_outlined, short: 'OF'),
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

(int, String?) quotePath(Object? s, {bool superseded = false}) => switch (s) {
  'Draft' || 'PendingApproval' || 'Approved' => (0, null),
  'Sent' => (1, null),
  // Approved is done; what is left is the customer's purchase order (step 3), then the sales order (step 4).
  'Accepted' => (3, null),
  'PurchaseOrder' => (4, null),
  'Converted' => (4, null),
  'Rejected' => (2, 'Perdida'),
  'Expired' => (1, 'Expirada'),
  _ => (0, superseded ? 'Substituída' : 'Cancelada'),
};

/// A quote that a newer revision replaced is history, not a failure: neutral tone and its own name.
bool isSuperseded(Map<String, dynamic> q) => q['supersededById'] != null;

/// What the status column and badge say: "Perdida · Preço", "Substituída por PROP 8A", or the plain status.
String quoteSituation(Map<String, dynamic> q, {bool short = false}) {
  final status = q['status'];
  if (isSuperseded(q)) return short ? 'Substituída' : 'Substituída pela revisão ${q['supersededBy']}';
  if (status == 'Rejected' && q['lostReason'] != null) return 'Perdida · ${lostReasons['${q['lostReason']}'] ?? q['lostReason']}';
  return quoteStatuses[status] ?? '$status';
}

Tone quoteToneOf(Map<String, dynamic> q) => isSuperseded(q) ? Tone.neutral : quoteTone(q['status']);

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

/// A status name. [kind] ('quote', 'order' or 'delivery') says whose status it is: the three records share words such as Cancelled, Shipped and
/// Delivered, and each names them in its own gender ("Cancelada", "Cancelado"). Without it the quote's wording wins, then the order's.
String statusLabel(Object? s, {String? kind}) {
  final maps = switch (kind) {
    'quote' => [quoteStatuses],
    'order' => [salesOrderStatuses],
    'delivery' => [deliveryStatuses],
    _ => [quoteStatuses, salesOrderStatuses, deliveryStatuses],
  };
  for (final m in maps) {
    final v = m[s];
    if (v != null) return v;
  }
  return '${s ?? ''}';
}

/// History actions whose title already says where the record went ("Conversão em pedido"): the "A → B" line would only repeat it.
const _titleNamesDestination = {
  'submitted',
  'approved',
  'approval-rejected',
  'sent',
  'po-received',
  'accepted',
  'declined',
  'gave-up',
  'reopened',
  'cancelled',
  'expired',
  'converted',
  'released',
  'shipped',
  'delivered',
  'balance-closed',
};

/// Quantity with thousands grouping and no trailing zeros: 12500 -> "12.500", 1500.5 -> "1.500,5".
String fmtQty(Object? v) {
  if (v is! num) return fmt(v);
  if (v == v.roundToDouble()) return fmtNum(v, 0);
  final s = fmtNum(v, 3);
  return s.replaceFirst(RegExp(r',?0+$'), '');
}

/// One line about a sales order for a page that points at it (a converted quote): its situation and what comes next.
({String title, String message, Tone tone}) orderSnapshot(Map<String, dynamic> o) {
  final ref = '${o['reference'] ?? ''}'.trim();
  final status = '${o['status']}';
  final pct = '${(((o['progress'] as num?) ?? 0) * 100).round()}%';
  final (situation, next, tone) = switch (status) {
    'Created' => ('Criado', 'Falta liberar para a produção.', Tone.info),
    'Released' || 'PartiallyShipped' when o['ready'] == true => (salesOrderStatuses[status]!, 'Pronto para expedir: programe a entrega.', Tone.success),
    'Released' || 'PartiallyShipped' => (salesOrderStatuses[status]!, 'Em produção, $pct pronto.', o['late'] == true ? Tone.danger : Tone.progress),
    'Shipped' => ('Expedido', 'Falta confirmar o recebimento pelo cliente.', Tone.progress),
    'Delivered' => ('Entregue', 'Todas as entregas foram confirmadas.', Tone.success),
    _ => ('Cancelado', '${o['statusReason'] ?? ''}', Tone.danger),
  };
  return (title: [ref, situation].where((p) => p.isNotEmpty).join(' · '), message: next, tone: tone);
}

/// History as timeline entries. Pass [kind] (see [statusLabel]) so the statuses in "A → B" use the record's own wording.
List<TimelineEntry> timeline(List<dynamic> history, {String? kind}) => [
  for (final h in history.cast<Map<String, dynamic>>())
    TimelineEntry(
      title: salesActions[h['action']] ?? '${h['action']}',
      subtitle: [
        if (h['fromStatus'] != null && h['toStatus'] != null && h['fromStatus'] != h['toStatus'] && !_titleNamesDestination.contains(h['action']))
          '${statusLabel(h['fromStatus'], kind: kind)} → ${statusLabel(h['toStatus'], kind: kind)}',
        if (h['note'] != null) '${h['note']}',
      ].join(' · '),
      user: h['user'] as String?,
      at: h['at'],
      tone: switch (h['action']) {
        'accepted' || 'converted' || 'approved' || 'delivered' => Tone.success,
        'declined' || 'gave-up' || 'cancelled' || 'expired' || 'approval-rejected' => Tone.danger,
        'balance-closed' => Tone.warning,
        'submitted' || 'credit-override' || 'approval-lapsed' => Tone.warning,
        'released' || 'shipped' => Tone.progress,
        _ => Tone.info,
      },
      icon: switch (h['action']) {
        'created' => Icons.add,
        'sent' => Icons.send,
        'accepted' || 'approved' => Icons.thumb_up_alt,
        'po-received' => Icons.assignment_turned_in,
        'po-text' || 'po-file' || 'po-file-removed' => Icons.attach_file,
        'duplicated' => Icons.copy,
        'approval-lapsed' => Icons.timer_off,
        'declined' || 'gave-up' || 'approval-rejected' => Icons.thumb_down_alt,
        'validity-extended' || 'rescheduled' => Icons.event_repeat,
        'balance-closed' => Icons.playlist_remove,
        'reopened' => Icons.undo,
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

Future<void> openQuote(BuildContext context, Session session, int id) => pushRecord<void>(context, 'quote', id, (_) => QuoteScreen(session: session, id: id));

Future<void> openSalesOrder(BuildContext context, Session session, int id) =>
    pushRecord<void>(context, 'sales-order', id, (_) => SalesOrderScreen(session: session, id: id));

Future<void> openDelivery(BuildContext context, Session session, int id) =>
    pushRecord<void>(context, 'delivery', id, (_) => DeliveryScreen(session: session, id: id));

/// Lays a main and a side column in a row on wide screens and stacks them on narrow ones.
class SideBySide extends StatelessWidget {
  const SideBySide({super.key, required this.main, required this.side});

  final List<Widget> main;
  final List<Widget> side;

  /// Content width from which the history sits beside the main column. It is the width of the page, not of the window: a record page opens
  /// beside the sidebar, so a 1100 px window leaves only about 800 px, and a main column of 500 px cannot hold an items table.
  static const sideMinWidth = 1100.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < sideMinWidth) {
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
    },
  );
}

const gap = SizedBox(height: 12);

/// Same as [openSalesOrder], in the place of the page that calls it (a quote that has just become this order).
Future<void> replaceWithSalesOrder(BuildContext context, Session session, int id) =>
    replaceRecord<void>(context, 'sales-order', id, (_) => SalesOrderScreen(session: session, id: id));

/// Same as [openQuote], in the place of the page that calls it (a quote version that a new revision has just replaced).
Future<void> replaceWithQuote(BuildContext context, Session session, int id) =>
    replaceRecord<void>(context, 'quote', id, (_) => QuoteScreen(session: session, id: id));

/// What a step of the path opens: the only record there is, or a choice among several. Null when there is nothing to open.
VoidCallback? stepLink(BuildContext context, String title, List<({String label, Future<void> Function() open})> options) {
  if (options.isEmpty) return null;
  if (options.length == 1) return () => unawaited(options.first.open());
  return () async {
    final picked = await showDialog<({String label, Future<void> Function() open})>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(title),
        children: [for (final o in options) SimpleDialogOption(onPressed: () => Navigator.pop(c, o), child: Text(o.label))],
      ),
    );
    if (picked != null) await picked.open();
  };
}
