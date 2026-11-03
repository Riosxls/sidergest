import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/load_error.dart';
import '../widgets/pipeline.dart';
import '../widgets/record_list.dart';
import '../widgets/record_nav.dart';
import 'orders.dart';
import 'purchasing_path.dart';
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
  FieldSpec('neededBy', 'Necessário em', type: FieldType.date),
  FieldSpec('department', 'Departamento', advanced: true),
  FieldSpec('application', 'Aplicação', advanced: true),
  FieldSpec('notes', 'Observações', advanced: true),
];

Future<void> newRequisition(BuildContext context, Session session, {VoidCallback? onSaved}) async {
  final r = await submitForm(
    context,
    api: session.api,
    title: 'Nova requisição',
    fields: requisitionFields,
    submit: (b) => session.api.post('/api/requisitions', b),
  );
  if (r == null) return;
  onSaved?.call();
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Requisição nº ${r['number']} criada')));
}

/// Purchase requisitions list.
class RequisitionsScreen extends StatefulWidget {
  const RequisitionsScreen({super.key, required this.session, this.initialStatus});

  final Session session;
  final String? initialStatus;

  @override
  State<RequisitionsScreen> createState() => _RequisitionsScreenState();
}

class _RequisitionsScreenState extends State<RequisitionsScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _status;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus ?? (widget.session.canBuy ? 'PendingApproval' : null);
  }

  Future<void> _new() => newRequisition(context, widget.session, onSaved: () => _list.currentState?.reload());

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
      onTap: (e) => openRequisition(context, widget.session, e['id'] as int),
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

/// Opens a requisition page.
Future<void> openRequisition(BuildContext context, Session session, int id) =>
    pushRecord<void>(context, 'requisition', id, (_) => RequisitionScreen(session: session, id: id));

/// Purchase requisition page: its data, the stage of the purchase it is in, the next step and links to the quotation and order it led to.
class RequisitionScreen extends StatefulWidget {
  const RequisitionScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<RequisitionScreen> createState() => _RequisitionScreenState();
}

class _RequisitionScreenState extends State<RequisitionScreen> {
  Map<String, dynamic>? _r;
  String? _error;

  Session get s => widget.session;
  ApiClient get api => s.api;
  String get base => '/api/requisitions/${widget.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await api.get(base) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _r = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  /// Stage of the purchase this requisition has reached, and the label of a stage that ended off track.
  (int, String?) _path(Object? status) => switch (status) {
    'Rejected' => (0, 'Reprovada'),
    'Cancelled' => (0, 'Cancelada'),
    'Quoting' || 'QuoteApproved' => (1, null),
    'QuoteRejected' => (1, 'Cotação reprovada'),
    'OrderIssued' => (2, null),
    'PartiallyReceived' || 'Received' => (3, null),
    _ => (0, null),
  };

