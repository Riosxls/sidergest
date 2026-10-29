import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../reports/nf_doc.dart';
import '../widgets/actions.dart';
import '../widgets/pipeline.dart';
import '../widgets/record_list.dart';
import 'certificates.dart';
import 'fiscal.dart';
import 'orders.dart';
import 'sales_common.dart';
import 'stock_documents.dart';

class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({super.key, required this.session});

  final Session session;

  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _status = 'Planned';

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: widget.session.api,
    path: '/api/sales/deliveries',
    query: {'status': _status},
    searchHint: 'Entrega, pedido, cliente ou NF',
    filters: [ChoiceFilter(label: 'Situação', value: _status, choices: deliveryStatuses, onChanged: (v) => setState(() => _status = v))],
    columns: [
      col('Entrega', 'reference'),
      col('Pedido', 'orderReference'),
      col('Cliente', 'customerName'),
      dateCol('Data', 'plannedDate'),
      labelCol('Situação', 'status', deliveryStatuses),
      col('Volumes', 'packages', numeric: true),
      col('Peso (kg)', 'grossWeightKg', numeric: true),
      col('NF', 'invoiceNumber'),
    ],
    rowColor: (ctx, e) => e['status'] == 'Planned' && isLate(e['plannedDate']) ? toneColors(ctx, Tone.danger).$1 : null,
    onTap: (e) async {
      await openDelivery(context, widget.session, e['id'] as int);
      _list.currentState?.reload();
    },
  );
}

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  Map<String, dynamic>? _d;
  Map<String, dynamic>? _nf;
  List<Map<String, dynamic>> _certs = const [];
  String? _error;

  ApiClient get api => widget.session.api;
  Session get s => widget.session;
  String get base => '/api/sales/deliveries/${widget.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await api.get(base) as Map<String, dynamic>;
      // The NF lookup is optional: a fiscal failure must not hide the delivery.
      List<Map<String, dynamic>> nfItems = const [];
      try {
        final nfs = await api.get('/api/fiscal/documents', {'deliveryId': widget.id, 'status': 'Authorized'}) as Map<String, dynamic>;
        nfItems = (nfs['items'] as List).cast<Map<String, dynamic>>();
      } catch (_) {}
      var certs = const <Map<String, dynamic>>[];
      try {
        certs = (await api.list('/api/sales/certificates', query: {'deliveryId': widget.id}, take: 100)).items;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _certs = certs;
          _nf = nfItems.isEmpty ? null : nfItems.first;
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _ship() async {
    final d = _d!;
    final r = await submitForm(
      context,
      api: api,
      title: 'Expedir ${d['reference']}',
      fields: [
        FieldSpec('date', 'Data de saída', type: FieldType.date, required: true, defaultValue: isoDate(DateTime.now())),
        const FieldSpec('invoiceNumber', 'Nº da NF', hint: 'Vazio = emitir a NF-e automaticamente (emissor ligado); preencha só se a NF foi emitida fora'),
        const FieldSpec('cfop', 'CFOP', hint: 'Vazio = CFOP do endereço de entrega ou 5101'),
        const FieldSpec('freight', 'Frete na NF (R\$)', type: FieldType.decimal),
        const FieldSpec('lotNumber', 'Nº do lote'),
        const FieldSpec('invoicedValue', 'Valor faturado (R\$)', type: FieldType.decimal, hint: 'Total da NF, com impostos'),
        FieldSpec('grossWeightKg', 'Peso bruto (kg)', type: FieldType.decimal, defaultValue: d['grossWeightKg']),
      ],
      submit: (b) => api.post('$base/ship', b),
    );
    if (r != null && r['reference'] != null) {
      setState(() => _d = r);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entrega expedida e estoque baixado')));
        await _printNf();
      }
    }
  }

  Future<void> _printNf() => printNf(
    context,
    name: 'NF ${_d!['reference']}',
    number: _d!['invoiceNumber'] == null ? '' : '${_d!['invoiceNumber']}',
    build: (f) => buildSaleNfPdf(api, _d!, f),
  );

  Future<void> _confirm() async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Confirmar recebimento · ${_d!['reference']}',
      fields: [
        FieldSpec('date', 'Data de recebimento', type: FieldType.date, required: true, defaultValue: isoDate(DateTime.now())),
        const FieldSpec('receivedBy', 'Recebido por'),
      ],
      submit: (b) => api.post('$base/confirm', b),
    );
    if (r != null && r['reference'] != null) setState(() => _d = r);
  }

  Future<void> _cancel() async {
    final shipped = _d!['status'] == 'Shipped';
    final reason = await promptText(
      context,
      title: shipped ? 'Cancelar expedição ${_d!['reference']}' : 'Cancelar ${_d!['reference']}',
      label: shipped ? 'Motivo (a baixa de estoque será estornada)' : 'Motivo',
      required: true,
      confirmLabel: 'Cancelar entrega',
    );
    if (reason == null || !mounted) return;
    final r = await runAction(context, () => api.post('$base/cancel', {'reason': reason}), success: 'Entrega cancelada');
    if (r is Map<String, dynamic>) setState(() => _d = r);
  }

  Widget _nextStep(Map<String, dynamic> d) => switch (d['status']) {
    'Planned' => NextStepCard(
      title: 'Programada para ${fmtDay(d['plannedDate'])}',
      message: 'Ao expedir, o produto acabado sai do estoque de expedição usando a reserva do pedido.',
      actions: [
        if (s.canShip)
          FilledButton.icon(key: const ValueKey('delivery-ship'), onPressed: _ship, icon: const Icon(Icons.local_shipping), label: const Text('Expedir')),
      ],
    ),
    'Shipped' => NextStepCard(
      title: 'Em trânsito',
      message: 'Saiu em ${fmtDate(d['shippedAt'])}${d['invoiceNumber'] == null ? '' : ' com a NF ${d['invoiceNumber']}'}. Confirme quando o cliente receber.',
      tone: Tone.progress,
      actions: [
        if (s.canShip)
          FilledButton.icon(
            key: const ValueKey('delivery-confirm'),
            onPressed: _confirm,
            icon: const Icon(Icons.task_alt),
            label: const Text('Confirmar entrega'),
          ),
      ],
    ),
    'Delivered' => NextStepCard(
      title: 'Entregue',
      message: 'Recebida em ${fmtDay(d['deliveredAt'])}${d['receivedBy'] == null ? '' : ' por ${d['receivedBy']}'}.',
      tone: Tone.success,
    ),
    _ => const NextStepCard(title: 'Cancelada', message: 'Veja o motivo no histórico.', tone: Tone.danger),
  };

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final canCancel = s.canShip && ['Planned', 'Shipped'].contains(d?['status']);
    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'Entrega' : '${d['reference']} · ${d['customerName']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (d != null && ['Shipped', 'Delivered'].contains(d['status']))
            IconButton(key: const ValueKey('delivery-print-nf'), tooltip: 'Imprimir NF', icon: const Icon(Icons.print_outlined), onPressed: _printNf),
          if (canCancel)
            PopupMenuButton<VoidCallback>(
              onSelected: (f) => f(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _cancel,
                  child: const ListTile(leading: Icon(Icons.block), title: Text('Cancelar entrega')),
                ),
              ],
            ),
        ],
      ),
      body: _error != null && d == null
          ? Center(child: Text(_error!))
          : d == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(d)),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final (step, failed) = deliveryPath(d['status']);
    return SideBySide(
      main: [
        RecordHeader(
          icon: Icons.local_shipping_outlined,
          kind: 'Entrega',
          title: '${d['reference']}',
          badge: StatusBadge(deliveryStatuses[d['status']] ?? '${d['status']}', tone: deliveryTone(d['status'])),
          fields: [
            ('Cliente', '${d['customerName']}'),
            ('Pedido', '${d['orderReference']}'),
            ('Data programada', fmtDay(d['plannedDate'])),
            ('Volumes', fmt(d['packages'])),
            ('Peso bruto (kg)', fmt(d['grossWeightKg'])),
            ('NF', fmt(d['invoiceNumber'])),
            ('Nº do lote', fmt(d['lotNumber'])),
            ('Valor faturado', d['invoicedValue'] == null ? '' : fmtMoney(d['invoicedValue'])),
            ('Valor s/ IPI', fmtMoney(d['valueExIpi'])),
            ('Saldo do pedido (kg)', fmt(d['balanceKg'])),
            ('Saldo do pedido (R\$)', fmtMoney(d['balanceValue'])),
          ],
        ),
        gap,
        StagePath(steps: flowSteps, current: step, failedLabel: failed),
        gap,
        _nextStep(d),
        gap,
        Section(
          title: 'Itens',
          actions: [
            TextButton.icon(
              onPressed: () => openSalesOrder(context, s, d['orderId'] as int).then((_) => _load()),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Ver pedido'),
            ),
            if (d['stockDocumentId'] != null)
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DocumentScreen(session: s, id: d['stockDocumentId'] as int),
                  ),
                ),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Movimento de estoque'),
              ),
          ],
          child: SimpleTable(
            columns: [
              col('Item', 'sequence'),
              col('Produto', 'productCode'),
              col('Descrição', 'description'),
              ColumnSpec('Quantidade', (e) => '${fmt(e['quantity'])} ${e['unit']}', numeric: true),
              col('Volumes', 'packages', numeric: true),
            ],
            rows: (d['lines'] as List).cast<Map<String, dynamic>>(),
          ),
        ),
        gap,
        Section(
          title: 'Certificados de qualidade (${_certs.length})',
          actions: [
            if (s.canCertificate && ['Planned', 'Shipped'].contains(d['status']))
              FilledButton.tonalIcon(
                key: const ValueKey('delivery-new-certificate'),
                onPressed: () async {
                  final order = await api.get('/api/sales/orders/${d['orderId']}') as Map<String, dynamic>;
                  if (mounted && await newCertificate(context, s, order, deliveryId: d['id'] as int)) _load();
                },
                icon: const Icon(Icons.add),
                label: const Text('Emitir certificado'),
              ),
          ],
          child: SimpleTable(
            columns: [
              col('Certificado', 'reference'),
              dateCol('Data', 'issueDate'),
              labelCol('Situação', 'status', certificateStatuses),
              col('Produto', 'description'),
              ColumnSpec('Qtd.', (e) => '${fmt(e['quantity'])} ${e['unit']}', numeric: true),
            ],
            rows: _certs,
            actions: (c) => [
              IconButton(
                tooltip: 'Abrir',
                icon: const Icon(Icons.open_in_new, size: 20),
                onPressed: () => openCertificate(context, s, c['id'] as int).then((_) => _load()),
              ),
            ],
          ),
        ),
        if (_nf != null) ...[
          gap,
          Section(
            title: 'Nota fiscal eletrônica',
            actions: [
              TextButton.icon(
                key: const ValueKey('delivery-open-nf'),
                onPressed: () => openFiscalDocument(context, s, _nf!['id'] as int).then((_) => _load()),
                icon: const Icon(Icons.description_outlined),
                label: const Text('Abrir NF'),
              ),
            ],
            child: InfoGrid([
              ('Número', '${_nf!['number']} · série ${_nf!['series']}'),
              ('CFOP', fmt(_nf!['cfopCode'])),
              ('Valor', fmtMoney(_nf!['invoiceTotal'])),
              ('Chave', fmt(_nf!['accessKey'])),
              ('Autorização', _nf!['simulated'] == true ? 'SIMULADA (sem valor fiscal)' : 'SEFAZ'),
            ]),
          ),
        ],
        gap,
        Section(
          title: 'Detalhes',
          child: InfoGrid([
            ('Local de entrega', fmt(d['addressText'])),
            ('Observações', fmt(d['notes'])),
            ('Criada', '${fmt(d['createdBy'])} · ${fmtDate(d['createdAt'])}'),
            ('Expedida', d['shippedAt'] == null ? '' : '${fmt(d['shippedBy'])} · ${fmtDate(d['shippedAt'])}'),
          ]),
        ),
      ],
      side: [
        Section(
          title: 'Histórico',
          child: TimelineView(entries: timeline(d['history'] as List)),
        ),
      ],
    );
  }
}
