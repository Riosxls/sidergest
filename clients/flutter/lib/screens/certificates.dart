import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../reports/certificate_doc.dart';
import '../reports/print_docs.dart' show PrintButton;
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/actions.dart';
import '../widgets/discard_guard.dart';
import '../widgets/entity_form.dart';
import '../widgets/load_error.dart';
import '../widgets/pipeline.dart';
import '../widgets/print_panel.dart' show printPdf;
import '../widgets/record_list.dart';
import '../widgets/record_nav.dart';
import '../widgets/record_shortcuts.dart';
import '../widgets/record_skeleton.dart';
import '../widgets/responsive.dart';
import 'customers.dart';
import 'sales_common.dart';
import 'sales_orders.dart' show ReasonDialog;

Tone certificateTone(Object? s) => switch (s) {
  'Draft' => Tone.warning,
  'Issued' => Tone.success,
  _ => Tone.danger,
};

Future<Map<String, dynamic>?> openCertificate(BuildContext context, Session session, int id) =>
    pushRecord<Map<String, dynamic>>(context, 'certificate', id, (_) => CertificateScreen(session: session, id: id));

/// Names of the rows whose "Encontrado" is blank. The server (`CertificateService.IssueAsync`) refuses a certificate when any row is blank
/// (whitespace only); a typed "-" is a value for it, so it is one here too.
List<String> emptyFoundRows(Iterable<String> names, Iterable<String> found) => [
  for (final (i, f) in found.indexed)
    if (f.trim().isEmpty) names.elementAt(i),
];

String foundRowsMessage(List<String> empty) =>
    'Preencha o "Encontrado" de todas as linhas antes de emitir. Faltam: ${empty.join(', ')}. Se uma linha não se aplica, remova-a (ou digite "-").';

/// Creates a draft certificate for an order line (prefilled by the server) and opens the editor on it.
/// Returns true when a certificate was created.
///
/// For a delivery pass [lineIds] (the order lines it carries): the picker lists only those, and [coveredLineIds] marks the ones that already have a
/// certificate. With one candidate line the picker is skipped.
Future<bool> newCertificate(
  BuildContext context,
  Session session,
  Map<String, dynamic> order, {
  int? deliveryId,
  Set<int>? lineIds,
  Set<int> coveredLineIds = const {},
}) async {
  final api = session.api;
  final lines = [for (final l in (order['lines'] as List).cast<Map<String, dynamic>>()) if (lineIds == null || lineIds.contains(l['id'])) l];
  if (lines.isEmpty) {
    showError(context, 'Esta entrega não tem itens para certificar.');
    return false;
  }
  var lineId = lines.length == 1 ? lines.first['id'] as int : null;
  if (lineId == null) {
    lineId = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Certificado de qual item?'),
        children: [
          for (final l in lines)
            SimpleDialogOption(
              key: ValueKey('cert-pick-${l['id']}'),
              onPressed: () => Navigator.pop(c, l['id'] as int),
              child: Text('${l['sequence']} · ${l['productCode']} · ${l['description']}${coveredLineIds.contains(l['id']) ? '  (já tem certificado)' : ''}'),
            ),
        ],
      ),
    );
    if (lineId == null || !context.mounted) return false;
  }
  final c = await runAction(context, () => api.post('/api/sales/certificates', {'orderId': order['id'], 'orderLineId': lineId, 'deliveryId': deliveryId}));
  if (c is! Map<String, dynamic> || !context.mounted) return false;
  var persisted = false;
  final saved = await Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      builder: (_) => CertificateEditorScreen(session: session, certificate: c, onPersisted: () => persisted = true),
    ),
  );
  // A draft whose edits reached the server (the issue step failed after the save) is kept: it holds what the user typed.
  if (saved != null || persisted) return true;
  // Backed out without saving: the draft only exists because the server numbered it, so it goes away (and frees the number when it is the last).
  try {
    await api.delete('/api/sales/certificates/${c['id']}');
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rascunho ${c['reference']} descartado: nada foi salvo')));
    return false;
  } catch (e) {
    debugPrint('certificates: The draft stays and can be deleted from its page: $e');
    return true;
  }
}

