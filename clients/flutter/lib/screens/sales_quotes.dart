import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../reports/print_docs.dart';
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/actions.dart';
import '../widgets/discard_guard.dart';
import '../widgets/drafts.dart';
import '../widgets/entity_form.dart';
import '../widgets/load_error.dart';
import '../widgets/pipeline.dart';
import '../widgets/print_gate.dart';
import '../widgets/print_panel.dart';
import '../widgets/record_list.dart';
import '../widgets/record_shortcuts.dart';
import '../widgets/record_skeleton.dart';
import '../widgets/responsive.dart';
import '../workdays.dart';
import 'customers.dart';
import 'quote_email_dialog.dart';
import 'quote_pricing.dart';
import 'sales_common.dart';
import 'viability.dart';

// The pure pricing helpers and the e-mail dialog live in their own files; they stay reachable from here for the screens that import this one.
export 'quote_email_dialog.dart';
export 'quote_pricing.dart';

const _requestExtensions = ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'txt'];

/// Lets the user choose the customer's request file (PDF, image or text).
Future<({String name, Uint8List bytes})?> pickRequestFile() async {
  final files = await FilePicker.pickFiles(dialogTitle: 'Anexar arquivo', type: FileType.custom, allowedExtensions: _requestExtensions);
  if (files.isEmpty) return null;
  final f = files.first;
  return (name: f.name, bytes: await f.readAsBytes());
}

/// Item of a quote: the price is always typed, and the lead time is a number of working days counted from the day the customer approves the quote (there is no fixed date yet).
const quoteLineFields = [
  FieldSpec('productId', 'Produto', type: FieldType.lookup, required: true, lookup: LookupSpec('/api/products')),
  FieldSpec('quantity', 'Quantidade', type: FieldType.decimal, required: true, positive: true),
  FieldSpec(
    'unitPrice',
    'Preço unitário (R\$)',
    type: FieldType.decimal,
    required: true,
    min: 0,
    money: true,
    hint: 'Obrigatório. Ao escolher o produto, o preço da tabela do cliente aparece aqui',
  ),
  FieldSpec(
    'leadTimeDays',
    'Prazo de entrega (dias úteis)',
    type: FieldType.integer,
    required: true,
    digitsOnly: true,
    min: 0,
    max: 365,
    hint: 'Dias úteis contados a partir da data em que o cliente aprovar o orçamento',
  ),
  FieldSpec('description', 'Descrição', hint: 'Vazio = descrição do cliente ou do produto'),
];

const salesLineFields = [
  FieldSpec('productId', 'Produto', type: FieldType.lookup, required: true, lookup: LookupSpec('/api/products')),
  FieldSpec('quantity', 'Quantidade', type: FieldType.decimal, required: true, positive: true),
  FieldSpec('unitPrice', 'Preço unitário (R\$)', type: FieldType.decimal, min: 0, money: true, hint: 'Vazio = tabela de preços do cliente'),
  FieldSpec('leadTimeDays', 'Prazo de entrega (dias úteis)', type: FieldType.integer, daysFor: 'deliveryDate', digitsOnly: true, min: 0, max: 365),
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
  const FieldSpec('condition', 'Estado de entrega', type: FieldType.choice, choices: deliveryConditions),
  const FieldSpec('saleUnit', 'Unidade de venda', type: FieldType.choice, choices: saleUnits),
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
  ColumnSpec('Preço unitário', (e) => e['unitPrice'] == null ? 'tabela' : fmtMoney(e['unitPrice']), numeric: true),
  ColumnSpec('IPI %', (e) => fmt(e['ipiPercent']), numeric: true),
  ColumnSpec('Valor estimado', (e) => e['unitPrice'] == null ? '' : fmtMoney(lineEstimate(e)), numeric: true),
  ColumnSpec('Entrega', (e) => e['deliveryDate'] != null ? fmtDay(e['deliveryDate']) : (e['leadTimeDays'] != null ? '${e['leadTimeDays']} dias úteis' : '')),
];

num _n(Object? v) => v is num ? v : 0;

/// Quotes (Orçamentos) list.
class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key, required this.session});

  final Session session;

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

/// Opens the editor of a new quote and then the saved quote. [customer] starts it with that customer (from the customer's own page).
Future<void> newQuote(BuildContext context, Session session, {VoidCallback? onSaved, ({int id, String name})? customer}) async {
  final q = await Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      builder: (_) => QuoteEditorScreen(session: session, customer: customer),
    ),
  );
  onSaved?.call();
  if (q == null || !context.mounted) return;
  await openQuote(context, session, q['id'] as int);
  onSaved?.call();
}

class _QuotesScreenState extends State<QuotesScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _status;
  bool _open = true; // cancelled originals stay listed next to their revisions; untick to see everything
  bool _mine = false;
  bool _followUp = false;
  bool _expiring = false;

  // Only a quote that never reached the customer is "cancelled"; once sent, the outcome is a lost sale, a revision or a new validity.
  static const _cancellable = ['Draft', 'PendingApproval', 'Approved'];

  Future<void> _duplicate(Map<String, dynamic> e) async {
    final r = await runAction(
      context,
      () => widget.session.api.post('/api/sales/quotes/${e['id']}/duplicate', {}),
      success: 'Cópia de ${e['reference']} criada',
    );
    if (r is! Map<String, dynamic> || !mounted) return;
    unawaited(_list.currentState?.reload());
    await openQuote(context, widget.session, r['id'] as int);
    unawaited(_list.currentState?.reload());
  }

  /// Quick cancel from the list: asks for the reason, no need to open the quote.
  Future<void> _cancel(Map<String, dynamic> e) async {
    final reason = await promptText(context, title: 'Cancelar ${e['reference']}', label: 'Motivo (ex.: emitido por engano)', required: true, confirmLabel: 'Cancelar orçamento', danger: true);
    if (reason == null || !mounted) return;
    await runAction(context, () => widget.session.api.post('/api/sales/quotes/${e['id']}/cancel', {'note': reason}), success: '${e['reference']} cancelado');
  }

  Future<void> _new() => newQuote(context, widget.session, onSaved: () => _list.currentState?.reload());

  /// Prints the quote from the list without opening it.
  Future<void> _print(Map<String, dynamic> e) async {
    final api = widget.session.api;
    await printPdf(
      context,
      'Orçamento ${e['reference']}',
      () async => buildQuotePdf(api, await api.get('/api/sales/quotes/${e['id']}') as Map<String, dynamic>),
    );
  }

  /// A row on a phone: who and which quote, the situation and the alerts as chips, then the total and the validity.
  Widget _phoneTile(BuildContext context, Map<String, dynamic> e) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${e['reference']}  ${fmt(e['customerName'])}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            StatusBadge(quoteSituation(e, short: true), tone: quoteToneOf(e)),
            for (final a in quoteAlerts(e)) StatusBadge(a.text, tone: a.tone, icon: a.icon),
          ],
        ),
        const SizedBox(height: 4),
        Text([fmtMoney(e['total']), if (e['validUntil'] != null) 'válida até ${fmtDay(e['validUntil'])}'].join(' · '), style: muted),
      ],
    );
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await confirmStep(
      context,
      title: 'Excluir ${e['reference']}?',
      message: 'O orçamento e o histórico dele somem de vez. Não dá para desfazer.',
      confirmLabel: 'Excluir',
      cancelLabel: 'Voltar',
      danger: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    await runAction(context, () => widget.session.api.delete('/api/sales/quotes/${e['id']}'), success: '${e['reference']} excluído');
    unawaited(_list.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    // "Somente abertas" is how the list starts, so it alone does not count as a filter the user set.
    filtersActive: _status != null || _mine || _followUp || _expiring,
    emptyText: 'Nenhum orçamento aberto.',
    emptyAction: widget.session.canSell
        ? FilledButton.icon(
            key: const ValueKey('empty-new-quote'),
            onPressed: _new,
            icon: const Icon(Icons.add),
            label: const Text('Criar o primeiro orçamento'),
          )
        : null,
    onClearFilters: () => setState(() {
      _open = false;
      _status = null;
      _mine = false;
      _followUp = false;
      _expiring = false;
    }),
    api: widget.session.api,
    path: '/api/sales/quotes',
    query: {
      'status': _status,
      'open': _open && _status == null ? true : null,
      'mine': _mine ? true : null,
      'followUp': _followUp ? true : null,
      'expiring': _expiring ? true : null,
    },
    searchHint: 'Orçamento, cliente ou referência do cliente',
    filters: [
      ChoiceFilter(label: 'Situação', value: _status, choices: quoteStatuses, onChanged: (v) => setState(() => _status = v)),
      // A chosen situation decides what is listed, so "Somente abertas" has nothing left to say.
      FilterChip(
        label: const Text('Somente abertas'),
        selected: _open && _status == null,
        onSelected: _status == null ? (v) => setState(() => _open = v) : null,
      ),
      FilterChip(key: const ValueKey('filter-mine'), label: const Text('Meus orçamentos'), selected: _mine, onSelected: (v) => setState(() => _mine = v)),
      FilterChip(
        key: const ValueKey('filter-follow-up'),
        label: const Text('Cobrar resposta'),
        selected: _followUp,
        onSelected: (v) => setState(() => _followUp = v),
      ),
      FilterChip(
        key: const ValueKey('filter-expiring'),
        label: const Text('Vence em breve'),
        selected: _expiring,
        onSelected: (v) => setState(() => _expiring = v),
      ),
    ],
    fab: widget.session.canSell
        ? FloatingActionButton.extended(heroTag: 'new-quote', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Novo orçamento'))
        : null,
    columns: [
      col('Orçamento', 'reference'),
      col('Cliente', 'customerName'),
      // The alerts ride with the situation: they are what the salesperson has to act on.
      ColumnSpec(
        'Situação',
        (e) => [quoteSituation(e, short: true), quoteAlert(e)].where((t) => t.isNotEmpty).join(' · '),
        cell: (c, e) => Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            StatusBadge(quoteSituation(e, short: true), tone: quoteToneOf(e)),
            for (final a in quoteAlerts(e)) StatusBadge(a.text, tone: a.tone, icon: a.icon),
          ],
        ),
      ),
      moneyCol('Total', 'total'),
      dateCol('Validade', 'validUntil'),
    ],
    phoneTile: _phoneTile,
    rowActions: (e) => [
      RowAction('Imprimir', Icons.print_outlined, () => _print(e)),
      if (widget.session.canSell) ...[
        RowAction('Duplicar', Icons.copy, () => _duplicate(e)),
        if (_cancellable.contains(e['status'])) RowAction('Cancelar', Icons.block, () => _cancel(e)),
        if (canDeleteQuote(widget.session, e['status'], e['revision'] as int? ?? 0)) RowAction('Excluir', Icons.delete_outline, () => _delete(e)),
      ],
    ],
    rowColor: (ctx, e) => e['status'] == 'PendingApproval' ? toneColors(ctx, Tone.warning).$1 : null,
    onTap: (e) async {
      await openQuote(context, widget.session, e['id'] as int);
      unawaited(_list.currentState?.reload());
    },
  );
}