  Future<void> _approve() async {
    final r = _r!;
    final res = await submitForm(
      context,
      api: api,
      title: 'Aprovar requisição nº ${r['number']}',
      fields: const [
        FieldSpec('approvedQuantity', 'Quantidade aprovada', type: FieldType.decimal, required: true),
        FieldSpec('note', 'Observação'),
      ],
      initial: {'approvedQuantity': r['quantity']},
      submit: (b) => api.post('$base/approve', b),
    );
    if (res == null || !mounted) return;
    setState(() => _r = res);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Requisição aprovada'),
        duration: const Duration(seconds: 10),
        persist: false,
        action: s.canBuy ? SnackBarAction(label: 'Cotar agora', onPressed: _quote) : null,
      ),
    );
  }

  Future<void> _reject() async {
    final note = await promptText(context, title: 'Reprovar requisição', label: 'Motivo', required: true, confirmLabel: 'Reprovar');
    if (note == null || !mounted) return;
    final res = await runAction(context, () => api.post('$base/reject', {'note': note}), success: 'Requisição reprovada');
    if (res is Map<String, dynamic> && mounted) setState(() => _r = res);
  }

  Future<void> _cancel() async {
    final reason = await promptText(
      context,
      title: 'Cancelar requisição nº ${_r!['number']}',
      label: 'Motivo',
      required: true,
      confirmLabel: 'Cancelar requisição',
    );
    if (reason == null || !mounted) return;
    final res = await runAction(context, () => api.post('$base/cancel', {'reason': reason}), success: 'Requisição cancelada');
    if (res is Map<String, dynamic> && mounted) setState(() => _r = res);
  }

  /// Starts a quotation with this requisition already selected.
  Future<void> _quote() async {
    final q = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewQuotationDialog(api: api, initialRequisitionIds: {widget.id}),
    );
    if (q == null || !mounted) return;
    await _load();
    if (mounted) await openQuotation(context, s, q['id'] as int);
    if (mounted) unawaited(_load());
  }

  Future<void> _openQuotation() => openQuotation(context, s, _r!['quotationId'] as int).then((_) => _load());

  Future<void> _openOrder() => openPurchaseOrder(context, s, _r!['purchaseOrderId'] as int).then((_) => _load());

  Widget _nextStep(Map<String, dynamic> r) {
    final error = Theme.of(context).colorScheme.error;
    final Widget? cancel = s.canRequest && _cancellable.contains(r['status'])
        ? OutlinedButton.icon(
            key: const ValueKey('req-cancel'),
            onPressed: _cancel,
            icon: const Icon(Icons.block),
            label: const Text('Cancelar requisição'),
            style: OutlinedButton.styleFrom(foregroundColor: error, side: BorderSide(color: error.withValues(alpha: 0.7))),
          )
        : null;
    final Widget? openQuote = r['quotationId'] == null
        ? null
        : OutlinedButton.icon(key: const ValueKey('req-open-quotation'), onPressed: _openQuotation, icon: const Icon(Icons.open_in_new), label: const Text('Abrir cotação'));
    final Widget? openOrder = r['purchaseOrderId'] == null
        ? null
        : OutlinedButton.icon(key: const ValueKey('req-open-order'), onPressed: _openOrder, icon: const Icon(Icons.open_in_new), label: const Text('Abrir pedido'));
    return switch (r['status']) {
      'PendingApproval' => NextStepCard(
        title: 'Aguardando aprovação',
        message: s.canBuy ? 'Aprove a quantidade para liberar a requisição para cotação, ou reprove com o motivo.' : 'O comprador ainda vai aprovar ou reprovar.',
        tone: Tone.warning,
        actions: [
          if (s.canBuy) FilledButton.icon(key: const ValueKey('req-approve'), onPressed: _approve, icon: const Icon(Icons.thumb_up_alt_outlined), label: const Text('Aprovar')),
          if (s.canBuy) OutlinedButton.icon(key: const ValueKey('req-reject'), onPressed: _reject, icon: const Icon(Icons.thumb_down_alt_outlined), label: const Text('Reprovar')),
          ?cancel,
        ],
      ),
      'Approved' => NextStepCard(
        title: 'Aprovada · falta cotar',
        message: 'Inclua esta requisição numa cotação para pedir preço aos fornecedores.',
        tone: Tone.success,
        actions: [
          if (s.canBuy) FilledButton.icon(key: const ValueKey('req-quote'), onPressed: _quote, icon: const Icon(Icons.request_quote_outlined), label: const Text('Cotar agora')),
          ?cancel,
        ],
      ),
      'Rejected' => NextStepCard(title: 'Reprovada', message: '${r['decisionNote'] ?? ''}', tone: Tone.danger, actions: [?cancel]),
      'Quoting' => NextStepCard(
        title: 'Em cotação',
        message: 'Registre as propostas e aprove a vencedora na cotação.',
        tone: Tone.progress,
        actions: [?openQuote],
      ),
      'QuoteApproved' => NextStepCard(
        title: 'Cotação aprovada',
        message: 'Gere o pedido de compra a partir da cotação.',
        tone: Tone.success,
        actions: [?openQuote],
      ),
      'QuoteRejected' => NextStepCard(
        title: 'Cotação reprovada',
        message: 'Nenhuma proposta foi aprovada para este item. Cancele a requisição ou peça uma nova.',
        tone: Tone.danger,
        actions: [?openQuote, ?cancel],
      ),
      'OrderIssued' => NextStepCard(title: 'Pedido emitido', message: 'Aguardando a entrega do fornecedor.', tone: Tone.progress, actions: [?openOrder]),
      'PartiallyReceived' => NextStepCard(title: 'Recebida parcialmente', message: 'Parte do material já chegou.', tone: Tone.progress, actions: [?openOrder]),
      'Received' => NextStepCard(title: 'Recebida', message: 'Todo o material chegou.', tone: Tone.success, actions: [?openOrder]),
      _ => NextStepCard(title: 'Cancelada', message: '${r['decisionNote'] ?? ''}', tone: Tone.danger),
    };
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final (step, failed) = _path(r?['status']);
    return Scaffold(
      appBar: AppBar(
        title: Text(r == null ? 'Requisição' : 'Requisição nº ${r['number']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (r != null)
            RelatedMenu(
              links: [
                if (r['quotationId'] != null) RelatedLink(Icons.request_quote_outlined, 'Cotação nº ${r['quotationNumber']}', _openQuotation),
                if (r['purchaseOrderId'] != null) RelatedLink(Icons.receipt_long_outlined, 'Pedido nº ${r['purchaseOrderNumber']}', _openOrder),
              ],
            ),
        ],
      ),
      body: _error != null && r == null
          ? LoadError(message: _error!, onRetry: _load)
          : r == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  PurchasingPath(
                    current: step,
                    page: 0,
                    failedLabel: failed,
                    quotation: r['quotationId'] == null ? null : _openQuotation,
                    order: r['purchaseOrderId'] == null ? null : _openOrder,
                  ),
                  const SizedBox(height: 12),
                  _nextStep(r),
                  const SizedBox(height: 12),
                  Section(
                    title: 'Requisição',
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
                ],
              ),
            ),
    );
  }
}
