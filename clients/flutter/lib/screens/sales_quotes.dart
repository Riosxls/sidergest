import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../reports/print_docs.dart';
import '../session.dart';
import '../widgets/discard_guard.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/pipeline.dart';
import '../widgets/record_list.dart';
import 'sales_common.dart';
import 'viability.dart';

const _requestExtensions = ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'txt'];

String _fmtSize(Object? v) {
  final n = v is num ? v : 0;
  return n >= 1048576 ? '${(n / 1048576).toStringAsFixed(1).replaceAll('.', ',')} MB' : '${(n / 1024).ceil()} KB';
}

/// Lets the user choose the customer's request file (PDF, image or text).
Future<({String name, Uint8List bytes})?> pickRequestFile() async {
  final files = await FilePicker.pickFiles(dialogTitle: 'Anexar arquivo', type: FileType.custom, allowedExtensions: _requestExtensions);
  if (files.isEmpty) return null;
  final f = files.first;
  return (name: f.name, bytes: await f.readAsBytes());
}

const salesLineFields = [
  FieldSpec('productId', 'Produto', type: FieldType.lookup, required: true, lookup: LookupSpec('/api/products')),
  FieldSpec('quantity', 'Quantidade', type: FieldType.decimal, required: true),
  FieldSpec('unitPrice', 'Preço unitário (R\$)', type: FieldType.decimal, hint: 'Vazio = tabela de preços do cliente'),
  FieldSpec('ipiPercent', 'IPI (%)', type: FieldType.decimal, hint: 'Vazio = tabela de preços'),
  FieldSpec('icmsPercent', 'ICMS (%)', type: FieldType.decimal, hint: 'Vazio = tabela de preços'),
  FieldSpec('leadTimeDays', 'Prazo de entrega (dias)', type: FieldType.integer, daysFor: 'deliveryDate'),
  FieldSpec('deliveryDate', 'Data de entrega', type: FieldType.date, dateFor: 'leadTimeDays'),
  FieldSpec('description', 'Descrição', hint: 'Vazio = descrição do cliente ou do produto'),
];

const specKeys = [
  'outsideDiameter',
  'thickness',
  'length',
  'standard',
  'condition',
  'saleUnit',
  'pieceWeightKg',
  'materialNeedKg',
  'toleranceDiameter',
  'toleranceThickness',
  'toleranceLengthPlus',
];

final orderLineFields = [
  ...salesLineFields,
  const FieldSpec('outsideDiameter', 'Ø externo (mm)', type: FieldType.decimal),
  const FieldSpec('thickness', 'Espessura (mm)', type: FieldType.decimal),
  const FieldSpec('length', 'Comprimento (mm)', type: FieldType.decimal),
  const FieldSpec('standard', 'Norma', hint: 'NBR 5599, DIN 2393…'),
  FieldSpec('condition', 'Estado de entrega', type: FieldType.choice, choices: deliveryConditions),
  FieldSpec('saleUnit', 'Unidade de venda', type: FieldType.choice, choices: saleUnits),
  const FieldSpec('pieceWeightKg', 'Peso da peça (kg)', type: FieldType.decimal),
  const FieldSpec('materialNeedKg', 'Necessidade de MP (kg)', type: FieldType.decimal, hint: 'Vazio = calculada pela quantidade'),
  const FieldSpec('toleranceDiameter', 'Tolerância Ø (± mm)', type: FieldType.decimal),
  const FieldSpec('toleranceThickness', 'Tolerância espessura (± mm)', type: FieldType.decimal),
  const FieldSpec('toleranceLengthPlus', 'Tolerância comprimento (+ mm)', type: FieldType.decimal),
  const FieldSpec(
    'feasibilityId',
    'Análise de viabilidade',
    type: FieldType.lookup,
    lookup: LookupSpec('/api/viability', query: {'usable': true}),
    hint: 'Cobre até 3 pedidos do mesmo item',
  ),
];

final orderLineColumns = <ColumnSpec>[
  ...salesLineColumns,
  ColumnSpec(
    'Medidas',
    (e) => [
      if (e['outsideDiameter'] != null) 'Ø${fmt(e['outsideDiameter'])}',
      if (e['thickness'] != null) 'e${fmt(e['thickness'])}',
      if (e['length'] != null) 'c${fmt(e['length'])}',
    ].join(' × '),
  ),
  ColumnSpec('Norma', (e) => [e['standard'], if (e['condition'] != null) deliveryConditions[e['condition']]].whereType<Object>().join(' · ')),
];

Map<String, dynamic> packSpec(Map<String, dynamic> line) {
  final spec = {
    for (final k in specKeys)
      if (line[k] != null) k: line[k],
  };
  final out = Map.of(line)..removeWhere((k, _) => specKeys.contains(k));
  if (spec.isNotEmpty) out['spec'] = spec;
  return out;
}

final salesLineColumns = [
  ColumnSpec('Produto', (e) => lbl(e, 'productId')),
  ColumnSpec('Quantidade', (e) => fmt(e['quantity']), numeric: true),
  ColumnSpec('Preço Unitário', (e) => e['unitPrice'] == null ? 'tabela' : fmtMoney(e['unitPrice']), numeric: true),
  ColumnSpec('IPI %', (e) => fmt(e['ipiPercent']), numeric: true),
  ColumnSpec('Valor estimado', (e) => e['unitPrice'] == null ? '' : fmtMoney(lineEstimate(e)), numeric: true),
  ColumnSpec('Entrega', (e) => e['deliveryDate'] != null ? fmtDay(e['deliveryDate']) : (e['leadTimeDays'] != null ? '${e['leadTimeDays']} dias' : '')),
];

