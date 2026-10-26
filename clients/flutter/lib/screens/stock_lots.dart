import 'package:flutter/material.dart';

import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/record_list.dart';
import 'stock_documents.dart';

class LotsView extends StatefulWidget {
  const LotsView({super.key, required this.session, this.query = const {}, this.initialStatus});

  final Session session;
  final Map<String, dynamic> query;
  final String? initialStatus;

  @override
  State<LotsView> createState() => _LotsViewState();
}

class _LotsViewState extends State<LotsView> {
  late String? _status = widget.initialStatus;

  @override
  Widget build(BuildContext context) {
    final api = widget.session.api;
    final cs = Theme.of(context).colorScheme;
    return RecordList(
      api: api,
      path: '/api/stock/lots',
      query: {...widget.query, 'status': _status},
      searchHint: 'Lote, NF ou corrida (exato)',
      filters: [ChoiceFilter(label: 'Situação', value: _status, choices: lotStatuses, onChanged: (v) => setState(() => _status = v))],
      enrich: (items) => NameCache.attachSupplier(api, items),
      columns: [
        col('Lote', 'code'),
        col('Item', 'itemCode'),
        labelCol('Situação', 'status', lotStatuses),
        col('Quantidade', 'quantity', numeric: true),
        dateCol('Recebido', 'receivedOn'),
        col('Fornecedor', 'supplierName'),
        col('NF', 'invoiceNumber'),
        col('Corrida', 'heatNumber'),
        col('Inspeção', 'inspectedBy'),
      ],
      rowColor: (_, e) => e['status'] == 'Rejected' ? cs.errorContainer : (e['status'] == 'Quarantine' ? cs.tertiaryContainer : null),
      onTap: (e) => showLotDialog(context, widget.session, e),
    );
  }
}

Future<void> showLotDialog(BuildContext context, Session session, Map<String, dynamic> lot) async {
  Future<void> inspect(BuildContext ctx, String status) async {
    String? note;
    if (status != 'Released') {
      note = await promptText(
        ctx,
        title: status == 'Rejected' ? 'Rejeitar lote ${lot['code']}' : 'Voltar lote ${lot['code']} para quarentena',
        label: 'Laudo / motivo',
        required: status == 'Rejected',
      );
      if (note == null) return;
    }
    if (!ctx.mounted) return;
    final r = await runAction(
      ctx,
      () => session.api.put('/api/stock/lots/${lot['id']}/inspection', {'status': status, 'note': note}),
      success: 'Lote ${lot['code']}: ${lotStatuses[status]}',
    );
    if (r != null && ctx.mounted) Navigator.pop(ctx);
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Lote ${lot['code']} · ${lot['itemCode']}'),
      content: SizedBox(
        width: 480,
        child: InfoGrid([
          ('Situação', lotStatuses[lot['status']] ?? fmt(lot['status'])),
          ('Quantidade', fmt(lot['quantity'])),
          ('Recebido em', fmtDay(lot['receivedOn'])),
          ('Fornecedor', fmt(lot['supplierName'])),
          ('NF', fmt(lot['invoiceNumber'])),
          ('Corrida', fmt(lot['heatNumber'])),
          ('Inspecionado por', lot['inspectedBy'] == null ? '' : '${lot['inspectedBy']} · ${fmtDate(lot['inspectedAt'])}'),
          ('Laudo', fmt(lot['inspectionNote'])),
        ]),
      ),
      actions: [
        if (session.canStock && lot['status'] != 'Released')
          FilledButton(key: const ValueKey('lot-release'), onPressed: () => inspect(ctx, 'Released'), child: const Text('Liberar')),
        if (session.canStock && lot['status'] != 'Rejected') TextButton(onPressed: () => inspect(ctx, 'Rejected'), child: const Text('Rejeitar')),
        if (session.canStock && lot['status'] != 'Quarantine') TextButton(onPressed: () => inspect(ctx, 'Quarantine'), child: const Text('Quarentena')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
      ],
    ),
  );
}

const reservationFields = [
  FieldSpec('materialId', 'Material', type: FieldType.lookup, lookup: materialLookup, hint: 'Material ou produto, não ambos'),
  FieldSpec('productId', 'Produto', type: FieldType.lookup, lookup: productLookup),
  FieldSpec('locationId', 'Local', type: FieldType.lookup, lookup: locationLookup, hint: 'Vazio = qualquer local próprio'),
  FieldSpec('quantity', 'Quantidade', type: FieldType.decimal, required: true),
  FieldSpec('reference', 'Referência (OP / pedido)', required: true),
  FieldSpec('neededOn', 'Necessário em', type: FieldType.date),
];

class ReservationsView extends StatefulWidget {
  const ReservationsView({super.key, required this.session, this.query = const {}});

  final Session session;
  final Map<String, dynamic> query;

  @override
  State<ReservationsView> createState() => _ReservationsViewState();
}

class _ReservationsViewState extends State<ReservationsView> {
  final _list = GlobalKey<RecordListState>();
  String? _status = 'Open';

  Future<void> _new() async {
    final r = await submitForm(
      context,
      api: widget.session.api,
      title: 'Nova reserva',
      fields: reservationFields,
      initial: widget.query['materialId'] != null || widget.query['productId'] != null ? {...widget.query} : null,
      submit: (b) => widget.session.api.post('/api/stock/reservations', b),
    );
    if (r != null) _list.currentState?.reload();
  }

  Future<void> _open(Map<String, dynamic> e) async {
    if (!widget.session.canStock || e['status'] != 'Open') return;
    if (!await confirm(context, 'Liberar o saldo restante (${fmt(e['remaining'])}) da reserva ${e['reference']}?')) return;
    if (!mounted) return;
    await runAction(context, () => widget.session.api.post('/api/stock/reservations/${e['id']}/release', {}), success: 'Reserva liberada');
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.session.api;
    return RecordList(
      key: _list,
      api: api,
      path: '/api/stock/reservations',
      query: {...widget.query, 'status': _status},
      searchParam: 'reference',
      searchHint: 'Referência exata',
      filters: [ChoiceFilter(label: 'Situação', value: _status, choices: reservationStatuses, onChanged: (v) => setState(() => _status = v))],
      fab: widget.session.canStock
          ? FloatingActionButton.extended(heroTag: 'new-res', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Nova reserva'))
          : null,
      enrich: (items) async {
        await NameCache.attachItem(api, items);
        await NameCache.attach(api, items, 'locationId', '/api/stock-locations', 'locationCode', (l) => '${l['code']}');
      },
      columns: [
        col('Referência', 'reference'),
        col('Item', 'itemCode'),
        col('Local', 'locationCode'),
        col('Quantidade', 'quantity', numeric: true),
        col('Consumido', 'consumed', numeric: true),
        col('Restante', 'remaining', numeric: true),
        labelCol('Situação', 'status', reservationStatuses),
        dateCol('Necessário em', 'neededOn'),
        col('Criada por', 'createdBy'),
      ],
      onTap: _open,
    );
  }
}
