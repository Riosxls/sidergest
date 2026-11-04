import 'dart:async';
import 'package:flutter/material.dart';

import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/record_list.dart';
import '../widgets/responsive.dart';
import 'stock_balances.dart';
import 'stock_documents.dart';
import 'suppliers.dart';

/// Stock lots list.
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
      filtersActive: _status != null,
      onClearFilters: () => setState(() => _status = null),
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
  String? error;
  var busy = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        Future<void> inspect(String status) async {
          String? note;
          if (status != 'Released') {
            note = await promptText(
              ctx,
              title: status == 'Rejected' ? 'Rejeitar lote ${lot['code']}' : 'Mover lote ${lot['code']} para quarentena',
              label: 'Laudo / motivo',
              required: status == 'Rejected',
            );
            if (note == null) return;
          }
          if (!ctx.mounted) return;
          set(() {
            busy = true;
            error = null;
          });
          try {
            await session.api.put('/api/stock/lots/${lot['id']}/inspection', {'status': status, 'note': note});
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lote ${lot['code']}: ${lotStatuses[status]}')));
          } catch (e) {
            // The failure is shown where the user is looking: a snackbar would sit behind the dialog.
            if (ctx.mounted) {
              set(() {
                busy = false;
                error = friendlyError(e);
              });
            }
          }
        }

        void open(Future<void> Function() go) {
          Navigator.pop(ctx);
          unawaited(go());
        }

        final itemId = (lot['materialId'] ?? lot['productId']) as int?;
        return AlertDialog(
          title: Text('Lote ${lot['code']} · ${lot['itemCode']}'),
          content: SizedBox(
            width: dialogWidth(context, 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
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
                ),
                if (itemId != null || lot['supplierId'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (itemId != null)
                          TextButton.icon(
                            key: const ValueKey('lot-open-item'),
                            onPressed: () => open(() => openItemStock(context, session, materialId: lot['materialId'] as int?, productId: lot['productId'] as int?)),
                            icon: const Icon(Icons.inventory_outlined, size: 18),
                            label: const Text('Ver saldo do item'),
                          ),
                        if (lot['supplierId'] != null)
                          TextButton.icon(
                            onPressed: () => open(() => openSupplier(context, session, lot['supplierId'] as int)),
                            icon: const Icon(Icons.business_outlined, size: 18),
                            label: const Text('Ver fornecedor'),
                          ),
                      ],
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(liveRegion: true, child: Text(error!, key: const ValueKey('lot-error'), style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
                  ),
              ],
            ),
          ),
          actions: [
            if (session.canStock && lot['status'] != 'Released')
              FilledButton(key: const ValueKey('lot-release'), onPressed: busy ? null : () => inspect('Released'), child: const Text('Liberar')),
            if (session.canStock && lot['status'] != 'Quarantine')
              TextButton(onPressed: busy ? null : () => inspect('Quarantine'), child: const Text('Mover para quarentena')),
            if (session.canStock && lot['status'] != 'Rejected')
              TextButton(
                key: const ValueKey('lot-reject'),
                style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: busy ? null : () => inspect('Rejected'),
                child: const Text('Rejeitar'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          ],
        );
      },
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

/// Stock reservations list filtered by a query.
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
    if (r != null) unawaited(_list.currentState?.reload());
  }

  bool _canRelease(Map<String, dynamic> e) => widget.session.canStock && e['status'] == 'Open';

  Future<void> _release(Map<String, dynamic> e) async {
    if (!await confirm(context, 'Liberar o saldo restante (${fmt(e['remaining'])}) da reserva ${e['reference']}?')) return;
    if (!mounted) return;
    await runAction(context, () => widget.session.api.post('/api/stock/reservations/${e['id']}/release', {}), success: 'Reserva liberada');
  }

  /// A reservation opens its details; releasing the balance is a button there and an entry of the row menu.
  Future<void> _open(Map<String, dynamic> e) async {
    final release = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reserva ${e['reference']}'),
        content: SizedBox(
          width: dialogWidth(context, 440),
          child: InfoGrid([
            ('Item', fmt(e['itemCode'])),
            ('Local', fmt(e['locationCode'])),
            ('Situação', reservationStatuses[e['status']] ?? fmt(e['status'])),
            ('Quantidade', fmt(e['quantity'])),
            ('Consumido', fmt(e['consumed'])),
            ('Restante', fmt(e['remaining'])),
            ('Necessário em', e['neededOn'] == null ? '' : fmtDay(e['neededOn'])),
            ('Criada por', '${fmt(e['createdBy'])} · ${fmtDate(e['createdAt'])}'),
          ]),
        ),
        actions: [
          if (_canRelease(e))
            FilledButton(key: const ValueKey('reservation-release'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Liberar saldo restante')),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Fechar')),
        ],
      ),
    );
    if (release == true && mounted) await _release(e);
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
      filtersActive: _status != null,
      onClearFilters: () => setState(() => _status = null),
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
      rowActions: (e) => [
        if (_canRelease(e)) RowAction('Liberar saldo', Icons.lock_open_outlined, () => _release(e)),
        if ((e['materialId'] != null || e['productId'] != null) && widget.query['materialId'] == null && widget.query['productId'] == null)
          RowAction('Saldo do item', Icons.inventory_outlined, () => openItemStock(context, widget.session, materialId: e['materialId'] as int?, productId: e['productId'] as int?)),
      ],
      onTap: _open,
    );
  }
}