num _n(Object? v) => v is num ? v : 0;

/// Quantity × unit price, plus IPI and ICMS amounts (both on the base value) when set.
num lineEstimate(Map<String, dynamic> l) {
  final base = _n(l['quantity']) * _n(l['unitPrice']);
  return base + base * _n(l['ipiPercent']) / 100 + base * _n(l['icmsPercent']) / 100;
}

class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key, required this.session});

  final Session session;

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _status;
  bool _open = false; // cancelled originals stay listed next to their revisions

  static const _cancellable = ['Draft', 'PendingApproval', 'Approved', 'Sent', 'Accepted', 'PurchaseOrder', 'Rejected', 'Expired'];

  /// Quick cancel from the list: asks for the reason, no need to open the quote.
  Future<void> _cancel(Map<String, dynamic> e) async {
    final reason = await promptText(context, title: 'Cancelar ${e['reference']}', label: 'Motivo', required: true);
    if (reason == null || !mounted) return;
    await runAction(context, () => widget.session.api.post('/api/sales/quotes/${e['id']}/cancel', {'note': reason}), success: '${e['reference']} cancelado');
  }

  Future<void> _new() async {
    final q = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => QuoteEditorScreen(session: widget.session)));
    _list.currentState?.reload();
    if (q == null || !mounted) return;
    await openQuote(context, widget.session, q['id'] as int);
    _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: widget.session.api,
    path: '/api/sales/quotes',
    query: {'status': _status, 'open': _open && _status == null ? true : null},
    searchHint: 'Orçamento, cliente ou referência do cliente',
    filters: [
      ChoiceFilter(label: 'Situação', value: _status, choices: quoteStatuses, onChanged: (v) => setState(() => _status = v)),
      FilterChip(label: const Text('Somente abertas'), selected: _open, onSelected: (v) => setState(() => _open = v)),
    ],
    fab: widget.session.canSell
        ? FloatingActionButton.extended(heroTag: 'new-quote', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Novo orçamento'))
        : null,
    columns: [
      col('Orçamento', 'reference'),
      col('Cliente', 'customerName'),
      labelCol('Situação', 'status', quoteStatuses),
      moneyCol('Total', 'total'),
      dateCol('Validade', 'validUntil'),
      dateCol('Criada', 'createdAt'),
      ColumnSpec('Desconto', (e) => e['needsApproval'] == true ? 'Acima do limite' : ''),
    ],
    rowActions: (e) => widget.session.canSell && _cancellable.contains(e['status']) ? [RowAction('Cancelar', Icons.block, () => _cancel(e))] : const [],
    rowColor: (ctx, e) => e['status'] == 'PendingApproval' ? toneColors(ctx, Tone.warning).$1 : null,
    onTap: (e) async {
      await openQuote(context, widget.session, e['id'] as int);
      _list.currentState?.reload();
    },
  );
}

class QuoteEditorScreen extends StatefulWidget {
  const QuoteEditorScreen({super.key, required this.session, this.quote, this.asOrder = false});

  final Session session;
  final Map<String, dynamic>? quote;
  final bool asOrder;

  @override
  State<QuoteEditorScreen> createState() => _QuoteEditorScreenState();
}

class _QuoteEditorScreenState extends State<QuoteEditorScreen> {
  late int? _customerId = widget.quote?['customerId'] as int?;
  late int? _addressId = widget.quote?['addressId'] as int?;
  late int? _termId = widget.quote?['paymentTermId'] as int?;
  late String? _customTerm = widget.quote?['customPaymentTerm'] as String?;
  late String _freight = '${widget.quote?['freight'] ?? 'Cif'}';
  late final _validity = TextEditingController(text: '${widget.quote?['validityDays'] ?? ''}');
  late final _contact = TextEditingController(text: widget.quote?['contactName'] as String? ?? '');
  late final _email = TextEditingController(text: widget.quote?['contactEmail'] as String? ?? '');
  late final _ref = TextEditingController(text: widget.quote?['customerReference'] as String? ?? '');
  late final _conditions = TextEditingController(text: widget.quote?['conditions'] as String? ?? '');
  late final _notes = TextEditingController(text: widget.quote?['notes'] as String? ?? '');
  late final _po = TextEditingController(text: widget.quote?['customerPo'] as String? ?? '');
  late final _salesperson = TextEditingController(text: widget.quote?['salesperson'] as String? ?? widget.session.username ?? '');
  late String _billTo = '${widget.quote?['billTo'] ?? 'Ebt'}';
  late String _origin = '${widget.quote?['origin'] ?? 'Email'}';
  late List<Map<String, dynamic>> _lines = [
    for (final l in (widget.quote?['lines'] as List? ?? []).cast<Map<String, dynamic>>())
      {
        'productId': l['productId'],
        'quantity': l['quantity'],
        'unitPrice': l['unitPrice'],
        'ipiPercent': l['ipiPercent'],
        'icmsPercent': l['icmsPercent'],
        'leadTimeDays': l['leadTimeDays'],
        'deliveryDate': l['deliveryDate'] ?? l['dueDate'],
        'description': l['description'],
        ...?(l['spec'] as Map<String, dynamic>?),
        'feasibilityId': l['feasibilityId'],
        '_labels': {'productId': '${l['productCode']} · ${l['description']}', if (l['feasibilityId'] != null) 'feasibilityId': '${l['feasibilityReference']}'},
      },
  ];
  List<Map<String, dynamic>> _addresses = [];
  String? _message;
  bool _busy = false;
  late final String _initial;