/// List of quality certificates with filters.
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
      ActionChip(
        key: const ValueKey('certificate-templates'),
        avatar: const Icon(Icons.fact_check_outlined, size: 18),
        label: const Text('Modelos de especificação'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CertificateTemplatesScreen(session: widget.session))),
      ),
    ],
    columns: [
      // Six columns: the company is in the filter and in the number, the customer's PO and the NF ride with the order.
      col('Certificado', 'reference'),
      labelCol('Situação', 'status', certificateStatuses),
      col('Cliente', 'customerName'),
      ColumnSpec('Produto · qtd.', (e) => '${fmt(e['description'])} · ${fmt(e['quantity'])} ${e['unit']}'),
      ColumnSpec(
        'Pedido · NF',
        (e) => [e['orderReference'], if (fmt(e['invoiceNumber']).isNotEmpty) 'NF ${e['invoiceNumber']}'].whereType<Object>().map(fmt).where((t) => t.isNotEmpty).join(' · '),
      ),
      dateCol('Data', 'issueDate'),
    ],
    onTap: (e) async {
      await openCertificate(context, widget.session, e['id'] as int);
      unawaited(_list.currentState?.reload());
    },
  );
}

/// View of one certificate with issue, cancel and print actions.
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

  /// Reloads the certificate. [report]: the user asked (F5, refresh button), so a failure is said even when the old data stays on screen.
  Future<void> _load({bool report = false}) async {
    try {
      final c = await api.get(base) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _c = c;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (_c != null) {
        if (report) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao atualizar: ${friendlyError(e)}')));
        return;
      }
      setState(() => _error = friendlyError(e));
    }
  }

  void _refresh() => unawaited(_load(report: true));

  Future<void> _edit() async {
    final r = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => CertificateEditorScreen(session: s, certificate: _c!),
      ),
    );
    if (r != null && mounted) setState(() => _c = r);
  }

  Future<void> _issue() async {
    final measures = (_c!['measures'] as List).cast<Map<String, dynamic>>();
    final empty = emptyFoundRows(measures.map((m) => '${m['name']}'), measures.map((m) => '${m['found'] ?? ''}'));
    if (measures.isEmpty || empty.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          icon: const Icon(Icons.edit_note),
          title: const Text('Faltam os valores encontrados'),
          content: Text(measures.isEmpty ? 'O certificado não tem linhas. Adicione as linhas de química, dimensional ou ensaios e preencha o "Encontrado".' : foundRowsMessage(empty)),
          actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Preencher'))],
        ),
      );
      if (mounted) await _edit();
      return;
    }
    final ok = await confirmStep(
      context,
      title: 'Emitir certificado ${_c!['reference']}?',
      message: 'Depois de emitido, os dados não podem mais ser editados.',
      confirmLabel: 'Emitir',
      icon: Icons.verified_outlined,
    );
    if (!ok || !mounted) return;
    final r = await runAction(context, () => api.post('$base/issue', {}), success: 'Certificado emitido');
    if (r is Map<String, dynamic> && mounted) setState(() => _c = r);
  }

  Future<void> _link() async {
    final c = _c!;
    final Map<String, dynamic> order;
    try {
      order = await api.get('/api/sales/orders/${c['orderId']}') as Map<String, dynamic>;
    } catch (e) {
      // A menu callback has nobody above it to catch this: say what happened instead of failing silently.
      if (mounted) showError(context, e);
      return;
    }
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
    if (r is Map<String, dynamic> && mounted) setState(() => _c = r);
  }

  Future<void> _cancel() async {
    final c = _c!;
    final answer = await showDialog<({String reason, bool option})>(
      context: context,
      builder: (_) => ReasonDialog(
        title: 'Cancelar ${c['reference']}?',
        confirmLabel: 'Cancelar certificado',
        details: [
          if (c['status'] == 'Issued') 'Um certificado cancelado deixa de valer: o pedido volta a exigir um certificado emitido (ou a dispensa) antes de expedir.',
          if (c['deliveryReference'] != null) 'Ele sai da entrega ${c['deliveryReference']}.',
        ],
      ),
    );
    if (answer == null || !mounted) return;
    final r = await runAction(context, () => api.post('$base/cancel', {'reason': answer.reason}), success: 'Certificado cancelado');
    if (r is Map<String, dynamic> && mounted) setState(() => _c = r);
  }

  Future<void> _delete() async {
    final ok = await confirmStep(
      context,
      title: 'Excluir rascunho ${_c!['reference']}?',
      message: 'O número fica disponível para o próximo certificado só se este for o último emitido.',
      confirmLabel: 'Excluir',
      cancelLabel: 'Voltar',
      danger: true,
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
          if (s.canIssueCertificate)
            FilledButton.icon(
            key: const ValueKey('certificate-issue'),
            onPressed: _issue,
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Emitir'),
          ),
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
          FilledButton.icon(
            key: const ValueKey('certificate-link'),
            onPressed: _link,
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('Vincular à entrega'),
          ),
      ],
    ),
    _ => NextStepCard(title: 'Cancelado', message: '${c['cancelReason'] ?? ''}', tone: Tone.danger),
  };

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final danger = Theme.of(context).colorScheme.error;
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
      if (s.canIssueCertificate && c?['status'] == 'Draft')
        PopupMenuItem(
          value: _delete,
          child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Excluir rascunho')),
        ),
      // A draft is deleted, not cancelled: "Excluir rascunho" above is its only way out.
      if (s.canIssueCertificate && c != null && c['status'] == 'Issued')
        PopupMenuItem(
          value: _cancel,
          child: ListTile(leading: const Icon(Icons.block), iconColor: danger, textColor: danger, title: const Text('Cancelar certificado')),
        ),
    ];
    return RecordShortcuts(
      onRefresh: _refresh,
      onPrint: c == null ? null : () => unawaited(printPdf(context, 'Certificado de qualidade ${c['reference']}', () => buildCertificatePdf(c))),
      child: Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Certificado' : 'Certificado ${c['reference']} · ${c['customerName']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (c != null) RefreshButton(onPressed: _refresh),
          if (c != null) RelatedMenu(links: [RelatedLink(Icons.business_outlined, 'Cliente: ${c['customerName']}', () => openCustomer(context, s, c['customerId'] as int))]),
          if (c != null)
            PrintButton(key: const ValueKey('certificate-print'), name: 'Certificado de qualidade ${c['reference']}', builder: () => buildCertificatePdf(c)),
          if (menu.isNotEmpty) PopupMenuButton<VoidCallback>(onSelected: (f) => f(), itemBuilder: (_) => menu),
        ],
      ),
      body: _error != null && c == null
          ? LoadError(message: _error!, onRetry: _load)
          : c == null
          ? const RecordSkeleton()
          : RefreshIndicator(onRefresh: () => _load(report: true), child: _body(c)),
      ),
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