/// Editor for a quote or, with `asOrder`, a sales order: customer, prazo, lines and totals.
class QuoteEditorScreen extends StatefulWidget {
  const QuoteEditorScreen({super.key, required this.session, this.quote, this.asOrder = false, this.customer});

  final Session session;
  final Map<String, dynamic>? quote;
  final bool asOrder;

  /// The customer a new quote starts with (opened from the customer's own page).
  final ({int id, String name})? customer;

  @override
  State<QuoteEditorScreen> createState() => _QuoteEditorScreenState();
}

class _QuoteEditorScreenState extends State<QuoteEditorScreen> {
  late int? _customerId = widget.quote?['customerId'] as int? ?? widget.customer?.id;
  late String? _customerLabel = widget.quote?['customerName'] as String? ?? widget.customer?.name;
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
  String? _errCustomer;
  String? _errTerm;
  String? _errLines;
  bool _busy = false;
  late final String _initial;
  num? _maxDiscount;
  int? _defaultValidity;
  bool _offListApproval = false;
  bool _contactEdited = false;
  bool _recovered = false;
  bool _lockSaved = false;

  /// Bumped when a recovered draft replaces the customer, so the picker shows the recovered name.
  int _restored = 0;
  final _scroll = ScrollController();
  final _customerKey = GlobalKey();
  final _termKey = GlobalKey();
  final _linesKey = GlobalKey();
  final _linesController = LinesEditorController();

  /// What the price table says for each product of the chosen customer (`null` = no entry): its price and taxes.
  final Map<Object, Map<String, dynamic>?> _priceInfo = {};

  String get _draftKey => 'quote-editor:${widget.asOrder ? 'order' : 'quote'}:${widget.quote?['id'] ?? 'new'}';

  num? _listPrice(Object id) {
    final p = _priceInfo[id]?['unitPrice'];
    return p is num ? p : null;
  }

  String _signature() => jsonEncode([
    _customerId,
    _addressId,
    _termId,
    _customTerm,
    _freight,
    _billTo,
    _origin,
    _lines,
    for (final c in [_validity, _contact, _email, _ref, _conditions, _notes, _po, _salesperson]) c.text,
  ]);

  ApiClient get api => widget.session.api;

  /// The session ended under the open editor: what was typed is kept so it can be offered again after signing in.
  void _saveDraft() {
    if (_busy || _signature() == _initial) return;
    _lockSaved = true;
    unawaited(
      DraftStore.save(_draftKey, {
        'customerId': _customerId,
        'customerLabel': _customerLabel,
        'addressId': _addressId,
        'termId': _termId,
        'termName': _termName,
        'customTerm': _customTerm,
        'freight': _freight,
        'billTo': _billTo,
        'origin': _origin,
        'text': {
          'validity': _validity.text,
          'contact': _contact.text,
          'email': _email.text,
          'ref': _ref.text,
          'conditions': _conditions.text,
          'notes': _notes.text,
          'po': _po.text,
          'salesperson': _salesperson.text,
        },
        'lines': _lines,
      }),
    );
  }

  Future<void> _restoreDraft() async {
    final d = await DraftStore.load(_draftKey);
    if (d == null || !mounted) return;
    final text = d['text'];
    final lines = d['lines'];
    setState(() {
      _customerId = d['customerId'] as int?;
      _customerLabel = d['customerLabel'] as String?;
      _addressId = d['addressId'] as int?;
      _termId = d['termId'] as int?;
      _termName = d['termName'] as String?;
      _customTerm = d['customTerm'] as String?;
      _freight = '${d['freight'] ?? _freight}';
      _billTo = '${d['billTo'] ?? _billTo}';
      _origin = '${d['origin'] ?? _origin}';
      if (text is Map) {
        final controllers = {
          'validity': _validity,
          'contact': _contact,
          'email': _email,
          'ref': _ref,
          'conditions': _conditions,
          'notes': _notes,
          'po': _po,
          'salesperson': _salesperson,
        };
        controllers.forEach((k, c) {
          if (text[k] != null) c.text = '${text[k]}';
        });
        _contactEdited = true;
      }
      if (lines is List) _lines = lines.whereType<Map>().map(Map<String, dynamic>.from).toList();
      _restored++;
      _recovered = true;
    });
    if (_customerId != null) unawaited(_loadAddresses(_customerId!, keep: true));
    if (!widget.asOrder) unawaited(_refreshListPrices());
  }

  @override
  void initState() {
    super.initState();
    _initial = _signature();
    DraftRegistry.register(_saveDraft);
    for (final c in [_validity, _contact, _email, _ref, _conditions, _notes, _po, _salesperson]) {
      c.addListener(_clearMessage);
    }
    if (_customerId != null) {
      _loadAddresses(_customerId!, keep: widget.quote != null);
      if (widget.quote == null) _applyDefaultTerm(_customerId!);
    }
    if (!widget.asOrder) {
      api.get('/api/sales/settings').then((r) {
        if (!mounted || r is! Map<String, dynamic>) return;
        setState(() {
          _maxDiscount = r['maxDiscountPercent'] as num?;
          _offListApproval = r['offListNeedsApproval'] == true;
          _defaultValidity = (r['defaultValidityDays'] as num?)?.toInt();
        });
      }, onError: (Object e) => debugPrint('sales_quotes: price lookup failed: $e'));
      _refreshListPrices();
    }
    unawaited(_restoreDraft());
  }

  /// Typing again takes the old error message away.
  void _clearMessage() {
    if (_message != null && mounted) setState(() => _message = null);
  }

  /// Looks up the price table entry of every product of the lines for the chosen customer: it warns about discounts before the quote is sent and fills the taxes a new line does not carry yet.
  Future<void> _refreshListPrices() async {
    final customer = _customerId;
    if (customer == null) return;
    for (final id in {
      for (final l in _lines)
        if (l['productId'] != null) l['productId']!,
    }) {
      await _lookupPrice(id, customer);
      if (!mounted || _customerId != customer) return;
    }
    _fillTaxes();
  }

  Future<void> _lookupPrice(Object id, int customer) async {
    if (_priceInfo.containsKey(id)) return;
    try {
      final r = await api.get('/api/sales/price?productId=$id&customerId=$customer');
      if (!mounted || _customerId != customer) return;
      setState(() => _priceInfo[id] = r is Map<String, dynamic> && r['unitPrice'] is num ? r : null);
    } catch (e) {
      debugPrint('sales_quotes: A failed lookup only hides the warning; the server still enforces the rule when the quote is sent: $e');
      // A failed lookup only hides the warning; the server still enforces the rule when the quote is sent.
    }
  }

  /// A line the user just added has no IPI or ICMS until the quote is saved; show the price table's rates now so the totals match what the server will keep.
  void _fillTaxes() {
    var changed = false;
    final filled = [
      for (final l in _lines)
        () {
          final info = _priceInfo[l['productId']];
          if (info == null) return l;
          final ipi = l['ipiPercent'] == null ? info['ipiPercent'] : null;
          final icms = l['icmsPercent'] == null ? info['icmsPercent'] : null;
          if (ipi == null && icms == null) return l;
          changed = true;
          return {...l, 'ipiPercent': ?ipi, 'icmsPercent': ?icms};
        }(),
    ];
    if (changed && mounted) setState(() => _lines = filled);
  }

  /// Price offered when a product is picked in the line form, from the customer's price table.
  Future<Map<String, Object?>?> _onPick(String key, int? id, Map<String, dynamic>? entity) async {
    final customer = _customerId;
    if (key != 'productId' || id == null || customer == null) return null;
    await _lookupPrice(id, customer);
    final price = _listPrice(id);
    return price == null ? null : {'unitPrice': fmtDecimalInput(price)};
  }

  /// Helper text of the price field: the table price and the discount the typed price makes.
  String? _priceHint(String key, Map<String, dynamic> values) {
    final id = values['productId'];
    if (key != 'unitPrice' || id == null || !_priceInfo.containsKey(id)) return null;
    final list = _listPrice(id);
    if (list == null) return 'Sem preço na tabela deste cliente: digite o preço.';
    final typed = values['unitPrice'];
    final base = 'Tabela: ${fmtMoney(list)}';
    if (typed is! num || list <= 0) return base;
    final d = (1 - typed / list) * 100;
    if (d.abs() < 0.005) return '$base · igual à tabela';
    final pct = fmt(double.parse(d.abs().toStringAsFixed(2)));
    final over = _maxDiscount != null && d > _maxDiscount! ? ' (acima do limite de ${fmt(_maxDiscount)}%: vai para autorização)' : '';
    return '$base · ${d > 0 ? 'desconto' : 'acréscimo'} de $pct%$over';
  }

  /// Discount of a line against the price table, or null when the table has no price to compare with.
  num? _lineDiscount(Map<String, dynamic> l) {
    final id = l['productId'];
    if (id == null) return null;
    return discountPercent(l['unitPrice'], _listPrice(id));
  }

  /// Highest discount against the list price (and which line it is) and how many typed prices have no list price to compare with.
  ({num discount, int line, int offList}) _pricing() => summarizePricing(_lines, hasPriceInfo: _priceInfo.containsKey, listPrice: _listPrice);

  /// "linha 2 (TB-25)" for messages.
  String _lineName(int i) {
    final code = '${(_lines[i]['_labels'] as Map?)?['productId'] ?? ''}'.split(' · ').first;
    return 'linha ${i + 1}${code.isEmpty || code == 'null' ? '' : ' ($code)'}';
  }

