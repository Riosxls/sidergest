import 'package:flutter/material.dart';

import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/record_list.dart';
import 'orders.dart';
import 'quotations.dart';

const requisitionFields = [
  FieldSpec(
    'materialId',
    'Material',
    type: FieldType.lookup,
    lookup: LookupSpec('/api/materials', fill: {'unit': 'purchaseUnit', 'description': 'description'}),
    hint: 'Vazio = item não cadastrado',
  ),
  FieldSpec('description', 'Descrição'),
  FieldSpec('unit', 'Unidade'),
  FieldSpec('quantity', 'Quantidade', type: FieldType.decimal, required: true),
  FieldSpec('department', 'Departamento'),
  FieldSpec('neededBy', 'Necessário em', type: FieldType.date),
  FieldSpec('application', 'Aplicação'),
  FieldSpec('notes', 'Observações'),
];

class RequisitionsScreen extends StatefulWidget {
  const RequisitionsScreen({super.key, required this.session});

  final Session session;

  @override
  State<RequisitionsScreen> createState() => _RequisitionsScreenState();
}

class _RequisitionsScreenState extends State<RequisitionsScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _status;

  @override
  void initState() {
    super.initState();
    if (widget.session.canBuy) _status = 'PendingApproval';
  }

  Future<void> _new() async {
    final r = await submitForm(
      context,
      api: widget.session.api,
      title: 'Nova requisição',
      fields: requisitionFields,
      submit: (b) => widget.session.api.post('/api/requisitions', b),
    );
    if (r != null) {
      _list.currentState?.reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Requisição nº ${r['number']} criada')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RecordList(
      key: _list,
      api: widget.session.api,
      path: '/api/requisitions',
      query: {'status': _status},
      searchHint: 'Número ou descrição',
      filters: [ChoiceFilter(label: 'Situação', value: _status, choices: requisitionStatuses, onChanged: (v) => setState(() => _status = v))],
      fab: widget.session.canRequest
          ? FloatingActionButton.extended(heroTag: 'new-req', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Nova requisição'))
          : null,
      columns: requisitionColumns,
      rowColor: (_, e) => e['status'] == 'PendingApproval' ? cs.tertiaryContainer : null,
      onTap: (e) => showRequisition(context, widget.session, e),
    );
  }
}

final requisitionColumns = [
  col('Nº', 'number'),
  col('Descrição', 'description'),
  col('Material', 'materialCode'),
  ColumnSpec('Quantidade', (e) => '${fmt(e['approvedQuantity'] ?? e['quantity'])} ${e['unit']}', numeric: true),
  col('Depto.', 'department'),
  dateCol('Necessário em', 'neededBy'),
  labelCol('Situação', 'status', requisitionStatuses),
  col('Solicitante', 'requestedBy'),
  dateCol('Data', 'requestedAt'),
  col('Cotação', 'quotationNumber'),
  col('Pedido', 'purchaseOrderNumber'),
];

const _cancellable = {'PendingApproval', 'Approved', 'Rejected', 'QuoteRejected'};

Future<void> showRequisition(BuildContext context, Session session, Map<String, dynamic> r) async {
  final api = session.api;
  final base = '/api/requisitions/${r['id']}';

  Future<void> act(BuildContext ctx, Future<dynamic> Function() call, String msg) async {
    final res = await runAction(ctx, call, success: msg);
    if (res != null && ctx.mounted) Navigator.pop(ctx);
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Requisição nº ${r['number']}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: InfoGrid([
            ('Situação', requisitionStatuses[r['status']] ?? fmt(r['status'])),
            ('Material', fmt(r['materialCode'])),
            ('Descrição', fmt(r['description'])),
            ('Quantidade', '${fmt(r['quantity'])} ${r['unit']}'),
            ('Aprovada', r['approvedQuantity'] == null ? '' : '${fmt(r['approvedQuantity'])} ${r['unit']}'),
            ('Departamento', fmt(r['department'])),
            ('Necessário em', fmtDay(r['neededBy'])),
            ('Aplicação', fmt(r['application'])),
            ('Observações', fmt(r['notes'])),
            ('Solicitado por', '${fmt(r['requestedBy'])} · ${fmtDate(r['requestedAt'])}'),
            ('Decisão', r['decidedBy'] == null ? '' : '${r['decidedBy']} · ${fmtDate(r['decidedAt'])}'),
            ('Nota da decisão', fmt(r['decisionNote'])),
            ('Cotação', fmt(r['quotationNumber'])),
            ('Pedido', fmt(r['purchaseOrderNumber'])),
          ]),
        ),
      ),
      actions: [
        if (r['quotationId'] != null)
          TextButton(
            onPressed: () => Navigator.of(ctx).push(
              MaterialPageRoute(
                builder: (_) => QuotationScreen(session: session, id: r['quotationId'] as int),
              ),
            ),
            child: const Text('Abrir cotação'),
          ),
        if (r['purchaseOrderId'] != null)
          TextButton(
            onPressed: () => Navigator.of(ctx).push(
              MaterialPageRoute(
                builder: (_) => OrderScreen(session: session, id: r['purchaseOrderId'] as int),
              ),
            ),
            child: const Text('Abrir pedido'),
          ),
        if (session.canRequest && _cancellable.contains(r['status']))
          TextButton(
            onPressed: () async {
              final reason = await promptText(ctx, title: 'Cancelar requisição', label: 'Motivo', confirmLabel: 'Cancelar requisição');
              if (reason != null && ctx.mounted) await act(ctx, () => api.post('$base/cancel', {'reason': reason}), 'Requisição cancelada');
            },
            child: const Text('Cancelar'),
          ),
        if (session.canBuy && r['status'] == 'PendingApproval') ...[
          TextButton(
            onPressed: () async {
              final note = await promptText(ctx, title: 'Reprovar requisição', label: 'Motivo', required: true, confirmLabel: 'Reprovar');
              if (note != null && ctx.mounted) await act(ctx, () => api.post('$base/reject', {'note': note}), 'Requisição reprovada');
            },
            child: const Text('Reprovar'),
          ),
          FilledButton(
            key: const ValueKey('req-approve'),
            onPressed: () async {
              final res = await submitForm(
                ctx,
                api: api,
                title: 'Aprovar requisição nº ${r['number']}',
                fields: const [
                  FieldSpec('approvedQuantity', 'Quantidade aprovada', type: FieldType.decimal, required: true),
                  FieldSpec('note', 'Observação'),
                ],
                initial: {'approvedQuantity': r['quantity']},
                submit: (b) => api.post('$base/approve', b),
              );
              if (res != null && ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Requisição aprovada')));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Aprovar'),
          ),
        ],
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
      ],
    ),
  );
}