/// Editor for a draft certificate: header, specification table, found values and observations.
class CertificateEditorScreen extends StatefulWidget {
  const CertificateEditorScreen({super.key, required this.session, required this.certificate, this.onPersisted});

  final Session session;
  final Map<String, dynamic> certificate;

  /// Called once the server has the edits (the save worked), even if the page is left without a result afterwards.
  final VoidCallback? onPersisted;

  @override
  State<CertificateEditorScreen> createState() => _CertificateEditorScreenState();
}

class _CertificateEditorScreenState extends State<CertificateEditorScreen> {
  static const _titles = ['', 'CERTIFICADO DE GARANTIA DA QUALIDADE DO PRODUTO'];
  static const _noteSnippets = [
    ('Certificado de origem', 'Certificado de origem do material nº '),
    ('Material recozido', 'MATERIAL RECOZIDO'),
    ('Alívio de tensão', 'TRATAMENTO ALIVIO DE TENSÃO NO FINAL DO PROCESSO'),
    (
      'Eddy current',
      'PROCESSO DE FECHAMENTO DO TUBO POR INDUÇÃO, DE ALTA FREQUENCIA, MONITORADO PELO EQUIPAMENTO DE "EDDY CURRENT", PARA DETECÇÃO DE FALHAS EM POTENCIAL OCASIONADAS POR CORRENTES PARASITAS.',
    ),
  ];
  late final Map<String, dynamic> c = widget.certificate;
  final _fields = <String, TextEditingController>{};
  final _spec = <TextEditingController>[];
  final _found = <TextEditingController>[];
  late final List<Map<String, dynamic>> _measures = [
    for (final m in (c['measures'] as List).cast<Map<String, dynamic>>()) {...m},
  ];
  late String? _title = c['title'] as String?;
  List<Map<String, dynamic>> _deliveries = const [];
  int? _deliveryId;
  String? _error;
  bool _busy = false;
  bool _bannerOpen = false;
  String _initial = '';

  ApiClient get api => widget.session.api;