  String _signature() => jsonEncode([
    _customerId, _addressId, _termId, _customTerm, _freight, _lines,
    for (final c in [_validity, _contact, _email, _ref, _conditions, _notes, _po]) c.text,
  ]);

  ApiClient get api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _initial = _signature();
    if (_customerId != null) _loadAddresses(_customerId!, keep: true);
  }

  @override
  void dispose() {
    for (final c in [_validity, _contact, _email, _ref, _conditions, _notes, _po, _salesperson]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _termName;

  /// Pre-fills the prazo with the customer's default when the user has not picked one yet.
  Future<void> _applyDefaultTerm(int customerId) async {
    if (_termId != null || _customTerm != null) return;
    try {
      final c = await api.get('/api/customers/$customerId') as Map<String, dynamic>;
      final company = c['company'] as Map<String, dynamic>?;
      final termId = company?['paymentTermId'] as int?;
      if (!mounted || termId == null || _termId != null || _customTerm != null || _customerId != customerId) return;
      setState(() {
        _termId = termId;
        _termName = company?['paymentTermName'] as String?;
      });
    } catch (_) {}
  }

  Future<void> _loadAddresses(int customerId, {bool keep = false}) async {
    try {
      final r = await api.get('/api/customers/$customerId/addresses');
      final list = (r is List ? r : (r as Map<String, dynamic>)['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _addresses = list;
        if (!keep || !list.any((a) => a['id'] == _addressId)) _addressId = list.isEmpty ? null : list.first['id'] as int;
        final first = list.isEmpty ? null : list.firstWhere((a) => a['id'] == _addressId, orElse: () => list.first);
        if (!keep) {
          // A new customer replaces the previous customer's contact details.
          _contact.text = '${first?['buyer'] ?? ''}';
          _email.text = '${first?['email'] ?? ''}';
        }
      });
    } catch (_) {}
  }

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_customerId == null) return setState(() => _message = 'Informe o cliente');
    if (_termId == null && _customTerm == null) return setState(() => _message = 'Informe o prazo');
    if (_lines.isEmpty) return setState(() => _message = 'Inclua ao menos um item');
    if (widget.asOrder && _addressId == null) return setState(() => _message = 'O cliente precisa de um endereço de entrega cadastrado');
    setState(() {
      _busy = true;
      _message = null;
    });
    final body = {
      'customerId': _customerId,
      'addressId': _addressId,
      'paymentTermId': _termId,
      'customPaymentTerm': _termId == null ? _customTerm : null,
      'freight': _freight,
      'validityDays': int.tryParse(_validity.text.trim()),
      'contactName': _t(_contact),
      'contactEmail': _t(_email),
      'customerReference': _t(_ref),
      'conditions': _t(_conditions),
      'notes': _t(_notes),
      'lines': [for (final l in _lines) widget.asOrder ? packSpec(stripLocal(l)) : stripLocal(l)],
    };
    if (widget.asOrder) {
      body['customerPo'] = _t(_po);
      body['billTo'] = _billTo;
      body['origin'] = _origin;
      body['salesperson'] = _t(_salesperson);
    }
    final path = widget.asOrder ? '/api/sales/orders' : '/api/sales/quotes';
    try {
      final q = (widget.quote == null ? await api.post(path, body) : await api.put('$path/${widget.quote!['id']}', body)) as Map<String, dynamic>;
      if (mounted) Navigator.pop(context, q);
    } on ApiException catch (e) {
      setState(() => _message = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final w = wide ? 300.0 : double.infinity;
    final estimate = _lines.fold<num>(0, (a, l) => a + lineEstimate(l));
    return DiscardGuard(
      isDirty: () => _signature() != _initial,
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.quote != null ? 'Editar ${widget.quote!['reference']}' : (widget.asOrder ? 'Novo pedido de venda' : 'Novo orçamento comercial')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              key: const ValueKey('quote-save'),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Salvar'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Section(
            title: 'Cliente e condições',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: w,
                  child: LookupField(
                    key: const ValueKey('quote-customer'),
                    api: api,
                    spec: const LookupSpec('/api/customers'),
                    label: 'Cliente *',
                    value: _customerId,
                    initialDisplay: widget.quote?['customerName'] as String?,
                    enabled: widget.quote == null || !widget.asOrder, // an order keeps its customer; a draft quote can change it
                    onChanged: (id, _) {
                      setState(() {
                        _customerId = id;
                        _addresses = [];
                        _addressId = null;
                      });
                      if (id != null) {
                        _loadAddresses(id);
                        _applyDefaultTerm(id);
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: wide ? 460 : w,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _addresses.any((a) => a['id'] == _addressId) ? _addressId : null,
                    key: ValueKey('addr-${_addresses.length}-$_addressId'),
                    isExpanded: true,
                    decoration: _dec('Local de entrega', hint: _customerId == null ? 'Escolha o cliente' : 'Sem endereço cadastrado'),
                    items: [
                      for (final a in _addresses)
                        DropdownMenuItem(
                          value: a['id'] as int,
                          child: Text(
                            [a['street'], a['number'], a['city'], a['uf']].where((x) => x != null && '$x'.isNotEmpty).join(', '),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _addressId = v),
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _customTerm != null && _termId == null
                      ? InputDecorator(
                          key: const ValueKey('quote-custom-term'),
                          decoration: InputDecoration(
                            labelText: 'Prazo * (personalizado)',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              tooltip: 'Escolher outro prazo',
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => _customTerm = null),
                            ),
                          ),
                          child: Text(_customTerm!, overflow: TextOverflow.ellipsis),
                        )
                      : LookupField(
                          key: ValueKey('quote-term-$_termId'),
                          api: api,
                          spec: const LookupSpec('/api/sales/payment-terms'),
                          label: 'Prazo *',
                          value: _termId,
                          initialDisplay: _termName ?? widget.quote?['paymentTermName'] as String?,
                          onChanged: (id, _) => setState(() {
                            _termId = id;
                            _termName = null;
                            if (id != null) _customTerm = null;
                          }),
                          onCustom: (text) => setState(() {
                            _termId = null;
                            _customTerm = text;
                          }),
                        ),
                ),
                SizedBox(
                  width: w,
                  child: DropdownButtonFormField<String>(
                    initialValue: _freight,
                    isExpanded: true,
                    decoration: _dec('Frete'),
                    items: [for (final e in freightTerms.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => _freight = v ?? 'Cif'),
                  ),
                ),
                if (widget.asOrder) ...[
                  SizedBox(
                    width: w,
                    child: TextField(controller: _po, decoration: _dec('Pedido de compra do cliente')),
                  ),
                  SizedBox(
                    width: w,
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('order-bill-to'),
                      initialValue: _billTo,
                      decoration: _dec('Faturar para'),
                      items: [for (final e in billToLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setState(() => _billTo = v ?? 'Ebt'),
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('order-origin'),
                      initialValue: _origin,
                      decoration: _dec('Origem do pedido'),
                      items: [for (final e in orderOrigins.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setState(() => _origin = v ?? 'Email'),
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: TextField(key: const ValueKey('order-salesperson'), controller: _salesperson, decoration: _dec('Responsável de vendas')),
                  ),
                ],
                if (!widget.asOrder) ...[
                  SizedBox(
                    width: wide ? 140 : w,
                    child: TextField(
                      controller: _validity,
                      keyboardType: TextInputType.number,
                      decoration: _dec('Validade (dias)', hint: 'padrão'),
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: TextField(controller: _contact, decoration: _dec('Contato (A/C)')),
                  ),
                  SizedBox(
                    width: w,
                    child: TextField(key: const ValueKey('quote-email'), controller: _email, decoration: _dec('E-mail do contato')),
                  ),
                  SizedBox(
                    width: w,
                    child: TextField(
                      controller: _ref,
                      decoration: _dec('Referência do cliente', hint: 'nº da RFQ/cotação dele'),
                    ),
                  ),
                  SizedBox(
                    width: wide ? 612 : w,
                    child: TextField(
                      controller: _conditions,
                      maxLines: 3,
                      minLines: 1,
                      decoration: _dec('Condições gerais', hint: 'Vazio = padrão dos parâmetros'),
                    ),
                  ),
                ],
                SizedBox(
                  width: wide ? 612 : w,
                  child: TextField(controller: _notes, maxLines: 3, minLines: 1, decoration: _dec('Observações')),
                ),
              ],
            ),
          ),
          gap,
          LinesEditor(
            api: api,
            title: 'Itens',
            fields: widget.asOrder ? orderLineFields : salesLineFields,
            newTitle: widget.asOrder ? 'Nova linha' : 'Criar orçamento',
            addLabel: widget.asOrder ? 'Adicionar linha' : 'Criar orçamento',
            addEnabled: widget.asOrder || (_customerId != null && (_termId != null || _customTerm != null)),
            editTitle: widget.asOrder ? null : 'Editar orçamento',
            lines: _lines,
            onChanged: (l) => setState(() => _lines = l),
            columns: widget.asOrder ? orderLineColumns : salesLineColumns,
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Estimativa (itens com preço informado, com IPI e ICMS): ${fmtMoney(estimate)}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (_message != null) Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
    ));
  }
}

class QuoteScreen extends StatefulWidget {
  const QuoteScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> {
  Map<String, dynamic>? _q;
  String? _error;
  num? _maxDiscount;

  ApiClient get api => widget.session.api;
  Session get s => widget.session;
  String get base => '/api/sales/quotes/${widget.id}';
  String get status => '${_q?['status']}';

  @override
  void initState() {
    super.initState();
    _load();
    api.get('/api/sales/settings').then((r) {
      if (mounted) setState(() => _maxDiscount = (r as Map<String, dynamic>)['maxDiscountPercent'] as num?);
    }, onError: (_) {});
  }

  Future<void> _load() async {
    try {
      final q = await api.get(base) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _q = q;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _act(String action, {Map<String, dynamic> body = const {}, String? success}) async {
    final r = await runAction(context, () => api.post('$base/$action', body), success: success);
    if (r is Map<String, dynamic>) setState(() => _q = r);
  }

  Future<void> _send() async {
    final q = _q!;
    if (q['status'] == 'Draft' && q['needsApproval'] == true) {
      final ok = await confirmStep(
        context,
        title: 'Enviar para aprovação?',
        message:
            'O desconto deste orçamento (${fmt(q['totals']['maxDiscountPercent'])}%) passa do limite de ${fmt(_maxDiscount)}%. Ele vai para o gerente comercial aprovar antes de seguir ao cliente.',
        confirmLabel: 'Enviar para aprovação',
        icon: Icons.verified_user_outlined,
      );
      if (ok && mounted) await _act('send', success: 'Enviada para aprovação do gerente');
      return;
    }
    final r = await submitForm(
      context,
      api: api,
      title: 'Enviar ${q['reference']} ao cliente',
      fields: [
        FieldSpec('sentTo', 'Enviar para (contato ou e-mail)', required: true, defaultValue: q['contactEmail'] ?? q['contactName']),
        const FieldSpec('note', 'Observação'),
      ],
      submit: (b) => api.post('$base/send', b),
    );
    if (r != null && r['reference'] != null) {
      setState(() => _q = r);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Orçamento enviado · válida até ${fmtDay(r['validUntil'])}')));
    }
  }

  /// "Pedido de compra" step: the customer's PO (file and/or text) must be attached before the quote moves on.
  Future<void> _receivePo() async {
    final q = _q!;
    if ('${q['requestText'] ?? ''}'.trim().isEmpty && q['requestFileName'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anexe o arquivo ou o texto do pedido de compra antes de registrá-lo')));
      return;
    }
    final r = await submitForm(
      context,
      api: api,
      title: 'Pedido de compra de ${q['reference']}',
      fields: [FieldSpec('customerPo', 'Nº do pedido de compra do cliente', defaultValue: q['customerPo']), const FieldSpec('note', 'Observação')],
      submit: (b) => api.post('$base/purchase-order', b),
    );
    if (r != null && r['reference'] != null) setState(() => _q = r);
  }

  Future<void> _accept() async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Cliente aprovou ${_q!['reference']}',
      fields: const [FieldSpec('customerPo', 'Nº do pedido de compra do cliente'), FieldSpec('note', 'Observação')],
      submit: (b) => api.post('$base/accept', b),
    );
    if (r != null && r['reference'] != null) setState(() => _q = r);
  }

  Future<void> _setRequestText() async {
    final text = await promptText(context, title: 'Texto do pedido de compra', label: 'Texto do pedido de compra', initial: '${_q?['requestText'] ?? ''}', confirmLabel: 'Salvar');
    if (text == null || !mounted) return;
    final r = await runAction(context, () => api.put('$base/request', {'text': text}));
    if (r is Map<String, dynamic>) setState(() => _q = r);
  }

  Future<void> _attachRequest() async {
    final f = await pickRequestFile();
    if (f == null || !mounted) return;
    final r = await runAction(context, () => api.upload('$base/request-file', 'file', f.name, f.bytes), success: 'Arquivo anexado');
    if (r is Map<String, dynamic>) setState(() => _q = r);
  }

  Future<void> _removeRequest() async {
    final r = await runAction(context, () => api.delete('$base/request-file'), success: 'Anexo removido');
    if (r is Map<String, dynamic>) setState(() => _q = r);
  }

  Future<void> _saveRequest() async {
    try {
      final bytes = await api.download('$base/request-file');
      final saved = await FilePicker.saveFile(fileName: '${_q!['requestFileName']}', bytes: bytes, dialogTitle: 'Salvar pedido de compra');
      if (saved != null && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Arquivo salvo')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha: $e')));
    }
  }

  Future<void> _reason(String action, String title, {String label = 'Motivo', String? success}) async {
    final reason = await promptText(context, title: title, label: label, required: true);
    if (reason == null || !mounted) return;
    await _act(action, body: {'note': reason}, success: success);
  }

  /// Cancels this quote (reason required) and opens the new revision as a draft with the same client, items and prazo.
  Future<void> _revise() async {
    final q = _q!;
    final r = await submitForm(
      context,
      api: api,
      title: 'Revisar ${q['reference']}',
      fields: [
        const FieldSpec('note', 'Motivo do cancelamento', required: true, hint: 'O orçamento atual fica cancelado, só para consulta'),
        FieldSpec('customerPo', 'Pedido de compra do cliente', defaultValue: q['customerPo'], hint: 'Mantenha o mesmo ou informe outro'),
      ],
      submit: (b) => api.post('$base/revise', b),
    );
    if (r == null || r['id'] == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${q['reference']} cancelado · nova revisão ${r['reference']} em rascunho')));
    await _load();
    if (mounted) await openQuote(context, s, r['id'] as int);
    if (mounted) _load();
  }

  Future<void> _convert() async {
    final ok = await confirmStep(
      context,
      title: 'Gerar pedido de venda?',
      message: 'Os itens, preços e condições de ${_q!['reference']} viram um pedido de venda. O limite de crédito do cliente é verificado agora.',
      confirmLabel: 'Gerar pedido',
      icon: Icons.receipt_long_outlined,
    );
    if (!ok || !mounted) return;
    Map<String, dynamic>? order;
    try {
      order = await api.post('$base/convert', {}) as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 409 && e.message.contains('Credit limit') && s.canApproveSales) {
        final force = await confirmStep(
          context,
          title: 'Limite de crédito excedido',
          message: '${e.message}\n\nLiberar mesmo assim? A liberação fica registrada no histórico.',
          confirmLabel: 'Liberar e gerar',
          danger: true,
          icon: Icons.warning_amber,
        );
        if (!force || !mounted) return;
        order = await runAction(context, () async => await api.post('$base/convert', {'overrideCredit': true}) as Map<String, dynamic>);
      } else {
        return showError(context, describeError(e));
      }
    }
    if (order == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pedido ${order['reference']} criado')));
    await _load();
    if (mounted) await openSalesOrder(context, s, order['id'] as int);
    _load();
  }

  Future<void> _edit() async {
    final r = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => QuoteEditorScreen(session: s, quote: _q),
      ),
    );
    if (r != null) {
      setState(() => _q = r);
      await _load();
    }
  }

  Future<void> _delete() async {
    if (!await confirmStep(
          context,
          title: 'Excluir ${_q!['reference']}?',
          message: 'O rascunho é apagado definitivamente.',
          confirmLabel: 'Excluir',
          danger: true,
        ) ||
        !mounted) {
      return;
    }
    final ok = await runAction(context, () async {
      await api.delete(base);
      return true;
    }, success: 'Orçamento excluído');
    if (ok == true && mounted) Navigator.pop(context);
  }

  String proposalText(Map<String, dynamic> q) {
    final b = StringBuffer()
      ..writeln('ORÇAMENTO COMERCIAL ${q['reference']}')
      ..writeln('Cliente: ${q['customerName']}')
      ..writeln(q['contactName'] == null ? '' : 'A/C: ${q['contactName']}')
      ..writeln(q['customerReference'] == null ? '' : 'Sua referência: ${q['customerReference']}')
      ..writeln('Prazo: ${q['paymentTermName'] ?? q['customPaymentTerm'] ?? 'a combinar'} · Frete: ${freightTerms[q['freight']] ?? q['freight']}')
      ..writeln()
      ..writeln('Item  Produto  Descrição  Qtd  Un  Vl. unit.  IPI%  Vl. total  Entrega');
    for (final l in (q['lines'] as List).cast<Map<String, dynamic>>()) {
      b.writeln(
        '${l['sequence']}  ${l['customerPartNumber'] ?? l['productCode']}  ${l['description']}  ${fmt(l['quantity'])}  ${l['unit']}  ${fmtNum(l['unitPrice'], 4)}  ${fmt(l['ipiPercent'])}  ${fmtNum(l['total'])}  ${l['deliveryDate'] != null ? fmtDay(l['deliveryDate']) : (l['leadTimeDays'] != null ? '${l['leadTimeDays']} dias' : '')}',
      );
    }
    final t = q['totals'] as Map<String, dynamic>;
    b
      ..writeln()
      ..writeln('Total dos produtos: ${fmtMoney(t['products'])}')
      ..writeln('IPI: ${fmtMoney(t['ipi'])}')
      ..writeln('Total do orçamento: ${fmtMoney(t['total'])}')
      ..writeln()
      ..writeln('Validade: ${q['validityDays']} dias${q['validUntil'] == null ? '' : ' (até ${fmtDay(q['validUntil'])})'}');
    if (q['conditions'] != null) b.writeln('Condições gerais: ${q['conditions']}');
    return b.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  Widget _requestSection(Map<String, dynamic> q) {
    final text = '${q['requestText'] ?? ''}';
    final fileName = q['requestFileName'] as String?;
    final canEdit = s.canSell && (status == 'Accepted' || status == 'PurchaseOrder');
    return Section(
      title: 'Pedido de compra',
      actions: [
        if (canEdit) TextButton.icon(key: const ValueKey('quote-po-text'), onPressed: _setRequestText, icon: const Icon(Icons.edit_note), label: const Text('Texto do pedido')),
        if (canEdit) TextButton.icon(key: const ValueKey('quote-po-attach'), onPressed: _attachRequest, icon: const Icon(Icons.attach_file), label: Text(fileName == null ? 'Anexar arquivo' : 'Substituir arquivo')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fileName == null && text.isEmpty) const Text('Nenhum pedido de compra anexado (PDF, imagem ou texto)'),
          if (fileName != null)
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text('$fileName · ${_fmtSize(q['requestFileSize'])}', overflow: TextOverflow.ellipsis)),
                TextButton.icon(onPressed: _saveRequest, icon: const Icon(Icons.download_outlined), label: const Text('Baixar')),
                if (canEdit) IconButton(tooltip: 'Remover anexo', icon: const Icon(Icons.delete_outline), onPressed: _removeRequest),
              ],
            ),
          if (text.isNotEmpty) SelectableText(text),
        ],
      ),
    );
  }

  Future<void> _preview() async {
    final text = proposalText(_q!);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Orçamento ${_q!['reference']}'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fechar')),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Texto copiado')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar'),
          ),
        ],
      ),
    );
  }

  Widget _nextStep(Map<String, dynamic> q) {
    final st = q['status'];
    final sell = s.canSell;
    FilledButton primary(String key, String label, IconData icon, VoidCallback onPressed) =>
        FilledButton.icon(key: ValueKey(key), onPressed: onPressed, icon: Icon(icon), label: Text(label));
    OutlinedButton secondary(String key, String label, IconData icon, VoidCallback onPressed) =>
        OutlinedButton.icon(key: ValueKey(key), onPressed: onPressed, icon: Icon(icon), label: Text(label));
    return switch (st) {
      'Draft' => NextStepCard(
        title: q['needsApproval'] == true ? 'Desconto acima do limite' : 'Pronta para enviar?',
        message: q['needsApproval'] == true
            ? 'O maior desconto sobre a tabela é ${fmt(q['totals']['maxDiscountPercent'])}%${_maxDiscount == null ? '' : ' (limite ${fmt(_maxDiscount)}%)'}. O envio passa pela aprovação do gerente comercial.'
            : 'Confira itens, preços e prazos. Ao enviar, a validade começa a contar.',
        tone: q['needsApproval'] == true ? Tone.warning : Tone.info,
        actions: [if (sell) primary('quote-send', q['needsApproval'] == true ? 'Enviar para aprovação' : 'Enviar ao cliente', Icons.send, _send)],
      ),
      'PendingApproval' => NextStepCard(
        title: 'Aguardando aprovação do gerente',
        message: 'Desconto de ${fmt(q['totals']['maxDiscountPercent'])}% sobre a tabela de preços.',
        tone: Tone.warning,
        actions: [
          if (s.canApproveSales) primary('quote-approve', 'Aprovar desconto', Icons.thumb_up_alt_outlined, () => _act('approve', success: 'Desconto aprovado')),
          if (s.canApproveSales)
            secondary(
              'quote-reject-approval',
              'Recusar',
              Icons.thumb_down_alt_outlined,
              () => _reason('reject-approval', 'Recusar desconto', success: 'Orçamento voltou para rascunho'),
            ),
        ],
      ),
      'Approved' => NextStepCard(
        title: 'Desconto aprovado',
        message: 'Aprovado por ${q['approvedBy'] ?? ''} em ${fmtDate(q['approvedAt'])}. Agora envie ao cliente.',
        actions: [if (sell) primary('quote-send', 'Enviar ao cliente', Icons.send, _send)],
      ),
      'Sent' => NextStepCard(
        title: 'Aguardando resposta do cliente',
        message: 'Enviada para ${q['sentTo'] ?? ''} em ${fmtDate(q['sentAt'])}. Válida até ${fmtDay(q['validUntil'])}.',
        actions: [
          if (sell) primary('quote-accept', 'Cliente aprovou', Icons.thumb_up_alt_outlined, _accept),
          if (sell)
            secondary(
              'quote-decline',
              'Cliente recusou',
              Icons.thumb_down_alt_outlined,
              () => _reason('decline', 'Cliente recusou ${q['reference']}', success: 'Recusa registrada'),
            ),
        ],
      ),
      'Accepted' => NextStepCard(
        title: 'Aprovada pelo cliente',
        message: 'Anexe o pedido de compra do cliente (arquivo ou texto) e registre-o para gerar o pedido de venda.',
        tone: Tone.success,
        actions: [if (sell) primary('quote-po', 'Registrar pedido de compra', Icons.assignment_turned_in_outlined, _receivePo)],
      ),
      'PurchaseOrder' => NextStepCard(
        title: 'Pedido de compra recebido',
        message: 'Gere o pedido de venda${q['customerPo'] == null ? '' : ' (pedido do cliente ${q['customerPo']})'} para liberar a produção.',
        tone: Tone.success,
        actions: [if (sell) primary('quote-convert', 'Gerar pedido de venda', Icons.receipt_long, _convert)],
      ),
      'Converted' => NextStepCard(
        title: 'Convertida em pedido',
        message: 'Este orçamento virou o pedido ${q['salesOrderReference'] ?? ''}.',
        tone: Tone.success,
        actions: [
          if (q['salesOrderId'] != null)
            primary('quote-open-order', 'Abrir pedido', Icons.open_in_new, () => openSalesOrder(context, s, q['salesOrderId'] as int).then((_) => _load())),
        ],
      ),
      'Rejected' || 'Expired' => NextStepCard(
        title: st == 'Rejected' ? 'Recusada pelo cliente' : 'Validade expirada',
        message: q['decisionNote'] == null ? 'Revise preços e prazos e envie de novo.' : 'Motivo: ${q['decisionNote']}. Revise e envie de novo.',
        tone: Tone.danger,
        actions: [if (sell) primary('quote-revise', 'Revisar orçamento', Icons.edit, _revise)],
      ),
      _ => NextStepCard(title: 'Cancelada', message: '${q['decisionNote'] ?? ''}', tone: Tone.danger),
    };
  }

  static const _revisable = ['PendingApproval', 'Approved', 'Sent', 'Accepted', 'PurchaseOrder', 'Rejected', 'Expired'];
  Future<void> _newFeasibility() async {
    final q = _q!;
    final r = await newFeasibility(
      context,
      s,
      initial: {
        'customerId': q['customerId'],
        'quoteId': q['id'],
        '_labels': {'customerId': '${q['customerName']}', 'quoteId': '${q['reference']}'},
      },
    );
    if (r != null && r['id'] is int && mounted) await openFeasibility(context, s, r['id'] as int);
  }

  List<Widget> _menuActions() {
    final q = _q;
    if (q == null) return [];
    final menu = <PopupMenuEntry<VoidCallback>>[
      PopupMenuItem(
        value: _preview,
        child: const ListTile(leading: Icon(Icons.description_outlined), title: Text('Ver texto do orçamento')),
      ),
      if (s.canSell && !['Cancelled', 'Converted'].contains(status))
        PopupMenuItem(
          value: _newFeasibility,
          child: const ListTile(leading: Icon(Icons.fact_check_outlined), title: Text('Nova análise de viabilidade')),
        ),
      if (s.canSell && status == 'Draft')
        PopupMenuItem(
          value: _edit,
          child: const ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar')),
        ),
      if (s.canSell && _revisable.contains(status))
        PopupMenuItem(
          value: _revise,
          child: const ListTile(leading: Icon(Icons.history_edu), title: Text('Revisar orçamento')),
        ),
      if (s.canSell && ['Draft', 'PendingApproval', 'Approved', 'Sent', 'PurchaseOrder', 'Accepted', 'Rejected', 'Expired'].contains(status))
        PopupMenuItem(
          value: () => _reason('cancel', 'Cancelar ${q['reference']}', success: 'Orçamento cancelado'),
          child: const ListTile(leading: Icon(Icons.block), title: Text('Cancelar')),
        ),
      if (s.canSell && status == 'Draft' && q['revision'] == 0)
        PopupMenuItem(
          value: _delete,
          child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Excluir')),
        ),
    ];
    return [
      if (s.canSell && _revisable.contains(status))
        TextButton.icon(key: const ValueKey('quote-revise-top'), onPressed: _revise, icon: const Icon(Icons.history_edu), label: const Text('Revisar')),
      PrintButton(name: 'Orçamento ${q['reference']}', builder: () => buildQuotePdf(api, q)),
      if (s.canSell && status == 'Draft') IconButton(tooltip: 'Editar', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
      PopupMenuButton<VoidCallback>(key: const ValueKey('quote-menu'), onSelected: (f) => f(), itemBuilder: (_) => menu),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    return Scaffold(
      appBar: AppBar(
        title: Text(q == null ? 'Orçamento' : '${q['reference']} · ${q['customerName']}', overflow: TextOverflow.ellipsis),
        actions: _menuActions(),
      ),
      body: _error != null && q == null
          ? Center(child: Text(_error!))
          : q == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(q)),
    );
  }

  Widget _body(Map<String, dynamic> q) {
    final t = q['totals'] as Map<String, dynamic>;
    final (step, failed) = quotePath(q['status']);
    final lines = (q['lines'] as List).cast<Map<String, dynamic>>();
    return SideBySide(
      main: [
        RecordHeader(
          icon: Icons.request_quote_outlined,
          kind: 'Orçamento comercial${q['revision'] == 0 ? '' : ' · revisão ${String.fromCharCode(65 + (q['revision'] as int))}'}',
          title: '${q['reference']}',
          badge: StatusBadge(quoteStatuses[q['status']] ?? '${q['status']}', tone: quoteTone(q['status'])),
          amount: fmtMoney(t['total']),
          fields: [
            ('Cliente', '${q['customerName']}'),
            ('Contato', [q['contactName'], q['contactEmail']].whereType<String>().join(' · ')),
            ('Validade', q['validUntil'] != null ? fmtDay(q['validUntil']) : '${q['validityDays']} dias após envio'),
            ('Prazo', fmt(q['paymentTermName'] ?? q['customPaymentTerm'])),
            ('Frete', freightTerms[q['freight']] ?? fmt(q['freight'])),
            ('Ref. do cliente', fmt(q['customerReference'])),
            ('Pedido do cliente', fmt(q['customerPo'])),
          ],
        ),
        gap,
        StagePath(steps: flowSteps, current: step, failedLabel: failed),
        gap,
        _nextStep(q),
        gap,
        Section(
          title: 'Itens (${lines.length})',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SimpleTable(
                columns: [
                  col('Item', 'sequence'),
                  ColumnSpec('Produto', (e) => '${e['productCode']}${e['customerPartNumber'] == null ? '' : ' (${e['customerPartNumber']})'}'),
                  col('Descrição', 'description'),
                  ColumnSpec('Qtd.', (e) => '${fmt(e['quantity'])} ${e['unit']}', numeric: true),
                  ColumnSpec('Preço Unitário', (e) => fmtMoney(e['unitPrice']), numeric: true),
                  ColumnSpec('Desc. %', (e) => e['discountPercent'] == null || e['discountPercent'] == 0 ? '' : fmt(e['discountPercent']), numeric: true),
                  col('IPI %', 'ipiPercent', numeric: true),
                  ColumnSpec(
                    'Entrega',
                    (e) => e['deliveryDate'] != null ? fmtDay(e['deliveryDate']) : (e['leadTimeDays'] != null ? '${e['leadTimeDays']} dias' : ''),
                  ),
                  moneyCol('Total', 'total'),
                ],
                rows: lines,
                rowColor: (e) => _maxDiscount != null && _n(e['discountPercent']) > _maxDiscount! ? toneColors(context, Tone.warning).$1 : null,
              ),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: InfoGrid([('Produtos', fmtMoney(t['products'])), ('IPI', fmtMoney(t['ipi'])), ('Total', fmtMoney(t['total']))]),
              ),
            ],
          ),
        ),
        gap,
        if (const ['Accepted', 'PurchaseOrder', 'Converted'].contains(q['status']) || q['requestFileName'] != null || '${q['requestText'] ?? ''}'.isNotEmpty) ...[
          _requestSection(q),
          gap,
        ],
        Section(
          title: 'Detalhes',
          child: InfoGrid([
            ('Local de entrega', fmt(q['addressText'])),
            ('Condições gerais', fmt(q['conditions'])),
            ('Observações', fmt(q['notes'])),
            ('Criada', '${fmt(q['createdBy'])} · ${fmtDate(q['createdAt'])}'),
            ('Aprovação interna', q['approvedAt'] == null ? '' : '${fmt(q['approvedBy'])} · ${fmtDate(q['approvedAt'])}'),
            ('Enviada', q['sentAt'] == null ? '' : '${fmt(q['sentTo'])} · ${fmtDate(q['sentAt'])}'),
            ('Resposta do cliente', q['decidedAt'] == null ? '' : '${fmtDate(q['decidedAt'])}${q['decisionNote'] == null ? '' : ' · ${q['decisionNote']}'}'),
          ]),
        ),
      ],
      side: [
        Section(
          title: 'Histórico',
          child: TimelineView(entries: timeline(q['history'] as List)),
        ),
      ],
    );
  }
}