  Widget _approvalBanner() {
    final limit = _maxDiscount;
    if (widget.asOrder || limit == null) return const SizedBox.shrink();
    final p = _pricing();
    final String? message = p.discount > limit
        ? 'O maior desconto sobre a tabela é ${fmt(double.parse(p.discount.toStringAsFixed(2)))}% (limite ${fmt(limit)}%), na ${_lineName(p.line)}. O envio vai para a autorização do gerente comercial.'
        : _offListApproval && p.offList > 0
        ? '${p.offList} ${p.offList == 1 ? 'item tem' : 'itens têm'} preço digitado sem preço de tabela para comparar. O envio vai para a autorização do gerente comercial.'
        : null;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: NextStepCard(key: const ValueKey('quote-approval-banner'), title: 'Vai precisar de autorização', message: message, tone: Tone.warning),
    );
  }

  @override
  void dispose() {
    DraftRegistry.unregister(_saveDraft);
    if (!_lockSaved) unawaited(DraftStore.clear(_draftKey));
    for (final c in [_validity, _contact, _email, _ref, _conditions, _notes, _po, _salesperson]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  String? _termName;

  /// Pre-fills the prazo with the customer's default when the user has not picked one yet. [announce]: the customer was just changed, so say what happened to the prazo.
  Future<void> _applyDefaultTerm(int customerId, {bool announce = false}) async {
    if (_termId != null || _customTerm != null) return;
    try {
      final c = await api.get('/api/customers/$customerId') as Map<String, dynamic>;
      final company = c['company'] as Map<String, dynamic>?;
      final termId = company?['paymentTermId'] as int?;
      if (!mounted || _termId != null || _customTerm != null || _customerId != customerId) return;
      if (termId == null) {
        if (announce) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este cliente não tem prazo de pagamento padrão: escolha o prazo.')));
        }
        return;
      }
      setState(() {
        _termId = termId;
        _termName = company?['paymentTermName'] as String?;
        _errTerm = null;
      });
      if (announce) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Prazo de pagamento trocado para o padrão do cliente: ${_termName ?? ''}')));
      }
    } catch (e) {
      debugPrint('sales_quotes: Optional context; the screen works without it: $e');
      // Optional context; the screen works without it.
    }
  }

  /// A new customer brings that customer's own prazo; one the user typed for this quote only stays.
  Future<void> _resetTermFor(int customerId) async {
    final had = _termId != null;
    if (_customTerm == null && had) {
      setState(() {
        _termId = null;
        _termName = null;
      });
    }
    await _applyDefaultTerm(customerId, announce: had && _customTerm == null);
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
        // A new customer brings the contact of the delivery address, unless the user already typed one; no address leaves what was typed.
        if (!keep && first != null && !_contactEdited) {
          _contact.text = '${first['buyer'] ?? ''}';
          _email.text = '${first['email'] ?? ''}';
        }
      });
    } catch (e) {
      debugPrint('sales_quotes: Optional context; the screen works without it: $e');
      // Optional context; the screen works without it.
    }
  }

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  /// Brings the first error into view: the fields it names, or the message at the top.
  void _showFirstError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _errCustomer != null
          ? _customerKey
          : _errTerm != null
          ? _termKey
          : _errLines != null
          ? _linesKey
          : null;
      final ctx = target?.currentContext;
      if (ctx != null) {
        unawaited(Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.1));
      } else if (_scroll.hasClients) {
        unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
      }
    });
  }

  Future<void> _save() async {
    final customer = _customerId == null ? 'Informe o cliente' : null;
    final term = _termId == null && _customTerm == null ? 'Informe o prazo' : null;
    final lines = _lines.isEmpty ? 'Inclua ao menos um item' : null;
    final address = widget.asOrder && _addressId == null ? 'O cliente precisa de um endereço de entrega cadastrado' : null;
    if (customer != null || term != null || lines != null || address != null) {
      setState(() {
        _errCustomer = customer;
        _errTerm = term;
        _errLines = lines;
        _message = address;
      });
      _showFirstError();
      return;
    }
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
      _lockSaved = false;
      if (mounted) Navigator.pop(context, q);
    } on ApiException catch (e) {
      setState(() => _message = describeError(e));
      _showFirstError();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label, {String? hint, String? helper}) =>
      InputDecoration(labelText: label, hintText: hint, helperText: helper, border: const OutlineInputBorder(), isDense: true);

  /// Customer, delivery, terms and notes fields; an order shows its PO and billing fields, a quote its contact and validity.
  Widget _conditionsSection({required bool wide, required double w}) => Section(
    title: 'Cliente e condições',
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _customerField(w),
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
            onChanged: (v) => setState(() {
              _addressId = v;
              // The contact follows the address, unless the user typed one.
              final a = _addresses.where((x) => x['id'] == v).firstOrNull;
              if (a != null && !_contactEdited) {
                _contact.text = '${a['buyer'] ?? ''}';
                _email.text = '${a['email'] ?? ''}';
              }
            }),
          ),
        ),
        _termField(w),
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
        if (widget.asOrder) ..._orderFields(w),
        if (!widget.asOrder) ..._quoteFields(wide, w),
        SizedBox(
          width: wide ? 612 : w,
          child: TextField(controller: _notes, maxLines: 3, minLines: 1, decoration: _dec('Observações')),
        ),
      ],
    ),
  );

  /// Customer picker; an order keeps its customer, a draft quote can change it.
  Widget _customerField(double w) => SizedBox(
    key: _customerKey,
    width: w,
    child: LookupField(
      key: _restored == 0 ? const ValueKey('quote-customer') : ValueKey('quote-customer-$_restored'),
      api: api,
      spec: const LookupSpec('/api/customers'),
      label: 'Cliente *',
      value: _customerId,
      error: _errCustomer,
      initialDisplay: _customerLabel,
      enabled: widget.quote == null || !widget.asOrder, // an order keeps its customer; a draft quote can change it
      onChanged: (id, entity) {
        final changed = id != _customerId;
        setState(() {
          _customerId = id;
          _customerLabel = entity == null ? null : LookupSpec.display(entity);
          _errCustomer = null;
          _addresses = [];
          _addressId = null;
          _priceInfo.clear();
          if (changed) {
            _contactEdited = false;
            _contact.text = '';
            _email.text = '';
          }
        });
        if (id != null) {
          _loadAddresses(id);
          if (changed) {
            unawaited(_resetTermFor(id));
          } else {
            _applyDefaultTerm(id);
          }
          if (!widget.asOrder) _refreshListPrices();
        }
      },
    ),
  );

  /// Prazo picker: a registered term or a custom text typed by the user.
  Widget _termField(double w) => SizedBox(
    key: _termKey,
    width: w,
    child: _customTerm != null && _termId == null
        ? InputDecorator(
            key: const ValueKey('quote-custom-term'),
            decoration: InputDecoration(
              labelText: 'Prazo de pagamento * (personalizado)',
              errorText: _errTerm,
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(tooltip: 'Escolher outro prazo', icon: const Icon(Icons.clear), onPressed: () => setState(() => _customTerm = null)),
            ),
            child: Text(_customTerm!, overflow: TextOverflow.ellipsis),
          )
        : LookupField(
            key: ValueKey('quote-term-$_termId'),
            api: api,
            spec: const LookupSpec('/api/sales/payment-terms'),
            label: 'Prazo de pagamento *',
            value: _termId,
            error: _errTerm,
            initialDisplay: _termName ?? widget.quote?['paymentTermName'] as String?,
            onChanged: (id, _) => setState(() {
              _termId = id;
              _termName = null;
              _errTerm = null;
              if (id != null) _customTerm = null;
            }),
            onCustom: (text) => setState(() {
              _termId = null;
              _customTerm = text;
              _errTerm = null;
            }),
          ),
  );

  /// Fields exclusive to a sales order: customer PO, billing, origin and salesperson.
  List<Widget> _orderFields(double w) => [
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
  ];

  /// What the validity field says below it: the default when empty, the end date when typed.
  String _validityHelp() {
    final n = int.tryParse(_validity.text.trim());
    if (n == null) return _defaultValidity == null ? 'Vazio = padrão dos parâmetros' : 'Vazio = padrão: $_defaultValidity dias';
    final end = DateTime.now().add(Duration(days: n));
    return 'Vale até ${fmtDay(isoDate(end))} se enviado hoje';
  }

  /// Fields exclusive to a quote: validity, contact, reference and general conditions.
  List<Widget> _quoteFields(bool wide, double w) => [
    SizedBox(
      width: wide ? 230 : w,
      child: TextField(
        key: const ValueKey('quote-validity'),
        controller: _validity,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _dec('Validade (dias)', hint: _defaultValidity == null ? 'padrão' : 'padrão: $_defaultValidity', helper: _validityHelp()),
        onChanged: (_) => setState(() {}),
      ),
    ),
    SizedBox(
      width: w,
      child: TextField(controller: _contact, decoration: _dec('Contato (A/C)'), onChanged: (_) => _contactEdited = true),
    ),
    SizedBox(
      width: w,
      child: TextField(key: const ValueKey('quote-email'), controller: _email, decoration: _dec('E-mail do contato'), onChanged: (_) => _contactEdited = true),
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
  ];

  /// Quote lines with the price table's price and the discount against it.
  List<ColumnSpec> get _quoteColumns => [
    ...salesLineColumns,
    ColumnSpec('Tabela / Desc.', (e) {
      final id = e['productId'];
      if (id == null || !_priceInfo.containsKey(id)) return '';
      final list = _listPrice(id);
      if (list == null) return 'sem tabela';
      final d = _lineDiscount(e);
      if (d == null) return fmtMoney(list);
      final shown = d.abs() < 0.005 ? '0%' : '${d > 0 ? '' : '+'}${fmt(double.parse((d > 0 ? d : -d).toStringAsFixed(2)))}%';
      final over = _maxDiscount != null && d > _maxDiscount! ? ' ⚠' : '';
      return '${fmtMoney(list)} / $shown$over';
    }, numeric: true),
  ];

  Color? _lineColor(Map<String, dynamic> l) {
    final d = _lineDiscount(l);
    return d != null && _maxDiscount != null && d > _maxDiscount! ? toneColors(context, Tone.warning).$1 : null;
  }

  Widget _total(String label, String value, {bool strong = false, Key? key}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      Text(
        value,
        key: key,
        style: (strong ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyMedium)?.copyWith(
          fontWeight: strong ? FontWeight.w700 : null,
        ),
      ),
    ],
  );

  /// Totals and the save button, always in view while the lines are edited. The printed total is products + IPI; the ICMS is shown as an estimate.
  Widget _bottomBar(({num products, num ipi, num icms}) parts, bool wide) {
    final save = FilledButton.icon(
      key: const ValueKey('quote-save'),
      onPressed: _busy ? null : _save,
      icon: const Icon(Icons.check),
      label: Text(widget.asOrder ? 'Salvar pedido' : 'Salvar orçamento'),
    );
    final totals = Wrap(
      spacing: 24,
      runSpacing: 4,
      children: [
        _total('Produtos', fmtMoney(parts.products)),
        _total('IPI', fmtMoney(parts.ipi)),
        if (parts.icms > 0) _total('ICMS (estimativa)', fmtMoney(parts.icms)),
        _total(widget.asOrder ? 'Total do pedido' : 'Total do orçamento', fmtMoney(parts.products + parts.ipi), strong: true, key: const ValueKey('quote-estimate')),
      ],
    );
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: wide
              ? Row(
                  children: [
                    Expanded(child: totals),
                    const SizedBox(width: 12),
                    save,
                  ],
                )
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [totals, const SizedBox(height: 8), save]),
        ),
      ),
    );
  }

  Widget _banner(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      liveRegion: true,
      child: Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final parts = estimateParts(_lines);
    // The layout follows the room the page is given (it can sit beside the sidebar), not the window.
    return LayoutBuilder(builder: (context, box) => _editorPage(context, parts, wide: box.maxWidth >= 700));
  }

  Widget _editorPage(BuildContext context, ({num products, num ipi, num icms}) parts, {required bool wide}) {
    final w = wide ? 300.0 : double.infinity;
    return DiscardGuard(
      isDirty: () => _signature() != _initial,
      child: CallbackShortcuts(
        // Ctrl+S saves, Ctrl+I adds an item.
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _busy ? null : unawaited(_save()),
          const SingleActivator(LogicalKeyboardKey.keyI, control: true): _linesController.add,
        },
        // Something in the page has to hold the focus for the shortcuts to hear a key pressed before any field is touched.
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.quote != null ? 'Editar ${widget.quote!['reference']}' : (widget.asOrder ? 'Novo pedido de venda' : 'Novo orçamento')),
            ),
            bottomNavigationBar: _bottomBar(parts, wide),
            body: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                if (_recovered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.restore, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Rascunho recuperado: nada foi salvo ainda.', style: Theme.of(context).textTheme.bodySmall)),
                      ],
                    ),
                  ),
                if (_message != null) _banner(_message!),
                _conditionsSection(wide: wide, w: w),
                gap,
                KeyedSubtree(
                  key: _linesKey,
                  child: LinesEditor(
                    controller: _linesController,
                    api: api,
                    title: 'Itens',
                    fields: widget.asOrder ? orderLineFields : quoteLineFields,
                    newTitle: widget.asOrder ? 'Nova linha' : 'Novo item',
                    addLabel: widget.asOrder ? 'Adicionar linha' : 'Adicionar item',
                    submitLabel: widget.asOrder ? 'Adicionar linha' : 'Adicionar item',
                    addAnotherLabel: 'Adicionar e novo',
                    carryKeys: const ['leadTimeDays'],
                    duplicateKey: 'productId',
                    staleOnChange: const {
                      'productId': ['ipiPercent', 'icmsPercent', 'description', 'feasibilityId'],
                    },
                    addEnabled: widget.asOrder || (_customerId != null && (_termId != null || _customTerm != null)),
                    disabledHint: 'Escolha o cliente e o prazo de pagamento para adicionar itens',
                    editTitle: widget.asOrder ? null : 'Editar item',
                    lines: _lines,
                    onPick: widget.asOrder ? null : _onPick,
                    hintFor: widget.asOrder ? null : _priceHint,
                    rowColor: widget.asOrder ? null : _lineColor,
                    onChanged: (l) {
                      setState(() {
                        _lines = l;
                        _errLines = null;
                      });
                      if (!widget.asOrder) _refreshListPrices();
                    },
                    columns: widget.asOrder ? orderLineColumns : _quoteColumns,
                  ),
                ),
                if (_errLines != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(_errLines!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                _approvalBanner(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quote detail: outcomes (approve, revise, decline), purchase order step, conversion to order and printing.
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
    }, onError: (Object e) => debugPrint('sales_quotes: sales settings lookup failed: $e'));
    api.get('/api/system/mail').then((r) {
      if (mounted && r is Map<String, dynamic>) {
        setState(() {
          _mailOn = r['enabled'] == true;
          _mailFrom = r['from'] as String?;
        });
      }
    }, onError: (Object e) => debugPrint('sales_quotes: mail status lookup failed, the e-mail button stays hidden: $e'));
  }

  /// Whether the server can send e-mail (SMTP set up in .env); without it only "Registrar envio" is offered.
  bool _mailOn = false;
  String? _mailFrom;

  Map<String, dynamic>? _credit;

  /// The sales order a converted quote became, for the card that says where it stands.
  Map<String, dynamic>? _order;

  Future<void> _load() async {
    try {
      final q = await api.get(base) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _q = q;
          _error = null;
        });
        unawaited(_loadCredit(q));
        unawaited(_loadOrder(q));
      }
    } catch (e) {
      if (!mounted) return;
      if (_q == null) {
        setState(() => _error = friendlyError(e));
      } else {
        // The page keeps what it has; say that it is not up to date.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao atualizar: ${friendlyError(e)}')));
      }
    }
  }

  /// The order of a converted quote (optional context: the card falls back to a plain sentence without it).
  Future<void> _loadOrder(Map<String, dynamic> q) async {
    if (q['status'] != 'Converted' || q['salesOrderId'] == null) {
      if (_order != null && mounted) setState(() => _order = null);
      return;
    }
    try {
      final o = await api.get('/api/sales/orders/${q['salesOrderId']}');
      if (mounted && o is Map<String, dynamic>) setState(() => _order = o);
    } catch (e) {
      debugPrint('sales_quotes: Optional context; the card works without it: $e');
    }
  }

  /// Soft credit warning while the quote can still become an order; the hard check stays at "Gerar pedido de venda".
  Future<void> _loadCredit(Map<String, dynamic> q) async {
    if (!_openStatuses.contains(q['status'])) {
      if (_credit != null) setState(() => _credit = null);
      return;
    }
    try {
      final c = await api.get('$base/credit');
      if (mounted && c is Map<String, dynamic>) setState(() => _credit = c);
    } catch (e) {
      debugPrint('sales_quotes: Optional context; the screen works without it: $e');
      // Optional context; the screen works without it.
    }
  }

  static const _openStatuses = ['Draft', 'PendingApproval', 'Approved', 'Sent', 'Accepted', 'PurchaseOrder'];

  Widget _creditBanner() {
    final c = _credit;
    if (c == null || c['exceeded'] != true) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NextStepCard(
        key: const ValueKey('quote-credit-banner'),
        title: 'Limite de crédito',
        message:
            'Pedidos em aberto ${fmtMoney(c['open'])} + a receber ${fmtMoney(c['receivable'] ?? 0)} + este orçamento ${fmtMoney(c['thisOrder'])} passam do limite de ${fmtMoney(c['limit'])} ${c['limitSource'] == 'customer' ? 'do cliente' : 'do prazo'}. '
            'O pedido de venda só sai com liberação do gerente comercial.',
        tone: Tone.warning,
      ),
    );
  }

  Future<void> _act(String action, {Map<String, dynamic> body = const {}, String? success}) async {
    final r = await runAction(context, () => api.post('$base/$action', body), success: success);
    if (r is Map<String, dynamic> && mounted) setState(() => _q = r);
  }

  Future<void> _send() async {
    final q = _q!;
    if (q['status'] == 'Draft' && q['needsApproval'] == true) {
      final ok = await confirmStep(
        context,
        title: 'Enviar para autorização?',
        message:
            'O desconto deste orçamento (${fmt(q['totals']['maxDiscountPercent'])}%) passa do limite de ${fmt(_maxDiscount)}%. Ele vai para o gerente comercial autorizar antes de seguir ao cliente.',
        confirmLabel: 'Enviar para autorização',
        icon: Icons.verified_user_outlined,
      );
      if (ok && mounted) await _act('send', success: 'Enviada para autorização do gerente');
      return;
    }
    // This step records that the quote went to the customer; the system sends nothing. The dialog and the message say so.
    final r = await submitForm(
      context,
      api: api,
      title: 'Registrar envio de ${q['reference']} ao cliente',
      fields: [
        FieldSpec(
          'sentTo',
          'Enviado para (contato ou e-mail)',
          required: true,
          defaultValue: q['contactEmail'] ?? q['contactName'],
          hint: 'O e-mail não sai daqui: baixe o PDF e envie pelo seu programa de e-mail',
        ),
        const FieldSpec('note', 'Observação'),
      ],
      submit: (b) => api.post('$base/send', b),
    );
    if (!mounted) return;
    if (r != null && r['reference'] != null) {
      setState(() => _q = r);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Envio registrado · válido até ${fmtDay(r['validUntil'])}. O sistema não envia o e-mail: baixe o PDF e abra o e-mail para enviá-lo.'),
          duration: const Duration(seconds: 10),
          persist: false, // a snackbar with an action stays until dismissed unless told otherwise
          action: SnackBarAction(label: 'Abrir e-mail', onPressed: _mail),
        ),
      );
    }
  }

  /// The quote as a file to attach to an e-mail: saved through the system dialog on a computer, handed to the share sheet on a phone.
  Future<void> _downloadPdf() async {
    final q = _q;
    if (q == null) return;
    final name = 'Orçamento ${q['reference']}';
    final phone = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    if (!phone) {
      await savePdf(context, '$name.pdf', () => buildQuotePdf(api, q));
      return;
    }
    try {
      await Printing.sharePdf(bytes: await buildQuotePdf(api, q), filename: '$name.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao gerar o PDF: ${friendlyError(e)}')));
    }
  }

  Future<void> _printQuote() async {
    final q = _q;
    if (q == null) return;
    await printPdf(context, 'Orçamento ${q['reference']}', () => buildQuotePdf(api, q));
  }

  String _mailSubject(Map<String, dynamic> q) => '${q['reference']} · EBT';

  String _mailBody(Map<String, dynamic> q) =>
      'Prezados,\n\nSegue em anexo o orçamento ${q['reference']}${q['validUntil'] == null ? '' : ', válido até ${fmtDay(q['validUntil'])}'}.\n\nAtenciosamente,';

  /// Sends the quote PDF from the company mailbox (SMTP on the server). A draft or approved quote is registered as sent at the same time;
  /// a quote already sent is just mailed again.
  Future<void> _emailQuote() async {
    final q = _q;
    if (q == null) return;
    final registers = q['status'] != 'Sent';
    Map<String, dynamic>? sent;
    // The dialog stays open, with its button busy, while the PDF is built and posted; a failure leaves it open for another try.
    final form = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (c) => QuoteEmailDialog(
        to: '${q['sentTo'] ?? q['contactEmail'] ?? ''}'.trim(),
        subject: _mailSubject(q),
        body: _mailBody(q),
        from: _mailFrom,
        fileName: 'Orçamento ${q['reference']}.pdf',
        registers: registers,
        onSend: (form) async {
          final r = await runAction(
            c,
            () async {
              final pdf = await buildQuotePdf(api, q);
              return api.post('$base/email', {...form, 'pdfBase64': base64Encode(pdf), 'fileName': 'Orçamento ${q['reference']}.pdf'});
            },
            success: registers ? 'E-mail enviado e envio registrado' : 'E-mail enviado',
          );
          if (r is Map<String, dynamic>) sent = r;
          return r is Map<String, dynamic>;
        },
      ),
    );
    final r = sent;
    if (form == null || r == null || !mounted) return;
    setState(() => _q = r);
    unawaited(_load());
  }

  /// Opens the user's mail program with the recipient, subject and text filled in. The PDF still has to be attached (print/share button).
  Future<void> _mail() async {
    final q = _q;
    if (q == null) return;
    final to = '${q['sentTo'] ?? q['contactEmail'] ?? ''}'.trim();
    final subject = _mailSubject(q);
    final body = _mailBody(q);
    final uri = Uri.parse(
      'mailto:${to.contains('@') ? Uri.encodeComponent(to) : ''}?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (e) {
      debugPrint('sales_quotes: Optional context; the screen works without it: $e');
      // Optional context; the screen works without it.
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum programa de e-mail configurado neste computador')));
    }
  }

  /// The sale is lost. [gaveUp]: the customer had already approved or ordered and dropped it afterwards.
  /// The category feeds the lost-reasons report, the note stays in the history.
  Future<void> _decline({bool gaveUp = false}) async {
    final r = await submitForm(
      context,
      api: api,
      title: gaveUp ? 'Cliente desistiu de ${_q!['reference']}' : 'Venda perdida: cliente recusou ${_q!['reference']}',
      fields: [
        FieldSpec(
          'lostReason',
          'Motivo principal',
          type: FieldType.choice,
          required: true,
          choices: gaveUp ? lostReasons : {for (final e in lostReasons.entries) if (e.key != 'CustomerGaveUp') e.key: e.value},
          defaultValue: gaveUp ? 'CustomerGaveUp' : null,
        ),
        const FieldSpec('note', 'Detalhes', required: true, hint: 'O que o cliente disse. O orçamento fica como Perdida e o motivo entra no relatório de vendas perdidas'),
      ],
      submit: (b) => api.post('$base/decline', b),
    );
    if (!mounted) return;
    if (r != null && r['reference'] != null) {
      setState(() => _q = r);
      unawaited(_loadCredit(r));
    }
  }

  /// Back to draft so a quote that is waiting for (or holds) the manager's approval can be edited; no new revision is created.
  Future<void> _reopen() async {
    final ok = await confirmStep(
      context,
      title: 'Voltar para rascunho?',
      message:
          'A autorização do gerente é descartada e você pode editar os itens e preços. Depois envie de novo; se o desconto continuar acima do limite, o gerente autoriza outra vez.',
      confirmLabel: 'Voltar para rascunho',
      cancelLabel: 'Manter como está',
      icon: Icons.edit_outlined,
    );
    if (ok && mounted) await _act('reopen', success: 'Orçamento voltou para rascunho');
  }

  /// Gives a quote that is still with the customer more time; an expired one becomes "Enviada" again with the new date.
  Future<void> _extend() async {
    final q = _q!;
    final current = DateTime.tryParse('${q['validUntil'] ?? ''}');
    final today = DateTime.now();
    final base0 = current != null && current.isAfter(today) ? current : today;
    final r = await submitForm(
      context,
      api: api,
      title: 'Prorrogar validade de ${q['reference']}',
      fields: [
        FieldSpec('validUntil', 'Nova validade', type: FieldType.date, required: true, defaultValue: isoDate(DateTime(base0.year, base0.month, base0.day + 15))),
        const FieldSpec('note', 'Motivo', hint: 'Ex.: cliente pediu mais prazo para decidir'),
      ],
      submit: (b) => api.post('$base/extend', b),
    );
    if (!mounted) return;
    if (r != null && r['reference'] != null) {
      setState(() => _q = r);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Validade até ${fmtDay(r['validUntil'])}')));
    }
  }

  /// New draft with the same items; leave the customer empty to keep this one.
  Future<void> _duplicate() async {
    final q = _q!;
    final r = await submitForm(
      context,
      api: api,
      title: 'Duplicar ${q['reference']}',
      fields: const [
        FieldSpec('customerId', 'Outro cliente (opcional)', type: FieldType.lookup, lookup: LookupSpec('/api/customers'), hint: 'Vazio = mesmo cliente'),
      ],
      submit: (b) => api.post('$base/duplicate', b),
    );
    if (r == null || r['id'] == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${r['reference']} criado como cópia de ${q['reference']}')));
    await openQuote(context, s, r['id'] as int);
    if (mounted) unawaited(_load());
  }

  /// "Pedido de compra" step: the customer's PO (file and/or text) must be attached before the quote moves on.
  Future<void> _receivePo() async {
    final q = _q!;
    if ('${q['requestText'] ?? ''}'.trim().isEmpty && q['requestFileName'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anexe o arquivo ou o texto do pedido de compra antes de registrá-lo')));
      return;
    }
    final proceed = await printGate(
      context,
      doneKey: 'quote:${q['id']}:po',
      title: 'Imprimir o pedido de compra do cliente?',
      message: 'Antes de registrar, imprima ou baixe o pedido de compra que o cliente enviou. Você também encontra todos os documentos no pedido de venda.',
      onPrint: _printRequest,
      onDownload: q['requestFileName'] == null ? null : _saveRequest,
    );
    if (!proceed || !mounted) return;
    await _submitPurchaseOrder(q);
  }

  Future<void> _submitPurchaseOrder(Map<String, dynamic> q) async {
    final lines = (q['lines'] as List).cast<Map<String, dynamic>>();
    final approved = DateTime.tryParse('${q['decidedAt'] ?? ''}')?.toLocal() ?? DateTime.now();
    // Our delivery date: the lead time in working days counted from the day the customer approved the quote.
    String ours(Map<String, dynamic> l) => l['leadTimeDays'] is! int ? '' : isoDate(addWorkDays(DateTime(approved.year, approved.month, approved.day), l['leadTimeDays'] as int));
    // A date counts as the customer's when it differs from what the item has now (its saved date, else ours).
    bool changed(Map<String, dynamic> l, Object? chosen) => '$chosen'.isNotEmpty && chosen != null && chosen != (l['deliveryDate'] ?? ours(l));
    final r = await submitForm(
      context,
      api: api,
      title: 'Pedido de compra de ${q['reference']}',
      fields: [
        FieldSpec('customerPo', 'Nº do pedido de compra do cliente', defaultValue: q['customerPo']),
        for (final l in lines)
          FieldSpec(
            'line-${l['id']}',
            'Item ${l['sequence']} · data de entrega',
            type: FieldType.date,
            defaultValue: l['deliveryDate'] ?? (ours(l).isEmpty ? null : ours(l)),
            hint: ours(l).isEmpty
                ? 'Sem prazo em dias úteis: informe a data'
                : 'Nossa data: ${fmtDay(ours(l))} (${l['leadTimeDays']} dias úteis após a aprovação). Se o pedido do cliente traz outra data, use a dele.',
          ),
        const FieldSpec('note', 'Observação'),
      ],
      submit: (b) => api.post('$base/purchase-order', {
        'customerPo': b['customerPo'],
        'note': b['note'],
        // Only dates that differ from ours are sent: the customer's date wins, ours stays as working days.
        'deliveryDates': [
          for (final l in lines)
            if (changed(l, b['line-${l['id']}'])) {'lineId': l['id'], 'deliveryDate': b['line-${l['id']}'] == ours(l) ? null : b['line-${l['id']}']},
        ],
      }),
    );
    if (!mounted) return;
    if (r != null && r['reference'] != null) {
      setState(() => _q = r);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Pedido de compra registrado'),
          duration: const Duration(seconds: 12),
          persist: false,
          action: s.canSell ? SnackBarAction(label: 'Gerar pedido de venda', onPressed: _convert) : null,
        ),
      );
    }
  }

  /// The customer's approval starts the delivery-time clock (working days count from today), so it is confirmed with the date it will carry.
  Future<void> _accept() async {
    final ok = await confirmStep(
      context,
      title: 'Cliente aprovou ${_q!['reference']}?',
      message: 'Registra a aprovação do cliente em ${fmtDay(isoDate(DateTime.now()))}. Os prazos de entrega em dias úteis passam a contar a partir de hoje.',
      confirmLabel: 'Registrar aprovação',
      icon: Icons.thumb_up_alt_outlined,
    );
    if (!ok || !mounted) return;
    final r = await runAction(context, () => api.post('$base/accept', {}), success: 'Aprovação do cliente registrada');
    if (r is Map<String, dynamic> && mounted) setState(() => _q = r);
  }

  Future<void> _setRequestText() async {
    final text = await promptText(
      context,
      title: 'Texto do pedido de compra',
      label: 'Texto do pedido de compra',
      initial: '${_q?['requestText'] ?? ''}',
      confirmLabel: 'Salvar',
    );
    if (text == null || !mounted) return;
    final r = await runAction(context, () => api.put('$base/request', {'text': text}));
    if (r is Map<String, dynamic> && mounted) setState(() => _q = r);
  }

  Future<void> _attachRequest() async {
    final f = await pickRequestFile();
    if (f == null || !mounted) return;
    final r = await runAction(context, () => api.upload('$base/request-file', 'file', f.name, f.bytes), success: 'Arquivo anexado');
    if (r is Map<String, dynamic> && mounted) setState(() => _q = r);
  }

  Future<void> _removeRequest() async {
    final r = await runAction(context, () => api.delete('$base/request-file'), success: 'Anexo removido');
    if (r is Map<String, dynamic> && mounted) setState(() => _q = r);
  }

  Future<bool> _printRequest() async {
    final q = _q!;
    try {
      final fileName = q['requestFileName'] as String?;
      final bytes = await customerOrderPdf(
        fileName: fileName,
        file: fileName == null ? null : await api.download('$base/request-file'),
        text: q['requestText'] as String?,
        title: 'Pedido de compra do cliente ${q['reference']}',
      );
      if (!mounted) return false;
      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este tipo de arquivo não imprime daqui. Baixe-o e imprima pelo programa que o abre.')));
        return false;
      }
      return await printPdf(context, 'Pedido de compra ${q['reference']}', () async => bytes, doneKey: 'quote:${q['id']}:po');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao imprimir: ${friendlyError(e)}')));
      return false;
    }
  }

  Future<void> _saveRequest() async {
    try {
      final bytes = await api.download('$base/request-file');
      final saved = await FilePicker.saveFile(fileName: '${_q!['requestFileName']}', bytes: bytes, dialogTitle: 'Salvar pedido de compra');
      if (saved != null) await PrintLog.mark('quote:${_q!['id']}:po');
      if (saved != null && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Arquivo salvo')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha: ${friendlyError(e)}')));
    }
  }

  Future<void> _reason(String action, String title, {String label = 'Motivo', String? success, String? confirmLabel, bool danger = false}) async {
    final reason = await promptText(context, title: title, label: label, required: true, confirmLabel: confirmLabel ?? title, danger: danger);
    if (reason == null || !mounted) return;
    await _act(action, body: {'note': reason}, success: success);
  }

  /// New revision: this version stays for reference as "Substituída" and a draft with the same client, items and prazo opens to be changed.
  Future<void> _revise() async {
    final q = _q!;
    final r = await submitForm(
      context,
      api: api,
      title: 'Nova revisão de ${q['reference']}',
      fields: [
        const FieldSpec('change', 'Motivo da revisão', type: FieldType.choice, required: true, choices: revisionReasons),
        const FieldSpec(
          'note',
          'Detalhes',
          required: true,
          hint: 'Esta versão passa a Substituída (só consulta). A nova revisão abre em rascunho com os mesmos itens para você alterar',
        ),
        FieldSpec('customerPo', 'Pedido de compra do cliente', defaultValue: q['customerPo'], hint: 'Mantenha o mesmo ou informe outro'),
      ],
      submit: (b) => api.post('$base/revise', {'note': '${revisionReasons[b['change']] ?? b['change']}: ${b['note']}', 'customerPo': b['customerPo']}),
    );
    if (r == null || r['id'] == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${q['reference']} substituída · nova revisão ${r['reference']} em rascunho')));
    await _load();
    if (mounted) await replaceWithQuote(context, s, r['id'] as int);
    if (mounted) unawaited(_load());
  }

  /// Fresh answer to "does this quote pass the customer's credit limit?" (false when it cannot be asked).
  Future<bool> _creditExceeded() async {
    try {
      final c = await api.get('$base/credit');
      return c is Map<String, dynamic> && c['exceeded'] == true;
    } catch (e) {
      debugPrint('sales_quotes: The override flow is offered only when the limit is confirmed: $e');
      return false;
    }
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
      // A 409 is not always the credit limit: ask the server whether it is, instead of reading its message.
      final credit = e.status == 409 && s.canApproveSales && await _creditExceeded();
      if (!mounted) return;
      if (credit) {
        final force = await confirmStep(
          context,
          title: 'Limite de crédito excedido',
          message: '${e.message}\n\nLiberar mesmo assim? A liberação fica registrada no histórico.',
          confirmLabel: 'Liberar e gerar',
          cancelLabel: 'Voltar',
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
    if (mounted) await replaceWithSalesOrder(context, s, order['id'] as int);
    unawaited(_load());
  }

  Future<void> _edit() async {
    final r = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => QuoteEditorScreen(session: s, quote: _q),
      ),
    );
    if (r != null) {
      if (!mounted) return;
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
          cancelLabel: 'Voltar',
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
      ..writeln('Prazo de pagamento: ${q['paymentTermName'] ?? q['customPaymentTerm'] ?? 'a combinar'} · Frete: ${freightTerms[q['freight']] ?? q['freight']}')
      ..writeln()
      ..writeln('Item  Produto  Descrição  Qtd  Un  Vl. unit.  IPI%  Vl. total  Entrega');
    for (final l in (q['lines'] as List).cast<Map<String, dynamic>>()) {
      b.writeln(
        '${l['sequence']}  ${l['customerPartNumber'] ?? l['productCode']}  ${l['description']}  ${fmt(l['quantity'])}  ${l['unit']}  ${fmtNum(l['unitPrice'], 4)}  ${fmt(l['ipiPercent'])}  ${fmtNum(l['total'])}  ${l['deliveryDate'] != null ? fmtDay(l['deliveryDate']) : (l['leadTimeDays'] != null ? '${l['leadTimeDays']} dias úteis' : '')}',
      );
    }
    final t = q['totals'] as Map<String, dynamic>;
    b
      ..writeln()
      ..writeln('Total dos produtos: ${fmtMoney(t['products'])}')
      ..writeln('IPI: ${fmtMoney(t['ipi'])}')
      ..writeln('Total do orçamento: ${fmtMoney(t['total'])}')
      ..writeln()
      ..writeln('Prazo de entrega: dias úteis a partir da aprovação do orçamento pelo cliente.')
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
        if (canEdit)
          TextButton.icon(
            key: const ValueKey('quote-po-text'),
            onPressed: _setRequestText,
            icon: const Icon(Icons.edit_note),
            label: const Text('Texto do pedido'),
          ),
        if (canEdit)
          TextButton.icon(
            key: const ValueKey('quote-po-attach'),
            onPressed: _attachRequest,
            icon: const Icon(Icons.attach_file),
            label: Text(fileName == null ? 'Anexar arquivo' : 'Substituir arquivo'),
          ),
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
                Expanded(child: Text('$fileName · ${fmtFileSize(q['requestFileSize'])}', overflow: TextOverflow.ellipsis)),
                TextButton.icon(key: const ValueKey('quote-po-print'), onPressed: _printRequest, icon: const Icon(Icons.print_outlined), label: const Text('Imprimir')),
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
        content: DialogBody(
          ideal: 720,
          child: SingleChildScrollView(
            child: SelectableText(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
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

  static const _reviseTip = 'Altera itens ou preço. Esta versão fica como Substituída (só consulta) e uma nova revisão abre em rascunho.';

  /// "Enviada em 30/10/2026 10:20", plus the recipient only when it is not the quote's own contact (shown once, in the header).
  String _sentMessage(Map<String, dynamic> q) {
    final sentTo = '${q['sentTo'] ?? ''}'.trim();
    final contact = '${q['contactEmail'] ?? ''}'.trim();
    final to = sentTo.isEmpty || sentTo == contact ? '' : ' para $sentTo';
    return 'Enviada$to em ${fmtDate(q['sentAt'])}.';
  }

  /// Detalhes: when it was sent; the address is added only when it differs from the quote's contact.
  String _sentDetail(Map<String, dynamic> q) {
    final sentTo = '${q['sentTo'] ?? ''}'.trim();
    final contact = '${q['contactEmail'] ?? ''}'.trim();
    return sentTo.isEmpty || sentTo == contact ? fmtDate(q['sentAt']) : '$sentTo · ${fmtDate(q['sentAt'])}';
  }

  /// Days left on a quote that is out with the customer: calm while there is time, amber in the last 3 days, red once it has passed.
  Widget? _validityBadge(Map<String, dynamic> q) {
    final until = DateTime.tryParse('${q['validUntil'] ?? ''}');
    if (until == null) return null;
    final now = DateTime.now();
    final days = DateTime(until.year, until.month, until.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final (label, tone) = days < 0
        ? ('Vencida há ${-days} ${-days == 1 ? 'dia' : 'dias'}', Tone.danger)
        : days == 0
        ? ('Vence hoje', Tone.danger)
        : days == 1
        ? ('Vence amanhã', Tone.warning)
        : days <= 3
        ? ('$days dias restantes', Tone.warning)
        : ('$days dias restantes', Tone.info);
    return StatusBadge(label, tone: tone, icon: Icons.schedule);
  }

  Widget _acceptedStep(Map<String, dynamic> q) {
    final sell = s.canSell;
    final attached = q['requestFileName'] != null || '${q['requestText'] ?? ''}'.trim().isNotEmpty;
    return NextStepCard(
      title: attached ? 'Pedido de compra anexado · registre-o' : 'Aprovada pelo cliente · falta o pedido de compra',
      message: attached
          ? 'Passo 2 de 2: confira o anexo abaixo e registre o pedido de compra para poder gerar o pedido de venda.'
          : 'Passo 1 de 2: anexe o pedido de compra que o cliente enviou (PDF, imagem ou texto). Depois, registre-o para gerar o pedido de venda.',
      tone: attached ? Tone.success : Tone.warning,
      icon: attached ? Icons.check_circle_outline : Icons.warning_amber_rounded,
      // One main action; the ways out of the sale sit apart, on the right.
      actions: [
        if (sell && !attached) _primary('quote-po-start', 'Anexar pedido de compra', Icons.attach_file, () => _provideRequest(_attachRequest)),
        if (sell && !attached) _secondary('quote-po-start-text', 'Escrever texto do pedido', Icons.edit_note, () => _provideRequest(_setRequestText)),
        if (sell && attached) _primary('quote-po', 'Registrar pedido de compra', Icons.assignment_turned_in_outlined, _receivePo),
      ],
      trailing: [
        if (sell)
          Tooltip(
            message: _reviseTip,
            child: TextButton.icon(key: const ValueKey('quote-change'), onPressed: _revise, icon: const Icon(Icons.edit_note), label: const Text('Nova revisão')),
          ),
        if (sell) _negative('quote-gave-up', 'Cliente desistiu', Icons.thumb_down_alt_outlined, _gaveUp),
      ],
    );
  }

  /// First purchase order of the quote: once the file or text is saved, go straight on to registering it instead of waiting for another click.
  Future<void> _provideRequest(Future<void> Function() provide) async {
    await provide();
    if (!mounted) return;
    final q = _q;
    if (q != null && q['status'] == 'Accepted' && (q['requestFileName'] != null || '${q['requestText'] ?? ''}'.trim().isNotEmpty)) await _receivePo();
  }

  void _gaveUp() => _decline(gaveUp: true);

  FilledButton _primary(String key, String label, IconData icon, VoidCallback onPressed) =>
      FilledButton.icon(key: ValueKey(key), onPressed: onPressed, icon: Icon(icon), label: Text(label));

  Widget _secondary(String key, String label, IconData icon, VoidCallback onPressed, {String? tip}) {
    final button = OutlinedButton.icon(key: ValueKey(key), onPressed: onPressed, icon: Icon(icon), label: Text(label));
    return tip == null ? button : Tooltip(message: tip, child: button);
  }

  // Outcomes that end the sale read as such: error-coloured outline instead of the neutral one.
  Widget _negative(String key, String label, IconData icon, VoidCallback onPressed) {
    final error = Theme.of(context).colorScheme.error;
    return OutlinedButton.icon(
      key: ValueKey(key),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(foregroundColor: error, side: BorderSide(color: error.withValues(alpha: 0.7))),
    );
  }

  Widget _nextStep(Map<String, dynamic> q) {
    return switch (q['status']) {
      'Draft' => _draftStep(q),
      'PendingApproval' => _pendingApprovalStep(q),
      'Approved' => _approvedStep(q),
      'Sent' => _sentStep(q),
      'Accepted' => _acceptedStep(q),
      'PurchaseOrder' => _purchaseOrderStep(q),
      'Converted' => _convertedStep(q),
      'Rejected' => _rejectedStep(q),
      'Expired' => _expiredStep(q),
      _ when isSuperseded(q) => _supersededStep(q),
      _ => NextStepCard(title: 'Cancelada', message: '${q['decisionNote'] ?? ''}', tone: Tone.danger),
    };
  }

  Widget _draftStep(Map<String, dynamic> q) {
    final sell = s.canSell;
    return NextStepCard(
      title: q['needsApproval'] == true ? 'Desconto acima do limite' : 'Pronta para enviar?',
      message: q['needsApproval'] == true
          ? 'O maior desconto sobre a tabela é ${fmt(q['totals']['maxDiscountPercent'])}%${_maxDiscount == null ? '' : ' (limite ${fmt(_maxDiscount)}%)'}. O envio passa pela autorização do gerente comercial.'
          : _rejectionNote(q) != null
          ? 'O gerente recusou o desconto: ${_rejectionNote(q)}. Ajuste os preços e envie de novo.'
          : _mailOn
          ? 'Confira itens, preços e prazos. Ao enviar, o PDF segue por e-mail ao cliente e a validade começa a contar. Se já enviou por outro meio, use "Já enviei por outro meio".'
          : 'Confira itens, preços e prazos. Ao registrar o envio, a validade começa a contar. O e-mail você envia à parte, com o PDF.',
      tone: q['needsApproval'] == true || _rejectionNote(q) != null ? Tone.warning : Tone.info,
      actions: [
        if (sell && q['needsApproval'] != true && _mailOn) ...[
          _primary('quote-email', 'Enviar ao cliente', Icons.forward_to_inbox, _emailQuote),
          _secondary('quote-send', 'Já enviei por outro meio', Icons.send, _send),
        ] else if (sell)
          _primary('quote-send', q['needsApproval'] == true ? 'Enviar para autorização' : 'Registrar envio ao cliente', Icons.send, _send),
      ],
    );
  }

  Widget _pendingApprovalStep(Map<String, dynamic> q) {
    final sell = s.canSell;
    return NextStepCard(
      title: 'Aguardando autorização do gerente',
      message: 'Desconto de ${fmt(q['totals']['maxDiscountPercent'])}% sobre a tabela de preços. Para mudar algo antes disso, volte para rascunho.',
      tone: Tone.warning,
      actions: [
        if (s.canApproveSales) _primary('quote-approve', 'Autorizar desconto', Icons.thumb_up_alt_outlined, () => _act('approve', success: 'Desconto autorizado')),
        if (s.canApproveSales)
          _secondary(
            'quote-reject-approval',
            'Recusar desconto',
            Icons.thumb_down_alt_outlined,
            () => _reason('reject-approval', 'Recusar desconto', success: 'Orçamento voltou para rascunho', danger: true),
          ),
        if (sell) _secondary('quote-reopen', 'Voltar para rascunho para editar', Icons.edit_outlined, _reopen),
      ],
    );
  }

  Widget _approvedStep(Map<String, dynamic> q) {
    final sell = s.canSell;
    return NextStepCard(
      title: 'Desconto autorizado',
      message:
          'Autorizado por ${q['approvedBy'] ?? ''} em ${fmtDate(q['approvedAt'])}. Agora ${_mailOn ? 'envie o orçamento ao cliente' : 'registre o envio ao cliente'}. Para mudar algo antes, volte para rascunho.',
      actions: [
        if (sell && _mailOn) ...[
          _primary('quote-email', 'Enviar ao cliente', Icons.forward_to_inbox, _emailQuote),
          _secondary('quote-send', 'Já enviei por outro meio', Icons.send, _send),
        ] else if (sell)
          _primary('quote-send', 'Registrar envio ao cliente', Icons.send, _send),
        if (sell) _secondary('quote-reopen', 'Voltar para rascunho para editar', Icons.edit_outlined, _reopen),
      ],
    );
  }

  Widget _sentStep(Map<String, dynamic> q) {
    final sell = s.canSell;
    return NextStepCard(
      title: 'Aguardando resposta do cliente',
      message: _sentMessage(q),
      badge: _validityBadge(q),
      actions: [
        if (sell) _primary('quote-accept', 'Cliente aprovou', Icons.thumb_up_alt_outlined, _accept),
        if (sell) _secondary('quote-change', 'Nova revisão', Icons.edit_note, _revise, tip: _reviseTip),
        if (sell) _negative('quote-decline', 'Cliente recusou (venda perdida)', Icons.thumb_down_alt_outlined, _decline),
      ],
    );
  }

  Widget _purchaseOrderStep(Map<String, dynamic> q) {
    final sell = s.canSell;
    return NextStepCard(
      title: 'Pedido de compra recebido',
      message: 'Gere o pedido de venda${q['customerPo'] == null ? '' : ' (pedido do cliente ${q['customerPo']})'} para liberar a produção.',
      tone: Tone.success,
      actions: [
        if (sell) _primary('quote-convert', 'Gerar pedido de venda', Icons.receipt_long, _convert),
        if (sell) _secondary('quote-change', 'Nova revisão', Icons.edit_note, _revise, tip: _reviseTip),
        if (sell) _negative('quote-gave-up', 'Cliente desistiu', Icons.thumb_down_alt_outlined, () => _decline(gaveUp: true)),
      ],
    );
  }

  /// Says where the order stands (its situation and what comes next), so the quote is rarely opened only to look.
  Widget _convertedStep(Map<String, dynamic> q) {
    final order = _order;
    final snap = order == null ? null : orderSnapshot(order);
    return NextStepCard(
      title: 'Convertida em pedido',
      message: snap == null ? 'Este orçamento virou o pedido ${q['salesOrderReference'] ?? ''}.' : 'Este orçamento virou o pedido ${snap.title}. ${snap.message}',
      tone: snap?.tone == Tone.danger ? Tone.danger : Tone.success,
      actions: [
        if (q['salesOrderId'] != null)
          _primary('quote-open-order', 'Abrir pedido', Icons.open_in_new, () => openSalesOrder(context, s, q['salesOrderId'] as int).then((_) => _load())),
      ],
    );
  }

  Widget _rejectedStep(Map<String, dynamic> q) {
    final sell = s.canSell;
    return NextStepCard(
      title: 'Venda perdida',
      message:
          '${q['lostReason'] == null ? '' : '${lostReasons['${q['lostReason']}'] ?? q['lostReason']}. '}${q['decisionNote'] ?? ''}\nSe o cliente voltar a negociar, abra uma nova revisão a partir desta.',
      tone: Tone.danger,
      actions: [if (sell) _primary('quote-revise', 'Retomar com nova revisão', Icons.restart_alt, _revise)],
    );
  }

  Widget _expiredStep(Map<String, dynamic> q) {
    final sell = s.canSell;
    return NextStepCard(
      title: 'Validade expirada',
      message: 'A validade passou sem resposta. Prorrogue se o cliente ainda pode responder; crie uma nova revisão para mudar preço ou prazo.',
      tone: Tone.danger,
      actions: [
        if (sell) _primary('quote-extend', 'Prorrogar validade', Icons.event_repeat, _extend),
        if (sell) _secondary('quote-revise', 'Nova revisão', Icons.restart_alt, _revise, tip: _reviseTip),
      ],
    );
  }

  Widget _supersededStep(Map<String, dynamic> q) {
    return NextStepCard(
      title: 'Substituída pela revisão ${q['supersededBy']}',
      message: 'Esta versão ficou só para consulta. A que está em andamento é a ${q['supersededBy']}.',
      tone: Tone.info,
      actions: [_primary('quote-open-latest', 'Abrir ${q['supersededBy']}', Icons.open_in_new, () => openQuote(context, s, q['supersededById'] as int).then((_) => _load()))],
    );
  }

  /// The manager's reason when the discount was refused and the quote came back to draft (history is newest first).
  String? _rejectionNote(Map<String, dynamic> q) {
    if (q['status'] != 'Draft') return null;
    for (final h in (q['history'] as List).cast<Map<String, dynamic>>()) {
      if (h['action'] == 'approval-rejected') return h['note'] as String?;
      if (h['action'] == 'sent' || h['action'] == 'submitted') return null; // sent again since: the old refusal no longer applies
    }
    return null;
  }

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
    final danger = Theme.of(context).colorScheme.error;
    // Grouped by what the user is trying to do: edit, handle the document, create something new from this quote, change its situation.
    // Outcomes of the customer's answer (approved, wants changes, refused, gave up) are the buttons on the status card, not menu items.
    // Editing a draft is the pencil in the bar; document actions (PDF, e-mail) and the validity live only in this menu, not on the status card.
    final document = <PopupMenuEntry<VoidCallback>>[
      PopupMenuItem(
        value: _preview,
        child: const ListTile(leading: Icon(Icons.description_outlined), title: Text('Ver texto do orçamento')),
      ),
      PopupMenuItem(
        key: const ValueKey('quote-menu-pdf'),
        value: _downloadPdf,
        child: const ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Baixar PDF')),
      ),
      if (s.canSell && _mailOn && status == 'Sent')
        PopupMenuItem(
          key: const ValueKey('quote-menu-email'),
          value: _emailQuote,
          child: const ListTile(leading: Icon(Icons.forward_to_inbox), title: Text('Reenviar por e-mail')),
        ),
      if (['Sent', 'Accepted', 'PurchaseOrder'].contains(status))
        PopupMenuItem(
          key: const ValueKey('quote-menu-mail'),
          value: _mail,
          child: const ListTile(leading: Icon(Icons.mail_outline), title: Text('Abrir e-mail para o cliente')),
        ),
      if (s.canSell && status == 'Sent')
        PopupMenuItem(
          key: const ValueKey('quote-menu-extend'),
          value: _extend,
          child: const ListTile(leading: Icon(Icons.event_repeat), title: Text('Prorrogar validade')),
        ),
    ];
    final create = <PopupMenuEntry<VoidCallback>>[
      if (s.canSell)
        PopupMenuItem(
          value: _duplicate,
          child: const ListTile(leading: Icon(Icons.copy), title: Text('Duplicar'), subtitle: Text('Cópia independente, com número novo')),
        ),
      if (s.canSell && !['Cancelled', 'Converted'].contains(status))
        PopupMenuItem(
          value: _newFeasibility,
          child: const ListTile(
            leading: Icon(Icons.fact_check_outlined),
            title: Text('Pedir análise de viabilidade'),
            subtitle: Text('Avaliação técnica, de qualidade e comercial'),
          ),
        ),
    ];
    final situation = <PopupMenuEntry<VoidCallback>>[
      // No "Nova revisão" here: every state that can be revised already has that button on the status card, so a second entry only confuses.
      if (s.canSell && ['Draft', 'PendingApproval', 'Approved'].contains(status))
        PopupMenuItem(
          value: () => _reason('cancel', 'Cancelar ${q['reference']}', label: 'Motivo (ex.: emitido por engano)', success: 'Orçamento cancelado', confirmLabel: 'Cancelar orçamento', danger: true),
          // Destructive entries wear the error colour, like the outcome buttons on the status card.
          child: ListTile(
            iconColor: danger,
            textColor: danger,
            leading: const Icon(Icons.block),
            title: const Text('Cancelar orçamento'),
            subtitle: const Text('Só para o que nunca foi enviado ao cliente'),
          ),
        ),
      if (s.canSell && canDeleteQuote(s, status, q['revision'] as int? ?? 0))
        PopupMenuItem(
          value: _delete,
          child: ListTile(iconColor: danger, textColor: danger, leading: const Icon(Icons.delete_outline), title: const Text('Excluir')),
        ),
    ];
    final menu = <PopupMenuEntry<VoidCallback>>[];
    for (final group in [document, create, situation]) {
      if (group.isEmpty) continue;
      if (menu.isNotEmpty) menu.add(const PopupMenuDivider());
      menu.addAll(group);
    }
    return [
      PrintButton(name: 'Orçamento ${q['reference']}', warning: quotePrintWarning(q), builder: () => buildQuotePdf(api, q)),
      if (s.canSell && status == 'Draft') IconButton(tooltip: 'Editar', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
      PopupMenuButton<VoidCallback>(key: const ValueKey('quote-menu'), onSelected: (f) => f(), itemBuilder: (_) => menu),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    return Scaffold(
      appBar: AppBar(
        // The customer is in the header (and links to its page); the title says which record this is.
        title: Text(q == null ? 'Orçamento' : 'Orçamento ${q['reference']}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(key: const ValueKey('quote-refresh'), tooltip: 'Atualizar (F5)', onPressed: _load, icon: const Icon(Icons.refresh)),
          if (q != null)
            RelatedMenu(
              links: [
                RelatedLink(Icons.business_outlined, 'Cliente: ${q['customerName']}', () => openCustomer(context, s, q['customerId'] as int)),
                if (q['salesOrderId'] != null) RelatedLink(Icons.receipt_long_outlined, 'Pedido de venda ${q['salesOrderReference'] ?? ''}', () => openSalesOrder(context, s, q['salesOrderId'] as int)),
              ],
            ),
          ..._menuActions(),
        ],
      ),
      body: RecordShortcuts(
        onRefresh: _load,
        onPrint: q == null ? null : _printQuote,
        child: _error != null && q == null
            ? LoadError(message: _error!, onRetry: _load)
            : q == null
            ? const RecordSkeleton()
            : RefreshIndicator(onRefresh: _load, child: _body(q)),
      ),
    );
  }

  Widget _header(Map<String, dynamic> q, Map<String, dynamic> t) {
    return RecordHeader(
  icon: Icons.request_quote_outlined,
  kind: 'Orçamento comercial${q['revision'] == 0 ? '' : ' · revisão ${String.fromCharCode(65 + (q['revision'] as int))}'}',
  title: '${q['reference']}',
  // The stage path already names these statuses; the badge stays for the ones it cannot say (draft, approval, lost with a reason, replaced...).
  badge: const ['Sent', 'Accepted', 'PurchaseOrder', 'Converted'].contains(q['status']) ? null : StatusBadge(quoteSituation(q), tone: quoteToneOf(q)),
  amount: fmtMoney(t['total']),
  amountLabel: 'Total do orçamento',
  fieldLinks: {'Cliente': () => openCustomer(context, s, q['customerId'] as int)},
  fields: [
    ('Cliente', '${q['customerName']}'),
    // Contact, validity and freight matter while the quote is being worked; afterwards they sit in Detalhes.
    if (_working(q)) ('Contato', _contact(q)),
    if (_validityMatters(q)) ('Validade', _validity(q)),
    ('Prazo de pagamento', fmt(q['paymentTermName'] ?? q['customPaymentTerm'])),
    if (_working(q)) ('Frete', _freight(q)),
    ('Ref. do cliente', fmt(q['customerReference'])),
    ('Pedido do cliente', fmt(q['customerPo'])),
  ],
);
  }

  /// Before the customer's answer is final: the quote can still change hands or text.
  bool _working(Map<String, dynamic> q) => _openStatuses.contains(q['status']);

  /// The validity only matters until the customer answers; after that it is history.
  bool _validityMatters(Map<String, dynamic> q) => const ['Draft', 'PendingApproval', 'Approved', 'Sent'].contains(q['status']);

  String _contact(Map<String, dynamic> q) => [q['contactName'], q['contactEmail']].whereType<String>().join(' · ');

  String _validity(Map<String, dynamic> q) => q['validUntil'] != null ? fmtDay(q['validUntil']) : '${q['validityDays']} dias após envio';

  String _freight(Map<String, dynamic> q) => freightTerms[q['freight']] ?? fmt(q['freight']);

  Widget _itemsSection(Map<String, dynamic> q, Map<String, dynamic> t, List<Map<String, dynamic>> lines) {
    return Section(
  title: 'Itens (${lines.length})',
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SimpleTable(
        columns: [
          col('Item', 'sequence'),
          ColumnSpec('Produto', (e) => '${e['productCode']}${e['customerPartNumber'] == null ? '' : ' (${e['customerPartNumber']})'}'),
          col('Descrição', 'description'),
          ColumnSpec('Qtd.', (e) => '${fmtQty(e['quantity'])} ${e['unit']}', numeric: true),
          ColumnSpec('Preço Unitário', (e) => fmtMoney(e['unitPrice']), numeric: true),
          // A line above the limit is tinted, and tagged so the colour is not the only sign.
          ColumnSpec(
            'Desc. %',
            (e) => e['discountPercent'] == null || e['discountPercent'] == 0
                ? '—'
                : (_maxDiscount != null && _n(e['discountPercent']) > _maxDiscount! ? '⚠ ${fmt(e['discountPercent'])}' : fmt(e['discountPercent'])),
            numeric: true,
          ),
          col('IPI %', 'ipiPercent', numeric: true),
          ColumnSpec(
            'Entrega',
            (e) => e['deliveryDate'] != null ? fmtDay(e['deliveryDate']) : (e['leadTimeDays'] != null ? '${e['leadTimeDays']} dias úteis' : ''),
            numeric: true,
          ),
          moneyCol('Total', 'total'),
        ],
        rows: lines,
        emptyText: 'Este orçamento não tem itens.',
        // Columns that say nothing for every line (no discount, no IPI) make room for the others.
        hideWhenEmpty: const {'Desc. %', 'IPI %'},
        rowColor: (e) => _maxDiscount != null && _n(e['discountPercent']) > _maxDiscount! ? toneColors(context, Tone.warning).$1 : null,
      ),
      if (_maxDiscount != null && lines.any((e) => _n(e['discountPercent']) > _maxDiscount!))
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            '⚠ Desconto acima do limite de ${fmt(_maxDiscount)}%.',
            key: const ValueKey('quote-discount-note'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      if (lines.any((l) => l['leadTimeDays'] != null && l['deliveryDate'] == null))
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'Prazo de entrega em dias úteis, contado a partir da data em que o cliente aprovar o orçamento.',
            key: const ValueKey('quote-lead-note'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      const SizedBox(height: 14),
      // The printed total is products + IPI, so that row is the emphasised one; the ICMS estimate sits below it.
      TotalsBlock(
        [
          ('Produtos', fmtMoney(t['products'])),
          ('IPI', fmtMoney(t['ipi'])),
          ('Total', fmtMoney(t['total'])),
          if (_n(t['icms']) > 0) ('ICMS (estimativa)', fmtMoney(t['icms'])),
          if (_n(t['icms']) > 0) ('Total com ICMS (estimativa)', fmtMoney(_n(t['total']) + _n(t['icms']))),
        ],
        strong: 2,
      ),
    ],
  ),
);
  }

  Widget _detailsSection(Map<String, dynamic> q) {
    return Section(
  title: 'Detalhes',
  child: InfoGrid([
    // What the header shows only while the quote is being worked.
    if (!_working(q)) ('Contato', _contact(q)),
    if (!_validityMatters(q)) ('Validade', _validity(q)),
    if (!_working(q)) ('Frete', _freight(q)),
    ('Local de entrega', fmt(q['addressText'])),
    ('Condições gerais', fmt(q['conditions'])),
    ('Observações', fmt(q['notes'])),
    ('Criada', '${fmt(q['createdBy'])} · ${fmtDate(q['createdAt'])}'),
    ('Autorização do gerente', q['approvedAt'] == null ? '' : '${fmt(q['approvedBy'])} · ${fmtDate(q['approvedAt'])}'),
    ('Enviada', q['sentAt'] == null ? '' : _sentDetail(q)),
    ('Resposta do cliente', q['decidedAt'] == null ? '' : '${fmtDate(q['decidedAt'])}${q['decisionNote'] == null ? '' : ' · ${q['decisionNote']}'}'),
    ('Motivo da perda', q['lostReason'] == null ? '' : lostReasons['${q['lostReason']}'] ?? '${q['lostReason']}'),
  ]),
);
  }

  Widget _body(Map<String, dynamic> q) {
    final t = q['totals'] as Map<String, dynamic>;
    final (step, failed) = quotePath(q['status'], superseded: isSuperseded(q));
    final lines = (q['lines'] as List).cast<Map<String, dynamic>>();
    return SideBySide(
      main: [
        _header(q, t),
        gap,
        StagePath(
          steps: flowSteps,
          current: step,
          failedLabel: failed,
          // The order the quote became is the one step that lives on another page.
          onStep: (i) => i == 4 && q['salesOrderId'] != null ? () => unawaited(openSalesOrder(context, s, q['salesOrderId'] as int).then((_) => _load())) : null,
        ),
        gap,
        _creditBanner(),
        _nextStep(q),
        // While nothing is attached the step card above carries the buttons; the section appears once there is something to show.
        if (const ['Accepted', 'PurchaseOrder'].contains(q['status']) && (q['requestFileName'] != null || '${q['requestText'] ?? ''}'.trim().isNotEmpty)) ...[
          gap,
          _requestSection(q),
        ],
        gap,
        _itemsSection(q, t, lines),
        gap,
        if (!const ['Accepted', 'PurchaseOrder'].contains(q['status']) &&
            (q['status'] == 'Converted' || q['requestFileName'] != null || '${q['requestText'] ?? ''}'.isNotEmpty)) ...[
          _requestSection(q),
          gap,
        ],
        _detailsSection(q),
      ],
      side: [
        Section(
          title: 'Histórico',
          child: TimelineView(entries: timeline(q['history'] as List, kind: 'quote')),
        ),
      ],
    );
  }
}