  /// Everything the user can edit, to tell whether leaving would lose something.
  String _signature() => [
    for (final e in _fields.entries) '${e.key}=${e.value.text}',
    for (var i = 0; i < _measures.length; i++) '${_measures[i]['kind']}|${_measures[i]['name']}|${_spec[i].text}|${_found[i].text}',
    '$_deliveryId',
    '$_title',
  ].join('\u0001');

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
    _initial = _signature();
    _loadDeliveries();
  }

  String text2(Object? v) => v == null ? '' : '$v';

  Future<void> _loadDeliveries() async {
    try {
      final o = await api.get('/api/sales/orders/${c['orderId']}') as Map<String, dynamic>;
      if (mounted) setState(() => _deliveries = (o['deliveries'] as List).cast<Map<String, dynamic>>().where((d) => d['status'] != 'Cancelled').toList());
    } catch (e) {
      debugPrint('certificates: Optional context; the screen works without it: $e');
      // Optional context; the screen works without it.
    }
  }

  @override
  void dispose() {
    for (final x in [..._fields.values, ..._spec, ..._found]) {
      x.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  String? _v(String key) {
    final t = _fields[key]!.text.trim();
    return t.isEmpty ? null : t;
  }

  final _scroll = ScrollController();

  /// Shows a validation or server message at the top of the page and brings the page back up to it (the save button is in the app bar).
  void _fail(String message) {
    setState(() {
      _busy = false;
      _error = message;
    });
    if (_scroll.hasClients) unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
  }

  /// Saves the draft. [issue]: "Salvar e emitir", which also issues it (after the same checks and confirmation as the certificate page).
  Future<void> _save({bool issue = false}) async {
    final date = parseDate(_fields['issueDate']!.text);
    final qty = parseDecimal(_fields['quantity']!.text.trim());
    if (date == null) return _fail('Data inválida');
    if (qty == null || qty <= 0) return _fail('Quantidade deve ser maior que zero');
    if (_v('description') == null) return _fail('Informe a descrição do produto');
    if (issue) {
      if (_measures.isEmpty) return _fail('O certificado não tem linhas. Adicione as linhas de química, dimensional ou ensaios e preencha o "Encontrado".');
      final empty = emptyFoundRows(_measures.map((m) => '${m['name']}'), _found.map((f) => f.text));
      // Nothing is saved before this check: a refused "Salvar e emitir" leaves the draft as it was.
      if (empty.isNotEmpty) return _fail(foundRowsMessage(empty));
      final ok = await confirmStep(
        context,
        title: 'Salvar e emitir ${c['reference']}?',
        message: 'Depois de emitido, os dados não podem mais ser editados.',
        confirmLabel: 'Emitir',
        icon: Icons.verified_outlined,
      );
      if (!ok || !mounted) return;
    }
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
        'title': _title,
        'measures': [
          for (var i = 0; i < _measures.length; i++)
            {'kind': _measures[i]['kind'], 'name': _measures[i]['name'], 'specified': _spec[i].text.trim(), 'found': _found[i].text.trim()},
        ],
      };
      var r = await api.put('/api/sales/certificates/${c['id']}', body) as Map<String, dynamic>;
      // What was typed is saved: a failure of the issue step below must not ask to discard it.
      _initial = _signature();
      widget.onPersisted?.call();
      if (issue) r = await api.post('/api/sales/certificates/${c['id']}/issue', {}) as Map<String, dynamic>;
      if (mounted) Navigator.of(context).pop(r);
    } catch (e) {
      if (mounted) _fail(friendlyError(e));
    }
  }

  Widget _text(String key, String label, {double width = 240, bool number = false, int lines = 1, String? hint}) => SizedBox(
    width: width,
    child: TextField(
      key: ValueKey('cert-$key'),
      controller: _fields[key],
      maxLines: lines,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
      textInputAction: lines > 1 ? TextInputAction.newline : TextInputAction.next,
      decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true),
    ),
  );

  Future<void> _addRow(String kind) async {
    final name = await promptText(
      context,
      title: 'Nova linha',
      label: kind == 'Chemical'
          ? 'Elemento (ex.: Ti)'
          : kind == 'Dimensional'
          ? 'Medida (ex.: Largura)'
          : 'Ensaio (ex.: Alongamento longitudinal, Teste destrutivo)',
      required: true,
      confirmLabel: 'Adicionar',
    );
    if (name == null || !mounted) return;
    setState(() {
      _measures.add({'kind': kind, 'name': name.trim()});
      _spec.add(TextEditingController());
      _found.add(TextEditingController());
    });
  }

  void _removeRow(int i) => setState(() {
    _measures.removeAt(i);
    _spec.removeAt(i).dispose();
    _found.removeAt(i).dispose();
  });

  void _addNote(String line) {
    final c = _fields['notes']!;
    final t = c.text.trimRight();
    c.text = t.isEmpty ? line : '$t\n$line';
    c.selection = TextSelection.collapsed(offset: c.text.length);
    setState(() {});
  }

  static const _kindIcons = {'Chemical': Icons.science_outlined, 'Dimensional': Icons.straighten, 'Mechanical': Icons.fitness_center};

  /// Same as the server: a row counts once it is not blank ("-" is a value).
  bool _hasValue(String t) => t.trim().isNotEmpty;

  InputDecoration _cell(ColorScheme scheme, {required bool found}) {
    final edge = found ? scheme.primary.withValues(alpha: 0.35) : Colors.transparent;
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecoration(
      isDense: true,
      hintText: '-',
      filled: true,
      fillColor: found ? scheme.primaryContainer.withValues(alpha: 0.35) : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border(edge),
      enabledBorder: border(edge),
      focusedBorder: border(scheme.primary, 1.6),
    );
  }

  Widget _tableTitle(String title, String kind, ColorScheme scheme, int total, int done) => Row(
    children: [
      Icon(_kindIcons[kind], size: 20, color: scheme.primary),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
      if (total > 0)
        Chip(
          visualDensity: VisualDensity.compact,
          side: BorderSide.none,
          backgroundColor: done == total ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          label: Text('$done de $total encontrados', style: Theme.of(context).textTheme.labelSmall),
        ),
    ],
  );

  /// Below this width of the card the value fields drop under the name, each with its own label, instead of squeezing into three slivers.
  static const _stackBelow = 600.0;

  Widget _tableHeaders(List<String> headers, ColorScheme scheme, TextStyle? label) => LayoutBuilder(
    builder: (context, box) => box.maxWidth < _stackBelow
        ? const SizedBox.shrink()
        : Row(
            children: [
              SizedBox(width: 92, child: Text(headers[0], style: label)),
              Expanded(child: Text(headers[1], style: label)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(headers[2], style: label?.copyWith(color: scheme.primary)),
              ),
              const SizedBox(width: kMinTouchTarget),
            ],
          ),
  );

  Widget _tableRow(String kind, int i, ColorScheme scheme) {
    final name = '${_measures[i]['name']}';
    Widget spec(bool narrow) => Semantics(
      label: 'Especificado: $name',
      child: TextField(
        key: ValueKey('spec-$kind-$name'),
        controller: _spec[i],
        textInputAction: TextInputAction.next,
        decoration: _cell(scheme, found: false).copyWith(labelText: narrow ? 'Especificado' : null),
      ),
    );
    Widget found(bool narrow) => Semantics(
      label: 'Encontrado: $name',
      child: TextField(
        key: ValueKey('found-$kind-$name'),
        controller: _found[i],
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
        decoration: _cell(scheme, found: true).copyWith(labelText: narrow ? 'Encontrado' : null),
      ),
    );
    final remove = IconButton(
      key: ValueKey('row-del-$kind-$name'),
      tooltip: 'Remover linha',
      constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
      icon: Icon(Icons.close, size: 20, color: scheme.onSurfaceVariant),
      onPressed: () => _removeRow(i),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < _stackBelow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                    remove,
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: spec(true)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: found(true)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(
                width: 92,
                // The name is cut at 92 px: the tooltip carries the whole of it.
                child: Tooltip(
                  message: name,
                  child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                ),
              ),
              Expanded(child: spec(false)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: found(false)),
              remove,
            ],
          );
        },
      ),
    );
  }

  Widget _table(String title, String kind, List<String> headers) {
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600);
    final idx = [
      for (var i = 0; i < _measures.length; i++)
        if (_measures[i]['kind'] == kind) i,
    ];
    final done = idx.where((i) => _hasValue(_found[i].text)).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tableTitle(title, kind, scheme, idx.length, done),
            const SizedBox(height: 10),
            _tableHeaders(headers, scheme, label),
            const SizedBox(height: 4),
            if (idx.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('Nenhuma linha.', style: label),
              ),
            for (final i in idx) _tableRow(kind, i, scheme),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('row-add-$kind'),
                onPressed: () => _addRow(kind),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Adicionar linha'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tables(BuildContext context) {
    final chem = _table('Composição química (%)', 'Chemical', const ['Elemento', 'Especificado', 'Encontrado']);
    final dim = _table('Dimensional (mm)', 'Dimensional', const ['Medida', 'Especificado', 'Encontrado']);
    final mech = _table('Ensaios mecânicos', 'Mechanical', const ['Limite', 'Especificado', 'Encontrado']);
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 1000
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: chem),
                const SizedBox(width: 12),
                Expanded(child: Column(children: [dim, gap, mech])),
              ],
            )
          : Column(children: [chem, gap, dim, gap, mech]),
    );
  }

  /// Where the specifications come from; folded away by default so the form starts with the fields.
  Widget _banner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.secondaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('cert-banner-toggle'),
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: () => setState(() => _bannerOpen = !_bannerOpen),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: scheme.onSecondaryContainer),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text('De onde vêm as especificações', style: Theme.of(context).textTheme.labelLarge)),
                    Icon(_bannerOpen ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
            ),
          ),
          if (_bannerOpen)
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: Text(
                'As especificações vêm do último certificado emitido para este cliente e produto (ou dos certificados em Excel de 2025-26); ao emitir, ficam salvas como modelo. Só o "Encontrado" muda a cada remessa.',
              ),
            ),
        ],
      ),
    );
  }

  Widget _certificateSection() => Section(
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
                DropdownMenuItem<int?>(
                  value: d['id'] as int,
                  child: Text('${d['reference']} · ${fmtDay(d['plannedDate'])}${d['invoiceNumber'] == null ? '' : ' · NF ${d['invoiceNumber']}'}'),
                ),
            ],
            onChanged: (v) => setState(() => _deliveryId = v),
          ),
        ),
      ],
    ),
  );

  Widget _productSection() => Section(
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
        SizedBox(
          width: 420,
          child: DropdownButtonFormField<String>(
            key: const ValueKey('cert-title'),
            initialValue: _title ?? '',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Título do certificado', border: OutlineInputBorder(), isDense: true),
            items: [
              for (final t in {..._titles, ?_title})
                DropdownMenuItem(
                  value: t,
                  child: Text(t.isEmpty ? 'Padrão · CERTIFICADO DE QUALIDADE' : t, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _title = (v == null || v.isEmpty) ? null : v),
          ),
        ),
        _text('notes', 'Observações', width: 700, lines: 3),
        SizedBox(
          width: 700,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (n, s) in _noteSnippets.indexed)
                ActionChip(key: ValueKey('note-snippet-$n'), label: Text(s.$1), onPressed: () => _addNote(s.$2)),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => DiscardGuard(
    isDirty: () => _signature() != _initial,
    // Ctrl+S saves; something in the page has to hold the focus for it to hear the key before a field is touched.
    child: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _busy ? null : unawaited(_save())},
      child: Focus(autofocus: true, skipTraversal: true, child: _scaffold(context)),
    ),
  );

  List<Widget> _saveActions(BuildContext context) {
    final canIssue = widget.session.canIssueCertificate;
    // On a narrow window the two buttons become icons with tooltips, so the title keeps its room.
    if (MediaQuery.sizeOf(context).width < 600) {
      return [
        if (canIssue)
          IconButton(
            key: const ValueKey('cert-save-issue'),
            tooltip: 'Salvar e emitir',
            onPressed: _busy ? null : () => _save(issue: true),
            icon: const Icon(Icons.verified_outlined),
          ),
        IconButton(key: const ValueKey('cert-save'), tooltip: 'Salvar (Ctrl+S)', onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined)),
      ];
    }
    return [
      if (canIssue)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: OutlinedButton.icon(
            key: const ValueKey('cert-save-issue'),
            onPressed: _busy ? null : () => _save(issue: true),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Salvar e emitir'),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: FilledButton.icon(
          key: const ValueKey('cert-save'),
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Salvar'),
        ),
      ),
    ];
  }

  Widget _scaffold(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Certificado ${c['reference']} · ${c['orderReference']}', overflow: TextOverflow.ellipsis),
      actions: _saveActions(context),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ),
            _certificateSection(),
            gap,
            _productSection(),
            gap,
            _banner(context),
            gap,
            _tables(context),
          ],
        ),
      ),
    ),
  );
}

