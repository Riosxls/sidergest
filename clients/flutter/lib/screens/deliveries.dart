import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../reports/certificate_doc.dart';
import '../reports/nf_doc.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart' show showError;
import '../widgets/load_error.dart';
import '../widgets/pipeline.dart';
import '../widgets/print_gate.dart';
import '../widgets/print_panel.dart';
import '../widgets/record_list.dart';
import '../widgets/record_shortcuts.dart';
import 'certificates.dart';
import 'customers.dart';
import 'fiscal.dart';
import 'orders.dart';
import 'sales_common.dart';
import 'sales_orders.dart' show ReasonDialog;
import 'stock_documents.dart';

/// List of deliveries (Entregas).
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
    filtersActive: _status != null,
    onClearFilters: () => setState(() => _status = null),
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
      unawaited(_list.currentState?.reload());
    },
  );
}

/// Delivery detail: items, shipment confirmation (with the certificate rule), NF emission and printing.
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
  bool? _certified;

  ApiClient get api => widget.session.api;
  Session get s => widget.session;
  String get base => '/api/sales/deliveries/${widget.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reloads the delivery with its NF and certificates. [report]: the user asked (F5, refresh button), so a failure is said even when the old data stays.
  Future<void> _load({bool report = false}) async {
    try {
      final d = await api.get(base) as Map<String, dynamic>;
      // The NF lookup is optional: a fiscal failure must not hide the delivery.
      List<Map<String, dynamic>> nfItems = const [];
      try {
        final nfs = await api.get('/api/fiscal/documents', {'deliveryId': widget.id, 'status': 'Authorized'}) as Map<String, dynamic>;
        nfItems = (nfs['items'] as List).cast<Map<String, dynamic>>();
      } catch (e) {
        debugPrint('deliveries: Optional context; the screen works without it: $e');
        // Optional context; the screen works without it.
      }
      var certs = const <Map<String, dynamic>>[];
      try {
        certs = (await api.list('/api/sales/certificates', query: {'deliveryId': widget.id}, take: 100)).items;
      } catch (e) {
        debugPrint('deliveries: Optional context; the screen works without it: $e');
        // Optional context; the screen works without it.
      }
      // null = unknown (lookup failed): the server still enforces the rule when shipping.
      bool? certified;
      try {
        final order = await api.get('/api/sales/orders/${d['orderId']}') as Map<String, dynamic>;
        final issued = (await api.list('/api/sales/certificates', query: {'orderId': d['orderId']}, take: 200)).items;
        certified = order['certificateWaived'] == true || issued.any((c) => c['status'] == 'Issued');
      } catch (e) {
        debugPrint('deliveries: Optional context; the screen works without it: $e');
        // Optional context; the screen works without it.
      }
      if (mounted) {
        setState(() {
          _certified = certified;
          _certs = certs;
          _nf = nfItems.isEmpty ? null : nfItems.first;
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (_d != null) {
        if (report) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao atualizar: ${friendlyError(e)}')));
        return;
      }
      setState(() => _error = friendlyError(e));
    }
  }

  void _refresh() => unawaited(_load(report: true));

  /// What shipping this delivery does, in a line under the date field of the form.
  String _shipSummary(Map<String, dynamic> d) {
    final lines = (d['lines'] as List).cast<Map<String, dynamic>>();
    final items = lines.map((l) => '${fmt(l['quantity'])} ${l['unit']} do item ${l['sequence']}').join(', ');
    return 'Sai do estoque: $items. A baixa é feita ao confirmar; a NF-e é emitida junto quando o emissor fiscal está ligado.';
  }

  Future<void> _ship() async {
    final d = _d!;
    var withoutCertificate = false;
    if (_certified == false) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.verified_outlined),
          title: const Text('Expedir sem certificado?'),
          content: Text('${d['orderReference']} não tem certificado de qualidade emitido nem dispensado. O ideal é emitir (ou dispensar) o certificado no pedido antes de expedir.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            // Skipping the certificate is the exception the rule allows, not the normal way: the button looks like one.
            FilledButton(
              key: const ValueKey('ship-without-certificate'),
              style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error, foregroundColor: Theme.of(c).colorScheme.onError),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Expedir sem certificado'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
      withoutCertificate = true;
    }
    if (!await _certificateGate() || !mounted) return;
    final r = await submitForm(
      context,
      api: api,
      title: 'Expedir ${d['reference']}',
      fields: [
        FieldSpec('date', 'Data de saída', type: FieldType.date, required: true, defaultValue: isoDate(DateTime.now()), hint: _shipSummary(d)),
        const FieldSpec('invoiceNumber', 'Nº da NF', hint: 'Vazio = emitir a NF-e automaticamente (emissor ligado); preencha só se a NF foi emitida fora'),
        const FieldSpec('cfop', 'CFOP', advanced: true, hint: 'Vazio = CFOP do endereço de entrega ou 5101'),
        const FieldSpec('freight', 'Frete na NF (R\$)', type: FieldType.decimal, advanced: true),
        const FieldSpec('lotNumber', 'Nº do lote', advanced: true),
        const FieldSpec('invoicedValue', 'Valor faturado (R\$)', type: FieldType.decimal, advanced: true, hint: 'Total da NF, com impostos'),
        FieldSpec('grossWeightKg', 'Peso bruto (kg)', type: FieldType.decimal, advanced: true, defaultValue: d['grossWeightKg']),
        if (s.canApproveSales) const FieldSpec('overrideCredit', 'Autorizar acima do limite de crédito', type: FieldType.boolean, defaultValue: false, hint: 'Só vale se o cliente passou do limite; fica no histórico'),
      ],
      submit: (b) => api.post('$base/ship', {...b, if (withoutCertificate) 'withoutCertificate': true}),
    );
    if (r != null && r['reference'] != null && mounted) {
      setState(() => _d = r);
      // The NF (and what came with it) is on the server now: show it without a manual reload. Printing is the user's call, from the snackbar or the card.
      unawaited(_load());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Entrega expedida e estoque baixado'),
          duration: const Duration(seconds: 15),
          persist: false,
          action: SnackBarAction(label: 'Imprimir NF', onPressed: () => unawaited(_printNf())),
        ),
      );
    }
  }

  Future<bool> _printNf() => printNf(
    context,
    name: 'NF ${_d!['reference']}',
    number: _d!['invoiceNumber'] == null ? '' : '${_d!['invoiceNumber']}',
    build: (f) => buildSaleNfPdf(api, _d!, f),
  );

  /// The issued certificates travel with the goods: offer to print or download them before the delivery leaves, once.
  Future<bool> _certificateGate() async {
    final issued = _certs.where((c) => c['status'] == 'Issued').toList();
    if (issued.isEmpty) return true;
    final refs = issued.map((c) => '${c['reference']}').join(', ');
    Future<Uint8List> pdf(Map<String, dynamic> c) async => buildCertificatePdf(await api.get('/api/sales/certificates/${c['id']}') as Map<String, dynamic>);
    final key = 'delivery:${widget.id}:certificates:${issued.map((c) => c['id']).join(',')}';
    // Typed to answer whether every certificate went out, so a cancelled print dialog leaves the gate asking next time.
    Future<bool> printAll() async {
      var all = true;
      for (final c in issued) {
        all = await printPdf(context, 'Certificado de qualidade ${c['reference']}', () => pdf(c)) && all;
      }
      return all;
    }

    Future<bool> saveAll() async {
      var all = true;
      for (final c in issued) {
        all = await savePdf(context, 'Certificado de qualidade ${c['reference']}.pdf', () => pdf(c)) && all;
      }
      return all;
    }

    return printGate(
      context,
      doneKey: key,
      title: issued.length == 1 ? 'Imprimir o certificado?' : 'Imprimir os certificados?',
      message: 'Antes de expedir, imprima ou baixe $refs para acompanhar a mercadoria.',
      onPrint: printAll,
      onDownload: saveAll,
    );
  }

  /// Delivery items that still have no certificate (cancelled ones do not count).
  int _missingCertificates(Map<String, dynamic> d) {
    final covered = _certs.where((c) => c['status'] != 'Cancelled').length;
    return ((d['lines'] as List).length - covered).clamp(0, 999);
  }

  Future<void> _createAllCertificates() async {
    final made = await runAction(context, () => api.post('/api/sales/certificates/for-delivery/${widget.id}', {}));
    if (made is! List || made.isEmpty || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${made.length} certificado(s) criado(s) com a especificação do último emitido. Abra cada um e preencha o "Encontrado".')),
    );
  }

  /// Shipped by someone without the right to emit the NF: the shipment event says "NF pendente".
  bool get _invoicePending =>
      _d?['invoiceNumber'] == null && ((_d?['history'] as List?) ?? const []).any((h) => h['action'] == 'shipped' && '${h['note']}'.contains('NF pendente'));

  Future<void> _emitInvoice() async {
    final r = await runAction(context, () => api.post('$base/emit-invoice', {}), success: 'NF emitida');
    if (r != null && r['reference'] != null && mounted) {
      setState(() => _d = r);
      unawaited(_load()); // the NF section and the link to the NF come from a separate lookup
    }
  }

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
    if (r != null && r['reference'] != null && mounted) {
      setState(() => _d = r);
      unawaited(_load());
    }
  }

  /// Cancelling a shipped delivery has effects beyond this page: the dialog lists them before asking for the reason.
  Future<void> _cancel() async {
    final d = _d!;
    final shipped = d['status'] == 'Shipped';
    final certs = _certs.where((c) => c['status'] != 'Cancelled').map((c) => '${c['reference']}').toList();
    // The server refuses to undo a delivery whose NF is authorized: the NF is cancelled first (from Fiscal), and that undoes the delivery too.
    if (_nf != null) {
      return showError(
        context,
        'A NF ${_nf!['number']} está autorizada para esta entrega. Cancele a NF em Fiscal (dentro do prazo): isso também desfaz a entrega e devolve o estoque.',
      );
    }
    final r = await showDialog<({String reason, bool option})>(
      context: context,
      builder: (_) => ReasonDialog(
        title: shipped ? 'Cancelar a expedição de ${d['reference']}?' : 'Cancelar ${d['reference']}?',
        confirmLabel: 'Cancelar entrega',
        details: [
          if (shipped) 'A baixa de estoque é estornada, o produto volta ao saldo e o pedido reabre o saldo da entrega.' else 'Nada saiu do estoque ainda: só a programação é cancelada.',
          if (certs.isNotEmpty) 'Os certificados ligados a esta entrega continuam emitidos: ${certs.join(', ')}. Cancele-os à parte se não valem mais.',
        ],
        reasonLabel: shipped ? 'Motivo (fica no histórico do pedido)' : 'Motivo',
      ),
    );
    if (r == null || !mounted) return;
    final res = await runAction(context, () => api.post('$base/cancel', {'reason': r.reason}), success: 'Entrega cancelada');
    if (res is Map<String, dynamic> && mounted) setState(() => _d = res);
  }

  Widget _nextStep(Map<String, dynamic> d) => switch (d['status']) {
    'Planned' => NextStepCard(
      title: isLate(d['plannedDate']) ? 'Atrasada · era para ${fmtDay(d['plannedDate'])}' : 'Programada para ${fmtDay(d['plannedDate'])}',
      message: 'Ao expedir, o produto acabado sai do estoque de expedição usando a reserva do pedido.${_certified == false ? ' Atenção: o pedido ainda não tem certificado de qualidade emitido nem dispensado.' : ''}',
      tone: _certified == false || isLate(d['plannedDate']) ? Tone.warning : Tone.info,
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
        TextButton.icon(key: const ValueKey('delivery-print-nf-card'), onPressed: _printNf, icon: const Icon(Icons.print_outlined), label: const Text('Imprimir NF')),
        if (_invoicePending && s.canEmitInvoice)
          OutlinedButton.icon(key: const ValueKey('delivery-emit-invoice'), onPressed: _emitInvoice, icon: const Icon(Icons.receipt_long_outlined), label: const Text('Emitir NF')),
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
      actions: [TextButton.icon(key: const ValueKey('delivery-print-nf-card'), onPressed: _printNf, icon: const Icon(Icons.print_outlined), label: const Text('Imprimir NF'))],
    ),
    _ => NextStepCard(title: 'Cancelada', message: _cancelNote(d) ?? 'Sem motivo registrado.', tone: Tone.danger),
  };

  /// The reason typed when the delivery was cancelled: the newest "cancelled" entry of the history (newest first).
  String? _cancelNote(Map<String, dynamic> d) {
    for (final h in ((d['history'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      if (h['action'] == 'cancelled' && '${h['note'] ?? ''}'.trim().isNotEmpty) return '${h['note']}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final canCancel = s.canShip && ['Planned', 'Shipped'].contains(d?['status']);
    final danger = Theme.of(context).colorScheme.error;
    final hasNf = d != null && ['Shipped', 'Delivered'].contains(d['status']);
    return RecordShortcuts(
      onRefresh: _refresh,
      onPrint: hasNf ? () => unawaited(_printNf()) : null,
      child: Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'Entrega' : '${d['reference']} · ${d['customerName']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (d != null) RefreshButton(onPressed: _refresh),
          if (d != null)
            RelatedMenu(
              links: [
                RelatedLink(Icons.business_outlined, 'Cliente: ${d['customerName']}', () => openCustomer(context, s, d['customerId'] as int)),
                RelatedLink(Icons.receipt_long_outlined, 'Pedido de venda ${d['orderReference'] ?? ''}', () => openSalesOrder(context, s, d['orderId'] as int)),
                if (_nf != null) RelatedLink(Icons.description_outlined, 'Nota fiscal ${d['invoiceNumber'] ?? ''}', () => openFiscalDocument(context, s, _nf!['id'] as int)),
              ],
            ),
          if (d != null && ['Shipped', 'Delivered'].contains(d['status']))
            IconButton(key: const ValueKey('delivery-print-nf'), tooltip: 'Imprimir NF', icon: const Icon(Icons.print_outlined), onPressed: _printNf),
          if (canCancel)
            PopupMenuButton<VoidCallback>(
              key: const ValueKey('delivery-menu'),
              onSelected: (f) => f(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _cancel,
                  child: ListTile(leading: const Icon(Icons.block), iconColor: danger, textColor: danger, title: const Text('Cancelar entrega')),
                ),
              ],
            ),
        ],
      ),
      body: _error != null && d == null
          ? LoadError(message: _error!, onRetry: _load)
          : d == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: () => _load(report: true), child: _body(d)),
      ),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final (step, failed) = deliveryPath(d['status']);
    return SideBySide(
      main: [
        _header(d),
        gap,
        StagePath(
          steps: flowSteps,
          current: step,
          failedLabel: failed,
          // Everything before the shipment lives on the order; the certificates of this delivery open directly.
          onStep: (i) => i == 6
              ? stepLink(context, 'Abrir qual certificado?', [
                  for (final c in _certs.where((c) => c['status'] != 'Cancelled'))
                    (label: '${c['reference']} · ${c['description']}', open: () => openCertificate(context, s, c['id'] as int).then((_) => _load())),
                ])
              : i <= 5
              ? () => unawaited(openSalesOrder(context, s, d['orderId'] as int).then((_) => _load()))
              : null,
        ),
        gap,
        _nextStep(d),
        gap,
        _itemsSection(d),
        gap,
        _certsSection(d),
        if (_nf != null) ...[
          gap,
          _nfSection(),
        ],
        gap,
        _detailsSection(d),
      ],
      side: [
        Section(
          title: 'Histórico',
          child: TimelineView(entries: timeline(d['history'] as List)),
        ),
      ],
    );
  }

  Widget _header(Map<String, dynamic> d) {
    return RecordHeader(
      icon: Icons.local_shipping_outlined,
      kind: 'Entrega',
      title: '${d['reference']}',
      badge: StatusBadge(deliveryStatuses[d['status']] ?? '${d['status']}', tone: deliveryTone(d['status'])),
      // The value of the goods on this delivery (the invoiced value once the NF exists); the header, like the order's, says how much is at stake.
      amount: d['invoicedValue'] != null ? fmtMoney(d['invoicedValue']) : (d['valueExIpi'] == null ? null : fmtMoney(d['valueExIpi'])),
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
    );
  }

  Widget _itemsSection(Map<String, dynamic> d) {
    return Section(
      title: 'Itens',
      actions: [
        TextButton.icon(
          onPressed: () => openSalesOrder(context, s, d['orderId'] as int).then((_) => _load()),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Ver pedido'),
        ),
        if (d['stockDocumentId'] != null)
          TextButton.icon(
            onPressed: () => openStockDocument(context, s, d['stockDocumentId'] as int),
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
    );
  }

  Widget _certsSection(Map<String, dynamic> d) {
    return Section(
      title: 'Certificados de qualidade (${_certs.length})',
      actions: [
        if (s.canCertificate && ['Planned', 'Shipped'].contains(d['status']) && _missingCertificates(d) > 0)
          FilledButton.tonalIcon(
            key: const ValueKey('delivery-all-certificates'),
            onPressed: _createAllCertificates,
            icon: const Icon(Icons.playlist_add),
            label: Text(_missingCertificates(d) == 1 ? 'Gerar certificado do item' : 'Gerar ${_missingCertificates(d)} certificados'),
          ),
        if (s.canCertificate && ['Planned', 'Shipped'].contains(d['status']))
          OutlinedButton.icon(
            key: const ValueKey('delivery-new-certificate'),
            onPressed: () async {
              final order = await api.get('/api/sales/orders/${d['orderId']}') as Map<String, dynamic>;
              if (mounted && await newCertificate(context, s, order, deliveryId: d['id'] as int)) unawaited(_load());
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
    );
  }

  Widget _nfSection() {
    return Section(
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
      );
  }

  Widget _detailsSection(Map<String, dynamic> d) {
    return Section(
      title: 'Detalhes',
      child: InfoGrid([
        ('Local de entrega', fmt(d['addressText'])),
        ('Observações', fmt(d['notes'])),
        ('Criada', '${fmt(d['createdBy'])} · ${fmtDate(d['createdAt'])}'),
        ('Expedida', d['shippedAt'] == null ? '' : '${fmt(d['shippedBy'])} · ${fmtDate(d['shippedAt'])}'),
      ]),
    );
  }
}
