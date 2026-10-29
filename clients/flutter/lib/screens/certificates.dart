import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../reports/certificate_doc.dart';
import '../reports/print_docs.dart' show PrintButton;
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/pipeline.dart';
import '../widgets/record_list.dart';
import 'sales_common.dart';

Tone certificateTone(Object? s) => switch (s) {
  'Draft' => Tone.warning,
  'Issued' => Tone.success,
  _ => Tone.danger,
};

Future<Map<String, dynamic>?> openCertificate(BuildContext context, Session session, int id) =>
    Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => CertificateScreen(session: session, id: id)));

/// Creates a draft certificate for an order line (prefilled by the server) and opens the editor on it.
/// Returns true when a certificate was created.
Future<bool> newCertificate(BuildContext context, Session session, Map<String, dynamic> order, {int? deliveryId}) async {
  final api = session.api;
  final lines = (order['lines'] as List).cast<Map<String, dynamic>>();
  var lineId = lines.length == 1 ? lines.first['id'] as int : null;
  if (lineId == null) {
    lineId = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Certificado de qual item?'),
        children: [
          for (final l in lines)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, l['id'] as int),
              child: Text('${l['sequence']} · ${l['productCode']} · ${l['description']}'),
            ),
        ],
      ),
    );
    if (lineId == null || !context.mounted) return false;
  }
  final c = await runAction(context, () => api.post('/api/sales/certificates', {'orderId': order['id'], 'orderLineId': lineId, 'deliveryId': deliveryId}));
  if (c is! Map<String, dynamic> || !context.mounted) return false;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CertificateEditorScreen(session: session, certificate: c)));
  return true;
}

class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({super.key, required this.session});

  final Session session;

  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _status;
  String? _company;

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: widget.session.api,
    path: '/api/sales/certificates',
    query: {'status': _status, 'company': _company},
    searchHint: 'Certificado, pedido, cliente, pedido do cliente ou NF',
    filters: [
      ChoiceFilter(label: 'Situação', value: _status, choices: certificateStatuses, onChanged: (v) => setState(() => _status = v)),
      ChoiceFilter(label: 'Empresa', value: _company, choices: const {'EBT': 'EBT', 'BST': 'BST'}, onChanged: (v) => setState(() => _company = v)),
    ],
    columns: [
      col('Certificado', 'reference'),
      col('Empresa', 'company'),
      dateCol('Data', 'issueDate'),
      labelCol('Situação', 'status', certificateStatuses),
      col('Pedido', 'orderReference'),
      col('Pedido do cliente', 'customerPo'),
      col('Cliente', 'customerName'),
      col('Produto', 'description'),
      ColumnSpec('Qtd.', (e) => '${fmt(e['quantity'])} ${e['unit']}', numeric: true),
      col('NF', 'invoiceNumber'),
    ],
    onTap: (e) async {
      await openCertificate(context, widget.session, e['id'] as int);
      _list.currentState?.reload();
    },
  );
}

class CertificateScreen extends StatefulWidget {
  const CertificateScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<CertificateScreen> createState() => _CertificateScreenState();
}

class _CertificateScreenState extends State<CertificateScreen> {
  Map<String, dynamic>? _c;
  String? _error;