/// Specification templates learned from issued certificates, one per customer and product.
class CertificateTemplatesScreen extends StatefulWidget {
  const CertificateTemplatesScreen({super.key, required this.session});

  final Session session;

  @override
  State<CertificateTemplatesScreen> createState() => _CertificateTemplatesScreenState();
}

class _CertificateTemplatesScreenState extends State<CertificateTemplatesScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  String _q = '';

  ApiClient get api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await api.get('/api/sales/certificates/templates') as List;
      if (mounted) {
        setState(() {
          _items = r.cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _forget(Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Esquecer este modelo?'),
        content: Text(
          'O próximo certificado de ${t['customerName']} para ${t['productCode']} volta a começar em branco. O modelo é recriado ao emitir outro certificado.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(key: const ValueKey('confirm-step'), onPressed: () => Navigator.pop(c, true), child: const Text('Esquecer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await runAction(context, () => api.delete('/api/sales/certificates/templates/${t['id']}'), success: 'Modelo removido');
    unawaited(_load());
  }

  Future<void> _edit(Map<String, dynamic> t) async {
    if (await showTemplateEditor(context, api, t) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modelo salvo')));
      unawaited(_load());
    }
  }

  Future<void> _importLegacy() async {
    final r = await runAction(context, () => api.post('/api/sales/certificates/templates/import-legacy', {}));
    if (r == null || !mounted) return;
    final m = r as Map<String, dynamic>;
    final created = m['created'] as int;
    final text = created == 0
        ? 'Nada novo: os modelos dos certificados em Excel já estão carregados.'
        : '$created modelos criados a partir dos certificados em Excel (${m['noCustomer']} sem cliente cadastrado, ${m['noProduct']} sem produto cadastrado).';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    unawaited(_load());
  }

  static const _kinds = {'Chemical': 'Química', 'Dimensional': 'Dimensional', 'Mechanical': 'Mecânico'};

  Widget _templateCard(Map<String, dynamic> t) => Card(
    child: ExpansionTile(
      key: ValueKey('template-${t['id']}'),
      title: Text('${t['customerName']} · ${t['productCode']}'),
      subtitle: Text('${t['productDescription']} · aprendido do certificado ${t['learnedFrom']}'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (t['title'] != null) Text('Título: ${t['title']}'),
        if (t['notes'] != null) Text('Observações: ${t['notes']}'),
        const SizedBox(height: 8),
        for (final m in (t['measures'] as List).cast<Map<String, dynamic>>()) Text('${_kinds[m['kind']] ?? m['kind']} · ${m['name']}: ${m['specified'] ?? '-'}'),
        if (widget.session.canCertificate)
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  key: ValueKey('template-edit-${t['id']}'),
                  onPressed: () => _edit(t),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar modelo'),
                ),
                TextButton.icon(
                  key: ValueKey('template-forget-${t['id']}'),
                  onPressed: () => _forget(t),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Esquecer modelo'),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final q = _q.trim().toLowerCase();
    final shown = items == null
        ? const <Map<String, dynamic>>[]
        : items.where((t) => q.isEmpty || '${t['customerName']} ${t['productCode']} ${t['productDescription']}'.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modelos de especificação'),
        actions: [
          // A one-off migration tool: it lives in the overflow menu, not in the bar.
          if (widget.session.canCertificate)
            PopupMenuButton<VoidCallback>(
              key: const ValueKey('templates-menu'),
              onSelected: (f) => f(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: const ValueKey('templates-import'),
                  value: _importLegacy,
                  child: const ListTile(leading: Icon(Icons.table_view_outlined), title: Text('Importar dos certificados em Excel')),
                ),
              ],
            ),
        ],
      ),
      body: _error != null
          ? LoadError(message: _error!, onRetry: _load)
          : items == null
          ? const RecordSkeleton()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Cada certificado emitido ensina o próximo do mesmo cliente e produto: limites especificados, título, acabamento e observações fixas. Os valores encontrados nunca são copiados.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('templates-search'),
                  onChanged: (v) => setState(() => _q = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Cliente ou produto',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(items.isEmpty ? 'Nenhum modelo ainda. Emita um certificado e o modelo aparece aqui.' : 'Nada encontrado.')),
                  ),
                for (final t in shown) _templateCard(t),
              ],
            ),
    );
  }
}

/// Edits the specification template of a customer + product without issuing a certificate. Returns true when saved.
Future<bool> showTemplateEditor(BuildContext context, ApiClient api, Map<String, dynamic> t) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _TemplateEditor(api: api, template: t),
    ) ??
    false;