  ApiClient get api => widget.session.api;
  Session get s => widget.session;
  String get base => '/api/sales/certificates/${widget.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await api.get(base) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _c = c;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _edit() async {
    final r = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => CertificateEditorScreen(session: s, certificate: _c!),
      ),
    );
    if (r != null) setState(() => _c = r);
  }

  Future<void> _issue() async {
    final ok = await confirmStep(
      context,
      title: 'Emitir certificado ${_c!['reference']}?',
      message: 'Depois de emitido, os dados não podem mais ser editados.',
      confirmLabel: 'Emitir',
      icon: Icons.verified_outlined,
    );
    if (!ok || !mounted) return;
    final r = await runAction(context, () => api.post('$base/issue', {}), success: 'Certificado emitido');
    if (r is Map<String, dynamic>) setState(() => _c = r);
  }

  Future<void> _link() async {
    final c = _c!;
    final order = await api.get('/api/sales/orders/${c['orderId']}') as Map<String, dynamic>;
    final deliveries = (order['deliveries'] as List).cast<Map<String, dynamic>>().where((d) => d['status'] != 'Cancelled').toList();
    if (!mounted) return;
    if (deliveries.isEmpty) return showError(context, 'O pedido ainda não tem entrega programada');
    final id = await showDialog<int>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Vincular a qual entrega?'),
        children: [
          for (final x in deliveries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, x['id'] as int),
              child: Text('${x['reference']} · ${fmtDay(x['plannedDate'])}${x['invoiceNumber'] == null ? '' : ' · NF ${x['invoiceNumber']}'}'),
            ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    final r = await runAction(context, () => api.post('$base/link-delivery', {'deliveryId': id}), success: 'Certificado vinculado à entrega');
    if (r is Map<String, dynamic>) setState(() => _c = r);
  }

  Future<void> _cancel() async {
    final reason = await promptText(context, title: 'Cancelar ${_c!['reference']}', label: 'Motivo', required: true, confirmLabel: 'Cancelar certificado');
    if (reason == null || !mounted) return;
    final r = await runAction(context, () => api.post('$base/cancel', {'reason': reason}), success: 'Certificado cancelado');
    if (r is Map<String, dynamic>) setState(() => _c = r);
  }

  Future<void> _delete() async {
    final ok = await confirmStep(
      context,
      title: 'Excluir rascunho ${_c!['reference']}?',
      message: 'O número fica disponível para o próximo certificado só se este for o último emitido.',
      confirmLabel: 'Excluir',
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    try {
      await api.delete(base);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e is ApiException ? describeError(e) : e);
    }
  }

  Widget _nextStep(Map<String, dynamic> c) => switch (c['status']) {
    'Draft' => NextStepCard(
      title: 'Rascunho',
      message: 'Preencha composição química, dimensional e ensaios com os valores encontrados e emita o certificado.',
      tone: Tone.warning,
      actions: [
        if (s.canCertificate) ...[
          OutlinedButton.icon(key: const ValueKey('certificate-edit'), onPressed: _edit, icon: const Icon(Icons.edit_outlined), label: const Text('Preencher')),
          FilledButton.icon(key: const ValueKey('certificate-issue'), onPressed: _issue, icon: const Icon(Icons.verified_outlined), label: const Text('Emitir')),
        ],
      ],
    ),
    'Issued' => NextStepCard(
      title: 'Emitido',
      message: c['deliveryId'] == null
          ? 'Vincule o certificado à entrega para trazer o número da NF e enviá-lo junto com a mercadoria.'
          : 'Vinculado a ${c['deliveryReference']}. Imprima e envie com a mercadoria.',
      tone: Tone.success,
      actions: [
        if (s.canCertificate && c['deliveryId'] == null)
          FilledButton.icon(key: const ValueKey('certificate-link'), onPressed: _link, icon: const Icon(Icons.local_shipping_outlined), label: const Text('Vincular à entrega')),
      ],
    ),
    _ => NextStepCard(title: 'Cancelado', message: '${c['cancelReason'] ?? ''}', tone: Tone.danger),
  };

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final menu = <PopupMenuEntry<VoidCallback>>[
      if (s.canCertificate && c?['status'] == 'Draft')
        PopupMenuItem(
          value: _edit,
          child: const ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar')),
        ),
      if (s.canCertificate && c?['status'] == 'Issued' && c?['deliveryId'] != null)
        PopupMenuItem(
          value: _link,
          child: const ListTile(leading: Icon(Icons.local_shipping_outlined), title: Text('Trocar entrega')),
        ),
      if (s.canCertificate && c?['status'] == 'Draft')
        PopupMenuItem(
          value: _delete,
          child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Excluir rascunho')),
        ),
      if (s.canCertificate && c != null && c['status'] != 'Cancelled')
        PopupMenuItem(
          value: _cancel,
          child: const ListTile(leading: Icon(Icons.block), title: Text('Cancelar certificado')),
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Certificado' : 'Certificado ${c['reference']} · ${c['customerName']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (c != null) PrintButton(key: const ValueKey('certificate-print'), name: 'Certificado de qualidade ${c['reference']}', builder: () => buildCertificatePdf(c)),
          if (menu.isNotEmpty) PopupMenuButton<VoidCallback>(onSelected: (f) => f(), itemBuilder: (_) => menu),
        ],
      ),
      body: _error != null && c == null
          ? Center(child: Text(_error!))
          : c == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(c)),
    );
  }

  Widget _measureTable(String title, List<Map<String, dynamic>> rows, List<String> headers) => Section(
    title: title,
    child: SimpleTable(
      columns: [
        ColumnSpec(headers[0], (e) => fmt(e['name'])),
        ColumnSpec(headers[1], (e) => fmt(e['specified'])),
        ColumnSpec(headers[2], (e) => fmt(e['found'])),
      ],
      rows: rows,
    ),
  );

  Widget _body(Map<String, dynamic> c) {
    final measures = (c['measures'] as List).cast<Map<String, dynamic>>();
    List<Map<String, dynamic>> of(String kind) => measures.where((m) => m['kind'] == kind).toList();
    final nf = c['effectiveInvoiceNumber'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        RecordHeader(
          icon: Icons.verified_outlined,
          kind: 'Certificado de qualidade · ${c['company']}',
          title: '${c['reference']}',
          badge: StatusBadge(certificateStatuses[c['status']] ?? '${c['status']}', tone: certificateTone(c['status'])),
          fields: [
            ('Cliente', '${c['customerName']}'),
            ('Pedido', '${c['orderReference']}'),
            ('Pedido do cliente', fmt(c['customerPo'])),
            ('Data', fmtDay(c['issueDate'])),
            ('NF', fmt(nf)),
            ('Quantidade', '${fmt(c['quantity'])} ${c['unit']}'),
            ('Entrega', fmt(c['deliveryReference'])),
          ],
        ),
        gap,
        _nextStep(c),
        gap,
        Section(
          title: 'Dados do produto',
          actions: [
            TextButton.icon(
              onPressed: () => openSalesOrder(context, s, c['orderId'] as int).then((_) => _load()),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Ver pedido'),
            ),
            if (c['deliveryId'] != null)
              TextButton.icon(
                onPressed: () => openDelivery(context, s, c['deliveryId'] as int).then((_) => _load()),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Ver entrega'),
              ),
          ],
          child: InfoGrid([
            ('Nº do produto', fmt(c['productCode'])),
            ('Descrição', fmt(c['description'])),
            ('Código do cliente', fmt(c['customerPartNumber'])),
            ('Descrição do cliente', fmt(c['customerPartDescription'])),
            ('Lote MP', fmt(c['rawMaterialLot'])),
            ('Dureza', fmt(c['hardness'])),
            ('Acabamento superficial', fmt(c['finish'])),
            ('Observações', fmt(c['notes'])),
            ('Aprovação', fmt(c['approvedBy'])),
            ('Criado', '${fmt(c['createdBy'])} · ${fmtDate(c['createdAt'])}'),
            ('Emitido', c['issuedAt'] == null ? '' : '${fmt(c['issuedBy'])} · ${fmtDate(c['issuedAt'])}'),
          ]),
        ),
        gap,
        _measureTable('Composição química (%)', of('Chemical'), const ['Elemento', 'Especificado', 'Encontrado']),
        gap,
        _measureTable('Dimensional (mm)', of('Dimensional'), const ['Medida', 'Especificado', 'Encontrado']),
        gap,
        _measureTable('Ensaios mecânicos', of('Mechanical'), const ['Limite', 'Especificado', 'Encontrado']),
      ],
    );
  }
}