class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({required this.api, required this.template});

  final ApiClient api;
  final Map<String, dynamic> template;

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateRow {
  _TemplateRow(this.kind, String name, String? specified) : name = TextEditingController(text: name), specified = TextEditingController(text: specified ?? '');

  String kind;
  final TextEditingController name;
  final TextEditingController specified;
}

class _TemplateEditorState extends State<_TemplateEditor> {
  late final TextEditingController _title = TextEditingController(text: '${widget.template['title'] ?? ''}');
  late final TextEditingController _finish = TextEditingController(text: '${widget.template['finish'] ?? ''}');
  late final TextEditingController _notes = TextEditingController(text: '${widget.template['notes'] ?? ''}');
  late final List<_TemplateRow> _rows = [
    for (final m in (widget.template['measures'] as List).cast<Map<String, dynamic>>()) _TemplateRow('${m['kind']}', '${m['name']}', m['specified'] as String?),
  ];
  String? _error;
  bool _busy = false;
  String _initial = '';

  String _signature() => [
    _title.text,
    _finish.text,
    _notes.text,
    for (final r in _rows) '${r.kind}|${r.name.text}|${r.specified.text}',
  ].join('\u0001');

  @override
  void initState() {
    super.initState();
    _initial = _signature();
  }

  static const _kinds = {'Chemical': 'Química', 'Dimensional': 'Dimensional', 'Mechanical': 'Mecânico'};