class CertificateEditorScreen extends StatefulWidget {
  const CertificateEditorScreen({super.key, required this.session, required this.certificate});

  final Session session;
  final Map<String, dynamic> certificate;

  @override
  State<CertificateEditorScreen> createState() => _CertificateEditorScreenState();
}

class _CertificateEditorScreenState extends State<CertificateEditorScreen> {
  late final Map<String, dynamic> c = widget.certificate;
  final _fields = <String, TextEditingController>{};
  final _spec = <TextEditingController>[];
  final _found = <TextEditingController>[];
  late final List<Map<String, dynamic>> _measures = (c['measures'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> _deliveries = const [];
  int? _deliveryId;
  String? _error;
  bool _busy = false;

  ApiClient get api => widget.session.api;

  @override
  void initState() {
    super.initState();
    String text(String key) => c[key] == null ? '' : fmt(c[key]);
    _fields.addAll({
      'issueDate': TextEditingController(text: fmtDay(c['issueDate'])),
      'customerPo': TextEditingController(text: text('customerPo')),
      'invoiceNumber': TextEditingController(text: text('invoiceNumber')),
      'quantity': TextEditingController(text: text('quantity')),
      'unit': TextEditingController(text: text('unit')),
      'description': TextEditingController(text: text('description')),
      'customerPartNumber': TextEditingController(text: text('customerPartNumber')),
      'customerPartDescription': TextEditingController(text: text('customerPartDescription')),
      'rawMaterialLot': TextEditingController(text: text('rawMaterialLot')),
      'hardness': TextEditingController(text: text('hardness')),
      'finish': TextEditingController(text: text('finish')),
      'notes': TextEditingController(text: text('notes')),
      'approvedBy': TextEditingController(text: text('approvedBy')),
    });
    for (final m in _measures) {
      _spec.add(TextEditingController(text: text2(m['specified'])));
      _found.add(TextEditingController(text: text2(m['found'])));
    }
    _deliveryId = c['deliveryId'] as int?;
    _loadDeliveries();
  }

  String text2(Object? v) => v == null ? '' : '$v';

  Future<void> _loadDeliveries() async {
    try {
      final o = await api.get('/api/sales/orders/${c['orderId']}') as Map<String, dynamic>;
      if (mounted) setState(() => _deliveries = (o['deliveries'] as List).cast<Map<String, dynamic>>().where((d) => d['status'] != 'Cancelled').toList());
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final x in [..._fields.values, ..._spec, ..._found]) {
      x.dispose();
    }
    super.dispose();
  }

  String? _v(String key) {
    final t = _fields[key]!.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    final date = parseDate(_fields['issueDate']!.text);
    final qty = parseDecimal(_fields['quantity']!.text.trim());
    if (date == null) return setState(() => _error = 'Data inválida');
    if (qty == null || qty <= 0) return setState(() => _error = 'Quantidade deve ser maior que zero');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = {
        'orderId': c['orderId'],
        'deliveryId': _deliveryId,
        'issueDate': date,
        'quantity': qty,
        'unit': _v('unit'),
        'customerPo': _v('customerPo'),
        'invoiceNumber': _v('invoiceNumber'),
        'description': _v('description'),
        'customerPartNumber': _v('customerPartNumber'),
        'customerPartDescription': _v('customerPartDescription'),
        'rawMaterialLot': _v('rawMaterialLot'),
        'hardness': _v('hardness'),
        'finish': _v('finish'),
        'notes': _v('notes'),
        'approvedBy': _v('approvedBy'),
        'measures': [
          for (var i = 0; i < _measures.length; i++)
            {'kind': _measures[i]['kind'], 'name': _measures[i]['name'], 'specified': _spec[i].text.trim(), 'found': _found[i].text.trim()},
        ],
      };
      final r = await api.put('/api/sales/certificates/${c['id']}', body);
      if (mounted) Navigator.of(context).pop(r as Map<String, dynamic>);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is ApiException ? describeError(e) : '$e';
        });
      }
    }
  }

  Widget _text(String key, String label, {double width = 240, bool number = false, int lines = 1, String? hint}) => SizedBox(
    width: width,
    child: TextField(
      key: ValueKey('cert-$key'),
      controller: _fields[key],
      maxLines: lines,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
      decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true),
    ),
  );

  Widget _table(String title, String kind, List<String> headers) {
    final idx = [for (var i = 0; i < _measures.length; i++) if (_measures[i]['kind'] == kind) i];
    return Section(
      title: title,
      child: Column(
        children: [
          Row(
            children: [
              for (final (n, h) in headers.indexed)
                Expanded(
                  flex: n == 0 ? 2 : 3,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(h, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
          for (final i in idx)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text('${_measures[i]['name']}')),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextField(
                        key: ValueKey('spec-$kind-${_measures[i]['name']}'),
                        controller: _spec[i],
                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: '-'),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      key: ValueKey('found-$kind-${_measures[i]['name']}'),
                      controller: _found[i],
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: '-'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Certificado ${c['reference']} · ${c['orderReference']}'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton.icon(key: const ValueKey('cert-save'), onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('Salvar')),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Section(
          title: 'Dados do certificado',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _text('issueDate', 'Data *', width: 150, hint: 'dd/mm/aaaa'),
              _text('customerPo', 'Nº do pedido do cliente', width: 200),
              _text('invoiceNumber', 'NF', width: 140, hint: 'Vazio = NF da entrega'),
              _text('quantity', 'Quantidade *', width: 140, number: true),
              _text('unit', 'Unidade', width: 90),
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<int?>(
                  key: const ValueKey('cert-delivery'),
                  initialValue: _deliveries.any((d) => d['id'] == _deliveryId) ? _deliveryId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Entrega', border: OutlineInputBorder(), isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Sem entrega')),
                    for (final d in _deliveries)
                      DropdownMenuItem<int?>(value: d['id'] as int, child: Text('${d['reference']} · ${fmtDay(d['plannedDate'])}${d['invoiceNumber'] == null ? '' : ' · NF ${d['invoiceNumber']}'}')),
                  ],
                  onChanged: (v) => setState(() => _deliveryId = v),
                ),
              ),
            ],
          ),
        ),
        gap,
        Section(
          title: 'Produto',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _text('description', 'Descrição *', width: 360),
              _text('customerPartNumber', 'Código do cliente', width: 200),
              _text('customerPartDescription', 'Descrição do cliente', width: 300),
              _text('rawMaterialLot', 'Lote MP', width: 180),
              _text('hardness', 'Dureza', width: 160, hint: 'ex.: 66 HRB'),
              _text('finish', 'Acabamento superficial', width: 420),
              _text('approvedBy', 'Aprovação / visto (nome)', width: 240),
              _text('notes', 'Observações', width: 700, lines: 3),
            ],
          ),
        ),
        gap,
        _table('Composição química (%)', 'Chemical', const ['Elemento', 'Especificado', 'Encontrado']),
        gap,
        _table('Dimensional (mm)', 'Dimensional', const ['Medida', 'Especificado', 'Encontrado']),
        gap,
        _table('Ensaios mecânicos', 'Mechanical', const ['Limite', 'Especificado', 'Encontrado']),
      ],
    ),
  );
}