  @override
  void dispose() {
    for (final c in [_title, _finish, _notes]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.name.dispose();
      r.specified.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_rows.any((r) => r.name.text.trim().isEmpty)) {
      setState(() => _error = 'Toda linha precisa de um nome');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.put('/api/sales/certificates/templates/${widget.template['id']}', {
        'title': _title.text.trim(),
        'finish': _finish.text.trim(),
        'notes': _notes.text.trim(),
        'measures': [
          for (final r in _rows) {'kind': r.kind, 'name': r.name.text.trim(), 'specified': r.specified.text.trim()},
        ],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _rowEditor(int i, _TemplateRow r, InputDecoration dec) {
    final kind = DropdownButtonFormField<String>(
      initialValue: r.kind,
      isExpanded: true,
      decoration: dec,
      items: [for (final e in _kinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
      onChanged: (v) => setState(() => r.kind = v ?? r.kind),
    );
    final name = TextField(key: ValueKey('template-name-$i'), controller: r.name, textInputAction: TextInputAction.next, decoration: dec.copyWith(labelText: 'Nome'));
    final spec = TextField(key: ValueKey('template-spec-$i'), controller: r.specified, textInputAction: TextInputAction.next, decoration: dec.copyWith(labelText: 'Especificado'));
    final remove = IconButton(
      tooltip: 'Remover',
      constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
      icon: const Icon(Icons.close),
      onPressed: () => setState(() => _rows.removeAt(i)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth < 520
            // Narrow: the kind and the remove button on one line, the two text fields stacked under it.
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [Expanded(child: kind), remove]),
                  const SizedBox(height: AppSpacing.sm),
                  name,
                  const SizedBox(height: AppSpacing.sm),
                  spec,
                ],
              )
            : Row(
                children: [
                  SizedBox(width: 140, child: kind),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: name),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: spec),
                  remove,
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const dec = InputDecoration(border: OutlineInputBorder(), isDense: true);
    return DiscardGuard(
      isDirty: () => _signature() != _initial,
      child: _dialog(context, dec),
    );
  }

  Widget _dialog(BuildContext context, InputDecoration dec) {
    return AlertDialog(
      title: Text('Modelo · ${widget.template['customerName']} · ${widget.template['productCode']}'),
      content: DialogBody(
        ideal: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('template-title'),
                controller: _title,
                decoration: dec.copyWith(labelText: 'Título (vazio = padrão)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _finish,
                decoration: dec.copyWith(labelText: 'Acabamento'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                minLines: 1,
                maxLines: 4,
                decoration: dec.copyWith(labelText: 'Observação fixa'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text('Limites especificados', style: Theme.of(context).textTheme.titleSmall)),
                  TextButton.icon(
                    key: const ValueKey('template-add-row'),
                    onPressed: () => setState(() => _rows.add(_TemplateRow('Dimensional', '', null))),
                    icon: const Icon(Icons.add),
                    label: const Text('Linha'),
                  ),
                ],
              ),
              for (final (i, r) in _rows.indexed) _rowEditor(i, r, dec),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(key: const ValueKey('template-save'), onPressed: _busy ? null : _save, child: const Text('Salvar modelo')),
      ],
    );
  }
}
