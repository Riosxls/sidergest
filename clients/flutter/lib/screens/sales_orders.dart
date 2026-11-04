import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../reports/certificate_doc.dart';
import '../reports/nf_doc.dart';
import '../reports/print_docs.dart';
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/load_error.dart';
import '../widgets/pipeline.dart';
import '../widgets/print_gate.dart';
import '../widgets/print_panel.dart';
import '../widgets/record_list.dart';
import '../widgets/record_shortcuts.dart';
import 'certificates.dart';
import 'customers.dart';
import 'production_orders.dart';
import 'sales_common.dart';
import 'sales_quotes.dart';

num _n(Object? v) => v is num ? v : 0;

/// Sales orders (Pedidos de venda) list.
class SalesOrdersScreen extends StatefulWidget {
  const SalesOrdersScreen({super.key, required this.session});

  final Session session;

  @override
  State<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

Future<void> newSalesOrder(BuildContext context, Session session, {VoidCallback? onSaved}) async {
  final o = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => QuoteEditorScreen(session: session, asOrder: true)));
  onSaved?.call();
  if (o == null || !context.mounted) return;
  await openSalesOrder(context, session, o['id'] as int);
  onSaved?.call();
}

class _SalesOrdersScreenState extends State<SalesOrdersScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _status;
  bool _open = true;
  bool _late = false;
  String? _month;
  String? _billTo;

  static Map<String, String> _months() {
    final now = DateTime.now();
    const names = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    return {
      for (var i = -2; i <= 9; i++)
        () {
          final d = DateTime(now.year, now.month + i);
          return '${d.year}-${d.month.toString().padLeft(2, '0')}';
        }(): '${names[DateTime(now.year, now.month + i).month - 1]}/${DateTime(now.year, now.month + i).year}',
    };
  }

  Future<void> _new() => newSalesOrder(context, widget.session, onSaved: () => _list.currentState?.reload());

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    filtersActive: _open || _status != null || _late || _month != null || _billTo != null,
    onClearFilters: () => setState(() {
      _open = false;
      _status = null;
      _late = false;
      _month = null;
      _billTo = null;
    }),
    api: widget.session.api,
    path: '/api/sales/orders',
    query: {'status': _status, 'open': _open && _status == null ? true : null, 'month': _month, 'late': _late ? true : null, 'billTo': _billTo},
    searchHint: 'Pedido, cliente ou pedido do cliente',
    filters: [
      ChoiceFilter(label: 'Situação', value: _status, choices: salesOrderStatuses, onChanged: (v) => setState(() => _status = v)),
      FilterChip(label: const Text('Somente abertos'), selected: _open, onSelected: (v) => setState(() => _open = v)),
      ChoiceFilter(label: 'Entrega no mês', value: _month, choices: _months(), onChanged: (v) => setState(() => _month = v)),
      FilterChip(key: const ValueKey('orders-late'), label: const Text('Atrasados'), selected: _late, onSelected: (v) => setState(() => _late = v)),
      ChoiceFilter(label: 'Faturar para', value: _billTo, choices: billToLabels, onChanged: (v) => setState(() => _billTo = v)),
    ],
    fab: widget.session.canSell
        ? FloatingActionButton.extended(heroTag: 'new-sales-order', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Novo pedido'))
        : null,
    columns: [
      col('Pedido', 'reference'),
      col('Cliente', 'customerName'),
      col('Pedido do cliente', 'customerPo'),
      labelCol('Situação', 'status', salesOrderStatuses),
      labelCol('Faturar p/', 'billTo', billToLabels),
      moneyCol('Total', 'total'),
      moneyCol('Saldo R\$', 'balanceValue'),
      ColumnSpec('Saldo kg', (e) => e['balanceKg'] == null ? '' : fmt(e['balanceKg']), numeric: true),
      dateCol('Entrega', 'nextDue'),
      ColumnSpec('Pronto', (e) => '${(_n(e['progress']) * 100).round()}%', numeric: true),
      ColumnSpec(
        'Alerta',
        (e) => [
          if (e['late'] == true) 'Atrasado',
          if (e['ready'] == true && ['Released', 'PartiallyShipped'].contains(e['status'])) 'Pronto p/ expedir',
        ].join(' · '),
      ),
    ],
    rowColor: (ctx, e) => e['late'] == true ? toneColors(ctx, Tone.danger).$1 : null,
    onTap: (e) async {
      await openSalesOrder(context, widget.session, e['id'] as int);
      unawaited(_list.currentState?.reload());
    },
  );
}

String _measures(Object? spec) {
  if (spec is! Map) return '';
  return [
    if (spec['outsideDiameter'] != null) 'Ø${fmt(spec['outsideDiameter'])}',
    if (spec['thickness'] != null) 'e${fmt(spec['thickness'])}',
    if (spec['length'] != null) 'c${fmt(spec['length'])}',
  ].join(' × ');
}

String _standard(Object? spec) {
  if (spec is! Map) return '';
  return [spec['standard'], if (spec['condition'] != null) deliveryConditions[spec['condition']]].whereType<Object>().join(' · ');
}

/// Sales order detail: items, deliveries, production and change/cancel actions.
class SalesOrderScreen extends StatefulWidget {
  const SalesOrderScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<SalesOrderScreen> createState() => _SalesOrderScreenState();
}

class _SalesOrderScreenState extends State<SalesOrderScreen> {
  Map<String, dynamic>? _o;
  List<Map<String, dynamic>> _certs = const [];
  Map<String, dynamic>? _quote;
  String? _error;

  ApiClient get api => widget.session.api;
  Session get s => widget.session;
  String get base => '/api/sales/orders/${widget.id}';
  String get status => '${_o?['status']}';
  bool get _certified => _o?['certificateWaived'] == true || _certs.any((c) => c['status'] == 'Issued');

  Future<void> _newCertificate() async {
    if (await newCertificate(context, s, _o!) && mounted) unawaited(_load());
  }

  Future<void> _waiveCertificate(bool waived) async {
    final r = await runAction(
      context,
      () => api.post('$base/certificate-waiver', {'waived': waived}),
      success: waived ? 'Certificado dispensado' : 'Certificado exigido novamente',
    );
    if (r != null) unawaited(_load());
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reloads the order. [report]: the user asked (F5, refresh button), so a failure is said even when the old data stays on screen.
  Future<void> _load({bool report = false}) async {
    try {
      final o = await api.get(base) as Map<String, dynamic>;
      // Certificates are optional context: a failure here must not hide the order.
      var certs = const <Map<String, dynamic>>[];
      try {
        certs = (await api.list('/api/sales/certificates', query: {'orderId': widget.id}, take: 200)).items;
      } catch (e) {
        debugPrint('sales_orders: Optional context; the screen works without it: $e');
        // Optional context; the screen works without it.
      }
      // The customer's purchase order lives on the quote; optional as well (orders can be typed without one).
      Map<String, dynamic>? quote;
      if (o['quoteId'] != null) {
        try {
          quote = await api.get('/api/sales/quotes/${o['quoteId']}') as Map<String, dynamic>;
        } catch (e) {
          debugPrint('sales_orders: Optional context; the screen works without it: $e');
          // Optional context; the screen works without it.
        }
      }
      if (mounted) {
        setState(() {
          _o = o;
          _certs = certs;
          _quote = quote;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (_o != null) {
        // The order on screen is still the last one that loaded; say that it is not up to date.
        if (report) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao atualizar: ${friendlyError(e)}')));
        return;
      }
      setState(() => _error = friendlyError(e));
    }
  }

  void _refresh() => unawaited(_load(report: true));

  String get _salesKey => 'order:${widget.id}:sales';
  String _ofKey(Object? id) => 'order:${widget.id}:of:$id';

  Future<bool> _printSalesOrder() => printPdf(context, 'Pedido de venda ${_ref()}', () => buildSalesOrderPdf(api, _o!), doneKey: _salesKey);

  Future<bool> _printOf(int id, String ref) => printPdf(
    context,
    'Ordem de produção $ref',
    () async => buildProductionOrderPdf(api, await api.get('/api/production/orders/$id') as Map<String, dynamic>),
    doneKey: _ofKey(id),
  );

  /// The order's OFs that were not printed or downloaded yet, as id -> reference.
  Future<Map<int, String>> _pendingOfs() async {
    final ofs = (_o!['lines'] as List).cast<Map<String, dynamic>>().where((l) => l['productionOrderId'] != null).fold(<int, String>{}, (m, l) => m..[l['productionOrderId'] as int] = '${l['productionReference']}');
    return {
      for (final e in ofs.entries)
        if (!await PrintLog.isDone(_ofKey(e.key))) e.key: e.value,
    };
  }

  Future<void> _release() async {
    // The pedido interno de venda is the paper of the step that ends here.
    final proceed = await printGate(
      context,
      doneKey: _salesKey,
      title: 'Imprimir o pedido interno de venda?',
      message: 'Antes de liberar ${_ref()} para a produção, imprima ou baixe o pedido interno de venda. Você também encontra todos os documentos no fim do fluxo.',
      onPrint: _printSalesOrder,
      onDownload: () => savePdf(context, 'Pedido de venda ${_ref()}.pdf', () => buildSalesOrderPdf(api, _o!), doneKey: _salesKey),
    );
    if (!proceed || !mounted) return;
    var useStock = true;
    var overrideCredit = false;
    final creditExceeded = (_o!['credit'] as Map?)?['exceeded'] == true && s.canApproveSales;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          icon: const Icon(Icons.precision_manufacturing_outlined),
          title: Text('Liberar ${_o!['reference']} para produção?'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Para cada item, o saldo livre de produto acabado é reservado para o pedido e uma ordem de fabricação (OF) é criada para o restante, com a data de entrega do item.',
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const ValueKey('use-stock'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usar estoque disponível'),
                  subtitle: const Text('Desligado: fabrica a quantidade toda'),
                  value: useStock,
                  onChanged: (v) => set(() => useStock = v),
                ),
                if (creditExceeded)
                  SwitchListTile(
                    key: const ValueKey('override-credit'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Autorizar acima do limite de crédito'),
                    subtitle: const Text('Fica registrado no histórico do pedido'),
                    value: overrideCredit,
                    onChanged: (v) => set(() => overrideCredit = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(key: const ValueKey('confirm-step'), onPressed: () => Navigator.pop(c, true), child: const Text('Liberar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final r = await runAction(context, () => api.post('$base/release', {'useStock': useStock, if (overrideCredit) 'overrideCredit': true}), success: 'Pedido liberado para produção');
    if (r is Map<String, dynamic> && mounted) setState(() => _o = r);
  }

  Future<void> _planDelivery() async {
    final o = _o!;
    final lines = (o['lines'] as List).cast<Map<String, dynamic>>().where((l) => _n(l['remaining']) - _n(l['planned']) > 0).toList();
    if (lines.isEmpty) return showError(context, 'Todos os itens já estão programados ou expedidos');
    final pending = await _pendingOfs();
    if (pending.isNotEmpty && mounted) {
      // Typed to answer whether every OF went out, so a cancelled print dialog leaves the gate asking next time.
      Future<bool> printAll() async {
        var all = true;
        for (final e in pending.entries) {
          all = await _printOf(e.key, e.value) && all;
        }
        return all;
      }

      Future<bool> saveAll() async {
        var all = true;
        for (final e in pending.entries) {
          all = await savePdf(context, 'Ordem de produção ${e.value}.pdf', () async => buildProductionOrderPdf(api, await api.get('/api/production/orders/${e.key}') as Map<String, dynamic>), doneKey: _ofKey(e.key)) && all;
        }
        return all;
      }

      final proceed = await printGate(
        context,
        doneKey: 'order:${widget.id}:ofs:${pending.keys.join(',')}',
        title: pending.length == 1 ? 'Imprimir a ordem de fabricação?' : 'Imprimir as ordens de fabricação?',
        message: 'Antes de programar a entrega, imprima ou baixe ${pending.values.join(', ')} para a produção.',
        onPrint: printAll,
        onDownload: saveAll,
      );
      if (!proceed || !mounted) return;
    }
    if (!mounted) return;
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DeliveryDialog(order: o, lines: lines),
    );
    if (r == null || !mounted) return;
    final d = await runAction(context, () => api.post('$base/deliveries', r), success: 'Entrega programada');
    if (d is Map<String, dynamic>) {
      await _load();
      if (mounted) await openDelivery(context, s, d['id'] as int);
      unawaited(_load());
    }
  }

  Future<void> _cancel() async {
    Map<String, dynamic> preview;
    try {
      preview = await api.get('$base/cancel-preview') as Map<String, dynamic>;
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
      return;
    }
    if (!mounted) return;
    List<String> names(String key) => (preview[key] as List).map((e) => '$e').toList();
    final shipped = names('shippedDeliveries');
    if (shipped.isNotEmpty) {
      return showError(context, 'Há entregas já expedidas (${shipped.join(', ')}). Cancele-as antes, ou use "Encerrar saldo" para fechar o pedido com o que já saiu.');
    }
    final ofs = (preview['productionOrders'] as List).cast<Map<String, dynamic>>();
    final started = ofs.where((e) => e['started'] == true).toList();
    final idle = ofs.where((e) => e['started'] != true).map((e) => '${e['reference']}').toList();
    final planned = names('plannedDeliveries');
    final reserved = preview['reservations'] as int? ?? 0;
    final r = await showDialog<({String reason, bool option})>(
      context: context,
      builder: (_) => ReasonDialog(
        title: 'Cancelar ${_o!['reference']}?',
        confirmLabel: 'Cancelar pedido',
        details: [
          if (idle.isNotEmpty) 'OFs ainda não iniciadas, canceladas junto: ${idle.join(', ')}',
          if (planned.isNotEmpty) 'Entregas programadas, canceladas junto: ${planned.join(', ')}',
          if (reserved > 0) 'Reservas de estoque liberadas: $reserved',
          if (started.isNotEmpty) 'OFs em andamento: ${started.map((e) => '${e['reference']} (${productionStatuses[e['status']] ?? e['status']})').join(', ')}',
          if (idle.isEmpty && planned.isEmpty && reserved == 0 && started.isEmpty) 'O pedido não tem OFs, entregas nem reservas.',
        ],
        optionLabel: started.isEmpty ? null : 'Cancelar também as OFs em andamento',
        optionHelp: 'Desmarcado: as OFs seguem no PCP e o produto vai para o estoque. Marcado: elas são canceladas (cancelamento técnico) e o material reservado é liberado.',
      ),
    );
    if (r == null || !mounted) return;
    final o = await runAction(context, () => api.post('$base/cancel', {'reason': r.reason, 'cancelProduction': r.option}), success: 'Pedido cancelado');
    if (o is Map<String, dynamic> && mounted) setState(() => _o = o);
  }

  Future<void> _closeBalance() async {
    final lines = (_o!['lines'] as List).cast<Map<String, dynamic>>().where((l) => _n(l['remaining']) > 0).toList();
    final r = await showDialog<({String reason, bool option})>(
      context: context,
      builder: (_) => ReasonDialog(
        title: 'Encerrar saldo de ${_o!['reference']}?',
        confirmLabel: 'Encerrar saldo',
        reasonLabel: 'Motivo (ex.: cliente cancelou o restante)',
        details: [
          for (final l in lines) 'Item ${l['sequence']} · ${l['productCode']}: ${fmt(l['quantity'])} → ${fmt(l['shipped'])} ${l['unit']}',
          'Entregas ainda não expedidas são canceladas. OFs abertas não são canceladas.',
          'O pedido passa a valer só pelo que já foi expedido.',
        ],
      ),
    );
    if (r == null || !mounted) return;
    final o = await runAction(context, () => api.post('$base/close-balance', {'reason': r.reason}), success: 'Saldo encerrado');
    if (o is Map<String, dynamic> && mounted) setState(() => _o = o);
  }

  Future<void> _reschedule() async {
    final o = _o!;
    final lines = (o['lines'] as List).cast<Map<String, dynamic>>();
    final r = await submitForm(
      context,
      api: api,
      title: 'Alterar prazos · ${o['reference']}',
      fields: [
        FieldSpec('customerPo', 'Pedido do cliente', defaultValue: o['customerPo']),
        for (final l in lines) FieldSpec('line-${l['id']}', 'Item ${l['sequence']} · ${l['productCode']} · entrega', type: FieldType.date, defaultValue: l['dueDate']),
        const FieldSpec('reason', 'Motivo da mudança', hint: 'Obrigatório ao mudar uma data (ex.: cliente adiou). As OFs abertas acompanham a nova data.'),
      ],
      submit: (b) => api.post('$base/reschedule', {
        'reason': b['reason'],
        'customerPo': b['customerPo'],
        'lines': [
          for (final l in lines)
            if (b['line-${l['id']}'] != null) {'lineId': l['id'], 'dueDate': b['line-${l['id']}']},
        ],
      }),
    );
    if (r != null && r['reference'] != null && mounted) {
      setState(() => _o = r);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prazos atualizados')));
    }
  }

  List<Widget> _closeAction() => [
    if (s.canSell && status == 'PartiallyShipped')
      TextButton(key: const ValueKey('order-close-balance'), onPressed: _closeBalance, child: const Text('Encerrar saldo')),
  ];

  Future<void> _edit() async {
    final r = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => QuoteEditorScreen(session: s, quote: _o, asOrder: true),
      ),
    );
    if (r != null && mounted) setState(() => _o = r);
  }

  Future<void> _printCustomerPo() async {
    final q = _quote!;
    try {
      final fileName = q['requestFileName'] as String?;
      final bytes = await customerOrderPdf(
        fileName: fileName,
        file: fileName == null ? null : await api.download('/api/sales/quotes/${q['id']}/request-file'),
        text: q['requestText'] as String?,
        title: 'Pedido de compra do cliente ${_ref()}',
      );
      if (bytes == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este tipo de arquivo não imprime daqui. Baixe-o no orçamento e imprima pelo programa que o abre.')));
        return;
      }
      if (mounted) await printPdf(context, 'Pedido de compra ${_ref()}', () async => bytes, doneKey: 'quote:${q['id']}:po');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao imprimir: ${friendlyError(e)}')));
    }
  }

  String _ref() => '${_o?['reference'] ?? ''}';

  /// The five papers of a purchase, in the order they are printed.
  List<PrintDoc> _printDocs(Map<String, dynamic> o) {
    final status = '${o['status']}';
    final lines = (o['lines'] as List).cast<Map<String, dynamic>>();
    final deliveries = (o['deliveries'] as List).cast<Map<String, dynamic>>();
    final q = _quote;
    final hasPo = q != null && (q['requestFileName'] != null || '${q['requestText'] ?? ''}'.trim().isNotEmpty);
    final ofs = lines.where((l) => l['productionOrderId'] != null).fold(<int, String>{}, (m, l) => m..[l['productionOrderId'] as int] = '${l['productionReference']}');
    final shipped = deliveries.where((d) => ['Shipped', 'Delivered'].contains(d['status'])).toList();
    final issued = _certs.where((c) => c['status'] != 'Cancelled').toList();
    return [
      PrintDoc(
        id: 'customer-po',
        label: 'Pedido de compra do cliente',
        detail: q?['requestFileName'] != null ? '${q?['requestFileName']}' : 'Texto registrado no orçamento',
        ready: hasPo,
        waiting: q == null ? 'Pedido digitado sem orçamento: não há pedido de compra anexado' : 'Anexe o pedido de compra no orçamento ${o['quoteReference']}',
        onPrint: _printCustomerPo,
        doneKey: q == null ? null : 'quote:${q['id']}:po',
      ),
      PrintDoc(id: 'sales-order', label: 'Pedido interno de venda', detail: _ref(), onPrint: _printSalesOrder, doneKey: _salesKey),
      if (ofs.isEmpty)
        PrintDoc(
          id: 'of',
          label: 'Ordem de fabricação',
          ready: false,
          notApplicable: status != 'Created',
          waiting: status == 'Created' ? 'Libere o pedido para a produção' : 'Este pedido saiu do estoque, sem OF',
        )
      else
        for (final e in ofs.entries)
          PrintDoc(
            id: 'of-${e.key}',
            label: 'Ordem de fabricação',
            detail: e.value,
            onPrint: () => _printOf(e.key, e.value),
            doneKey: _ofKey(e.key),
          ),
      if (shipped.isEmpty)
        const PrintDoc(id: 'nf', label: 'Nota fiscal', ready: false, waiting: 'Disponível depois de expedir a entrega')
      else
        for (final d in shipped)
          PrintDoc(
            id: 'nf-${d['id']}',
            label: 'Nota fiscal',
            detail: '${d['invoiceNumber'] == null ? 'sem nº de NF' : 'NF ${d['invoiceNumber']}'} · ${d['reference']}',
            onPrint: () async {
              final full = await api.get('/api/sales/deliveries/${d['id']}') as Map<String, dynamic>;
              if (!mounted) return;
              await printNf(context, name: 'NF ${d['reference']}', number: d['invoiceNumber'] == null ? '' : '${d['invoiceNumber']}', build: (f) => buildSaleNfPdf(api, full, f));
            },
          ),
      if (issued.isEmpty)
        PrintDoc(
          id: 'certificate',
          label: 'Certificado de qualidade',
          ready: false,
          notApplicable: o['certificateWaived'] == true,
          waiting: o['certificateWaived'] == true ? 'Dispensado para este pedido' : 'Emita o certificado de qualidade',
        )
      else
        for (final c in issued)
          PrintDoc(
            id: 'certificate-${c['id']}',
            label: 'Certificado de qualidade',
            detail: '${c['reference']} · ${c['description']}${c['status'] == 'Draft' ? ' · rascunho' : ''}',
            onPrint: () => printPdf(context, 'Certificado ${c['reference']}', () async => buildCertificatePdf(await api.get('/api/sales/certificates/${c['id']}') as Map<String, dynamic>)),
          ),
    ];
  }

  /// Print shortcut inside the step card: the paper that step needs on the desk.
  Widget _cardPrint(String key, String label, Future<void> Function() onPressed) =>
      TextButton.icon(key: ValueKey(key), onPressed: onPressed, icon: const Icon(Icons.print_outlined), label: Text(label));

  List<Widget> _ofPrints(Map<String, dynamic> o) {
    final ofs = (o['lines'] as List).cast<Map<String, dynamic>>().where((l) => l['productionOrderId'] != null).fold(<int, String>{}, (m, l) => m..[l['productionOrderId'] as int] = '${l['productionReference']}');
    return [
      for (final e in ofs.entries)
        _cardPrint(
          'order-print-of-${e.key}',
          ofs.length == 1 ? 'Imprimir OF' : 'Imprimir ${e.value}',
          () => _printOf(e.key, e.value),
        ),
    ];
  }

  Widget _nextStep(Map<String, dynamic> o) {
    final pct = '${(_n(o['progress']) * 100).round()}%';
    FilledButton primary(String key, String label, IconData icon, VoidCallback onPressed) =>
        FilledButton.icon(key: ValueKey(key), onPressed: onPressed, icon: Icon(icon), label: Text(label));
    return switch (o['status']) {
      'Created' => NextStepCard(
        title: 'Liberar para produção',
        message: 'O estoque livre é reservado para o pedido e as OFs do restante vão para o PCP.',
        actions: [if (s.canReleaseSales) primary('order-release', 'Liberar para produção', Icons.play_arrow, _release), _cardPrint('order-print-card', 'Imprimir pedido interno', _printSalesOrder)],
      ),
      'Released' || 'PartiallyShipped' when o['ready'] == true && !_certified => NextStepCard(
        title: 'Produção pronta · falta o certificado',
        message: 'Emita o certificado de qualidade antes de programar a entrega. Se o cliente não exige certificado, dispense.',
        tone: Tone.warning,
        actions: [
          if (s.canCertificate) primary('order-certificate', 'Emitir certificado', Icons.verified_outlined, _newCertificate),
          if (s.canShip)
            OutlinedButton.icon(
              key: const ValueKey('order-deliver'),
              onPressed: _planDelivery,
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Programar entrega'),
            ),
          if (s.canIssueCertificate)
            TextButton(key: const ValueKey('order-certificate-waive'), onPressed: () => _waiveCertificate(true), child: const Text('Dispensar certificado')),
          ..._ofPrints(o),
          ..._closeAction(),
        ],
      ),
      'Released' || 'PartiallyShipped' when o['ready'] == true => NextStepCard(
        title: 'Pronto para expedir',
        message: 'Há produto acabado para os itens em aberto. Programe a entrega.',
        tone: Tone.success,
        actions: [if (s.canShip) primary('order-deliver', 'Programar entrega', Icons.local_shipping, _planDelivery), ..._closeAction(), ..._ofPrints(o)],
      ),
      'Released' || 'PartiallyShipped' => NextStepCard(
        title: 'Em produção · $pct pronto',
        message: o['late'] == true
            ? 'Há itens com data de entrega vencida.'
            : 'Acompanhe as OFs abaixo. Dá para programar uma entrega parcial do que já está pronto.',
        tone: o['late'] == true ? Tone.danger : Tone.progress,
        actions: [
          if (s.canShip)
            OutlinedButton.icon(
              key: const ValueKey('order-deliver'),
              onPressed: _planDelivery,
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Programar entrega'),
            ),
          ..._closeAction(),
          ..._ofPrints(o),
        ],
      ),
      'Shipped' => NextStepCard(
        title: 'Tudo expedido',
        message: 'Confirme o recebimento pelo cliente em cada entrega.',
        tone: Tone.progress,
        actions: [
          // The confirmation lives on the delivery: one click from here instead of hunting for the small icon in the table.
          for (final d in (o['deliveries'] as List).cast<Map<String, dynamic>>().where((d) => d['status'] == 'Shipped'))
            FilledButton.icon(
              key: ValueKey('order-confirm-delivery-${d['id']}'),
              onPressed: () => unawaited(openDelivery(context, s, d['id'] as int).then((_) => _load())),
              icon: const Icon(Icons.task_alt),
              label: Text('Confirmar recebimento · ${d['reference']}'),
            ),
        ],
      ),
      'Delivered' => const NextStepCard(title: 'Pedido entregue', message: 'Todas as entregas foram confirmadas.', tone: Tone.success),
      _ => NextStepCard(title: 'Pedido cancelado', message: '${o['statusReason'] ?? ''}', tone: Tone.danger),
    };
  }

  /// One print entry in the bar. Before production it prints the pedido interno de venda; with OFs in production it is a menu with the
  /// pedido and each OF, named, so the bar never fills with identical icons.
  List<Widget> _printActions(Map<String, dynamic> o) {
    final ofs = (o['lines'] as List)
        .cast<Map<String, dynamic>>()
        .where((l) => l['productionOrderId'] != null)
        .fold(<int, String>{}, (m, l) => m..[l['productionOrderId'] as int] = '${l['productionReference']}');
    final inProduction = ['Released', 'PartiallyShipped'].contains(o['status']);
    if (!inProduction || ofs.isEmpty) {
      return [PrintButton(key: const ValueKey('print-sales-order'), name: 'Pedido de venda ${o['reference']}', doneKey: _salesKey, builder: () => buildSalesOrderPdf(api, o))];
    }
    return [
      PopupMenuButton<VoidCallback>(
        key: const ValueKey('print-menu'),
        tooltip: 'Imprimir',
        icon: const Icon(Icons.print_outlined),
        onSelected: (f) => f(),
        itemBuilder: (_) => [
          PopupMenuItem(
            key: const ValueKey('print-sales-order'),
            value: () => unawaited(_printSalesOrder()),
            child: const ListTile(leading: Icon(Icons.receipt_long_outlined), title: Text('Pedido interno de venda')),
          ),
          for (final e in ofs.entries)
            PopupMenuItem(
              key: ValueKey('print-menu-of-${e.key}'),
              value: () => unawaited(_printOf(e.key, e.value)),
              child: ListTile(leading: const Icon(Icons.precision_manufacturing_outlined), title: Text('Ordem de fabricação ${e.value}')),
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final danger = Theme.of(context).colorScheme.error;
    final menu = <PopupMenuEntry<VoidCallback>>[
      if (s.canSell && status == 'Created')
        PopupMenuItem(
          value: _edit,
          child: const ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar')),
        ),
      if (s.canShip && ['Released', 'PartiallyShipped'].contains(status))
        PopupMenuItem(
          value: _planDelivery,
          child: const ListTile(leading: Icon(Icons.local_shipping_outlined), title: Text('Programar entrega')),
        ),
      if (s.canSell && ['Released', 'PartiallyShipped'].contains(status))
        PopupMenuItem(
          value: _reschedule,
          child: const ListTile(leading: Icon(Icons.event_repeat), title: Text('Alterar prazos ou pedido do cliente')),
        ),
      if (s.canSell && status == 'PartiallyShipped')
        PopupMenuItem(
          value: _closeBalance,
          child: ListTile(leading: Icon(Icons.playlist_remove, color: danger), iconColor: danger, textColor: danger, title: const Text('Encerrar saldo')),
        ),
      if (s.canSell && ['Created', 'Released', 'PartiallyShipped'].contains(status))
        PopupMenuItem(
          value: _cancel,
          child: ListTile(leading: const Icon(Icons.block), iconColor: danger, textColor: danger, title: const Text('Cancelar pedido')),
        ),
    ];
    return RecordShortcuts(
      onRefresh: _refresh,
      onPrint: o == null ? null : () => unawaited(_printSalesOrder()),
      child: Scaffold(
      appBar: AppBar(
        title: Text(o == null ? 'Pedido de venda' : '${o['reference']} · ${o['customerName']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (o != null) RefreshButton(onPressed: _refresh),
          if (o != null)
            RelatedMenu(
              links: [
                RelatedLink(Icons.business_outlined, 'Cliente: ${o['customerName']}', () => openCustomer(context, s, o['customerId'] as int)),
                if (o['quoteId'] != null) RelatedLink(Icons.request_quote_outlined, 'Orçamento ${o['quoteReference'] ?? ''}', () => openQuote(context, s, o['quoteId'] as int)),
              ],
            ),
          if (o != null) ..._printActions(o),
          if (menu.isNotEmpty) PopupMenuButton<VoidCallback>(key: const ValueKey('order-menu'), onSelected: (f) => f(), itemBuilder: (_) => menu),
        ],
      ),
      body: _error != null && o == null
          ? LoadError(message: _error!, onRetry: _load)
          : o == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: () => _load(report: true), child: _body(o)),
      ),
    );
  }

  /// Each step of the path opens the record it stands for: the quote, the OFs, the certificates, the deliveries.
  VoidCallback? _stepLink(int i, Map<String, dynamic> o, List<Map<String, dynamic>> lines, List<Map<String, dynamic>> deliveries) {
    switch (i) {
      case <= 3:
        if (o['quoteId'] == null) return null;
        return () => unawaited(openQuote(context, s, o['quoteId'] as int).then((_) => _load()));
      case 5:
        final ofs = lines.where((l) => l['productionOrderId'] != null).fold(<int, String>{}, (m, l) => m..[l['productionOrderId'] as int] = '${l['productionReference']}');
        return stepLink(context, 'Abrir qual ordem de fabricação?', [
          for (final e in ofs.entries) (label: e.value, open: () => openProductionOrder(context, s, e.key).then((_) => _load())),
        ]);
      case 6:
        return stepLink(context, 'Abrir qual certificado?', [
          for (final c in _certs.where((c) => c['status'] != 'Cancelled'))
            (label: '${c['reference']} · ${c['description']}', open: () => openCertificate(context, s, c['id'] as int).then((_) => _load())),
        ]);
      case 7:
        return stepLink(context, 'Abrir qual entrega?', [
          for (final d in deliveries.where((d) => d['status'] != 'Cancelled'))
            (label: '${d['reference']} · ${deliveryStatuses[d['status']] ?? d['status']}', open: () => openDelivery(context, s, d['id'] as int).then((_) => _load())),
        ]);
      default:
        return null;
    }
  }

  Widget _body(Map<String, dynamic> o) {
    final (step, failed) = orderPath(o['status'], ready: o['ready'] == true, certified: _certified);
    final lines = (o['lines'] as List).cast<Map<String, dynamic>>();
    final deliveries = (o['deliveries'] as List).cast<Map<String, dynamic>>();
    final credit = o['credit'] as Map<String, dynamic>;
    final released = !['Created', 'Cancelled'].contains(o['status']);
    return SideBySide(
      main: [
        _orderHeader(o, credit),
        gap,
        StagePath(
          steps: flowSteps,
          current: step,
          failedLabel: failed,
          onStep: (i) => _stepLink(i, o, lines, deliveries),
        ),
        gap,
        _nextStep(o),
        // Same order as the quote (header, path, next step, items, details); the papers come after the records they belong to.
        gap,
        _itemsSection(o, lines),
        if (released) ...[gap, _production(lines)],
        gap,
        _deliveriesSection(o, deliveries),
        if (released) ...[gap, _certificatesSection(o)],
        if (o['status'] != 'Cancelled') ...[gap, PrintPanel(docs: _printDocs(o))],
        gap,
        _detailsSection(o),
      ],
      side: [
        Section(
          title: 'Histórico',
          child: TimelineView(entries: timeline(o['history'] as List)),
        ),
      ],
    );
  }

  Widget _orderHeader(Map<String, dynamic> o, Map<String, dynamic> credit) =>
    RecordHeader(
      icon: Icons.receipt_long_outlined,
      kind: 'Pedido de venda',
      title: '${o['reference']}',
      badge: StatusBadge(salesOrderStatuses[o['status']] ?? '${o['status']}', tone: orderTone(o['status'])),
      amount: fmtMoney(o['total']),
      fields: [
        ('Cliente', '${o['customerName']}'),
        ('Pedido do cliente', fmt(o['customerPo'])),
        ('Faturar para', billToLabels[o['billTo']] ?? fmt(o['billTo'])),
        ('Origem', orderOrigins[o['origin']] ?? fmt(o['origin'])),
        ('Responsável de vendas', fmt(o['salesperson'])),
        ('Prazo', fmt(o['paymentTermName'] ?? o['customPaymentTerm'])),
        ('Frete', freightTerms[o['freight']] ?? fmt(o['freight'])),
        ('Orçamento', fmt(o['quoteReference'])),
        ('Crédito', credit['limit'] == null ? 'Sem limite' : '${fmtMoney(credit['open'])} em pedidos + ${fmtMoney(credit['receivable'] ?? 0)} a receber, de ${fmtMoney(credit['limit'])}'),
      ],
    );

  Widget _itemsSection(Map<String, dynamic> o, List<Map<String, dynamic>> lines) =>
    Section(
      title: 'Itens (${lines.length})',
      actions: [
        if (o['quoteId'] != null)
          TextButton.icon(
            onPressed: () => openQuote(context, s, o['quoteId'] as int).then((_) => _load()),
            icon: const Icon(Icons.request_quote_outlined),
            label: const Text('Ver orçamento'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OrderItems(lines: lines),
          const SizedBox(height: 14),
          // The products and IPI sit right under the lines they add up, as on the quote (the emphasised row is the total of the paper).
          TotalsBlock([
            ('Produtos', fmtMoney(o['products'])),
            ('IPI', fmtMoney(o['ipi'])),
            ('Total', fmtMoney(o['total'])),
            if (lines.any((l) => _n(l['shipped']) > 0)) ('Saldo a expedir', fmtMoney(lines.fold<num>(0, (a, l) => a + _n(l['balanceValue'])))),
          ], strong: 2),
        ],
      ),
    );

  Widget _deliveriesSection(Map<String, dynamic> o, List<Map<String, dynamic>> deliveries) =>
    Section(
      title: 'Entregas (${deliveries.length})',
      actions: [
        if (s.canShip && ['Released', 'PartiallyShipped'].contains(o['status']))
          FilledButton.tonalIcon(onPressed: _planDelivery, icon: const Icon(Icons.add), label: const Text('Programar')),
      ],
      child: SimpleTable(
        columns: [
          col('Entrega', 'reference'),
          dateCol('Data', 'plannedDate'),
          labelCol('Situação', 'status', deliveryStatuses),
          col('NF', 'invoiceNumber'),
          col('Volumes', 'packages', numeric: true),
        ],
        rows: deliveries,
        actions: (d) => [
          IconButton(
            tooltip: 'Abrir',
            icon: const Icon(Icons.open_in_new, size: 20),
            onPressed: () => openDelivery(context, s, d['id'] as int).then((_) => _load()),
          ),
        ],
      ),
    );

  Widget _certificatesSection(Map<String, dynamic> o) =>
    Section(
      title: 'Certificados de qualidade (${_certs.length})',
      actions: [
        if (o['certificateWaived'] == true)
          TextButton(onPressed: s.canIssueCertificate ? () => _waiveCertificate(false) : null, child: const Text('Dispensado · exigir novamente'))
        else if (s.canCertificate && status != 'Cancelled')
          FilledButton.tonalIcon(
            key: const ValueKey('order-new-certificate'),
            onPressed: _newCertificate,
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
          col('Entrega', 'deliveryReference'),
          col('NF', 'invoiceNumber'),
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

  Widget _detailsSection(Map<String, dynamic> o) =>
    Section(
      title: 'Detalhes',
      child: InfoGrid([
        ('Local de entrega', fmt(o['addressText'])),
        ('Observações', fmt(o['notes'])),
        ('Criado', '${fmt(o['createdBy'])} · ${fmtDate(o['createdAt'])}'),
        ('Liberado', o['releasedAt'] == null ? '' : '${fmt(o['releasedBy'])} · ${fmtDate(o['releasedAt'])}'),
      ]),
    );

  Widget _production(List<Map<String, dynamic>> lines) => Section(
    title: 'Produção e disponibilidade',
    child: Column(
      children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: LayoutBuilder(builder: (context, box) => _productionRow(l, narrow: box.maxWidth < 640)),
          ),
      ],
    ),
  );

  /// One item's production line. Wide: info, badges and the progress bar side by side. Narrow: the info above, the badges wrapping, the bar below.
  Widget _productionRow(Map<String, dynamic> l, {required bool narrow}) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${l['sequence']} · ${l['productCode']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          [
            if (_n(l['fromStock']) > 0) '${fmt(l['fromStock'])} do estoque',
            if (l['productionReference'] != null) '${fmt(_n(l['quantity']) - _n(l['fromStock']))} na ${l['productionReference']}',
          ].join(' + '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
    final badges = <Widget>[
      if (l['productionReference'] != null)
        InkWell(
          onTap: () => openProductionOrder(context, s, l['productionOrderId'] as int).then((_) => _load()),
          child: StatusBadge(
            '${l['productionReference']} · ${productionStatuses[l['productionStatus']] ?? l['productionStatus']}',
            tone: productionTone(l['productionStatus']),
            icon: Icons.open_in_new,
          ),
        ),
      if (l['productionOrderId'] != null)
        PrintButton(
          key: ValueKey('print-of-${l['productionOrderId']}'),
          name: 'Ordem de produção ${l['productionReference']}',
          doneKey: _ofKey(l['productionOrderId']),
          builder: () async => buildProductionOrderPdf(api, await api.get('/api/production/orders/${l['productionOrderId']}') as Map<String, dynamic>),
        ),
      if (l['ready'] == true && _n(l['remaining']) > 0) const StatusBadge('Pronto', tone: Tone.success, icon: Icons.check),
    ];
    final meter = ProgressMeter(
      _n(l['quantity']) == 0
          ? 0
          : (_n(l['shipped']) > _n(l['fromStock']) + _n(l['produced']) ? _n(l['shipped']) : _n(l['fromStock']) + _n(l['produced'])) / _n(l['quantity']),
      label: '${fmt(_n(l['fromStock']) + _n(l['produced']))}/${fmt(l['quantity'])} · exp. ${fmt(l['shipped'])}',
    );
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          info,
          if (badges.isNotEmpty) Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: badges),
          const SizedBox(height: 4),
          meter,
        ],
      );
    }
    return Row(
      children: [
        SizedBox(width: 220, child: info),
        for (final b in badges) Padding(padding: const EdgeInsets.only(right: 8), child: b),
        Expanded(child: meter),
      ],
    );
  }
}

/// The items of an order: a table with only the columns the user acts on (the dimensions, standard, IPI and feasibility ride under the product), or a
/// card per item when the room is narrow.
class _OrderItems extends StatelessWidget {
  const _OrderItems({required this.lines});

  final List<Map<String, dynamic>> lines;

  static String _product(Map<String, dynamic> l) => '${l['productCode']}${l['customerPartNumber'] == null ? '' : ' (${l['customerPartNumber']})'}';

  /// The grey line under the description: measures, standard, the material need and the feasibility study, whichever exist.
  static String _technical(Map<String, dynamic> l) {
    final spec = l['spec'];
    final need = spec is Map ? spec['materialNeedKg'] : null;
    return [
      _measures(spec),
      _standard(spec),
      if (need != null) 'MP ${fmt(need)} kg',
      if (l['feasibilityReference'] != null) 'Viabilidade ${l['feasibilityReference']}',
    ].where((e) => e.isNotEmpty).join('  ·  ');
  }

  static String _price(Map<String, dynamic> l) => fmtNum(l['unitPrice'], 4);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) => box.maxWidth < 820 ? _cards(context) : _table(context));

  Widget _table(BuildContext context) {
    final theme = Theme.of(context);
    final grey = TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant);
    Widget cell(Widget child, {bool right = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Align(alignment: right ? Alignment.centerRight : Alignment.centerLeft, child: child),
    );
    Widget head(String t, {bool right = false}) => cell(Text(t, style: const TextStyle(fontWeight: FontWeight.w600)), right: right);
    final line = BorderSide(color: theme.dividerColor, width: 0.8);
    return Table(
      key: const ValueKey('order-items'),
      columnWidths: const {
        0: FixedColumnWidth(46),
        1: FlexColumnWidth(),
        2: FixedColumnWidth(110),
        3: FixedColumnWidth(110),
        4: FixedColumnWidth(90),
        5: FixedColumnWidth(84),
        6: FixedColumnWidth(84),
        7: FixedColumnWidth(118),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      border: TableBorder(horizontalInside: line, bottom: line),
      children: [
        TableRow(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.colorScheme.outline, width: 1.2))),
          children: [
            head('Item'),
            head('Produto'),
            head('Qtd.', right: true),
            head('Preço', right: true),
            head('Entrega', right: true),
            head('Expedido', right: true),
            head('Saldo', right: true),
            head('Total', right: true),
          ],
        ),
        for (final l in lines)
          TableRow(
            children: [
              cell(Text('${l['sequence']}')),
              cell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_product(l), style: const TextStyle(fontWeight: FontWeight.w600)),
                    if ('${l['description'] ?? ''}'.isNotEmpty) Text('${l['description']}'),
                    if (_technical(l).isNotEmpty) Text(_technical(l), style: grey),
                  ],
                ),
              ),
              cell(Text('${fmt(l['quantity'])} ${l['unit']}'), right: true),
              cell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [Text(_price(l)), if (_n(l['ipiPercent']) > 0) Text('IPI ${fmt(l['ipiPercent'])}%', style: grey)],
                ),
                right: true,
              ),
              cell(Text(fmtDay(l['dueDate'])), right: true),
              cell(Text(fmt(l['shipped'])), right: true),
              cell(Text(fmt(l['remaining']), style: const TextStyle(fontWeight: FontWeight.w600)), right: true),
              cell(Text(fmtMoney(l['total'])), right: true),
            ],
          ),
      ],
    );
  }

  Widget _cards(BuildContext context) {
    final theme = Theme.of(context);
    final grey = TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant);
    return Column(
      key: const ValueKey('order-items'),
      children: [
        for (final l in lines)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${l['sequence']} · ${_product(l)}', style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text(fmtMoney(l['total']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                if ('${l['description'] ?? ''}'.isNotEmpty) Text('${l['description']}'),
                if (_technical(l).isNotEmpty) Text(_technical(l), style: grey),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 2,
                  children: [
                    Text('Qtd. ${fmt(l['quantity'])} ${l['unit']}', style: grey),
                    Text('Preço ${_price(l)}', style: grey),
                    Text('Entrega ${fmtDay(l['dueDate'])}', style: grey),
                    Text('Expedido ${fmt(l['shipped'])}', style: grey),
                    Text('Saldo ${fmt(l['remaining'])}', style: grey),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DeliveryDialog extends StatefulWidget {
  const _DeliveryDialog({required this.order, required this.lines});

  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> lines;

  @override
  State<_DeliveryDialog> createState() => _DeliveryDialogState();
}

class _DeliveryDialogState extends State<_DeliveryDialog> {
  late final _date = TextEditingController(text: fmtDay(isoDate(DateTime.now())));
  final _notes = TextEditingController();
  late final _qty = {
    for (final l in widget.lines)
      l['id'] as int: TextEditingController(
        text: fmt(
          _n(l['remaining']) - _n(l['planned']) > _n(l['available']) && _n(l['available']) > 0 ? _n(l['available']) : _n(l['remaining']) - _n(l['planned']),
        ),
      ),
  };
  String? _error;

  @override
  void dispose() {
    for (final c in [_date, _notes, ..._qty.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(parseDate(_date.text) ?? '') ?? DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: current, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked != null && mounted) setState(() => _date.text = fmtDay(isoDate(picked)));
  }

  void _ok() {
    final date = parseDate(_date.text);
    if (date == null) return setState(() => _error = 'Data inválida');
    final lines = <Map<String, dynamic>>[];
    for (final l in widget.lines) {
      final text = _qty[l['id']]!.text.trim();
      if (text.isEmpty) continue;
      final q = parseDecimal(text);
      if (q == null || q < 0) return setState(() => _error = 'Item ${l['sequence']}: quantidade inválida');
      final open = _n(l['remaining']) - _n(l['planned']);
      if (q > open) return setState(() => _error = 'Item ${l['sequence']}: a quantidade passa do saldo a programar (${fmt(open)} ${l['unit']})');
      if (q > 0) lines.add({'orderLineId': l['id'], 'quantity': q});
    }
    if (lines.isEmpty) return setState(() => _error = 'Informe a quantidade de ao menos um item');
    Navigator.pop(context, {'plannedDate': date, 'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(), 'lines': lines});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Programar entrega · ${widget.order['reference']}'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('dl-date'),
                    controller: _date,
                    keyboardType: TextInputType.datetime,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Data *',
                      hintText: 'dd/mm/aaaa',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(key: const ValueKey('dl-date-pick'), tooltip: 'Escolher a data', icon: const Icon(Icons.calendar_month_outlined), onPressed: _pickDate),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final l in widget.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${l['sequence']} · ${l['productCode']} · ${l['description']}', overflow: TextOverflow.ellipsis),
                          // The text keeps the theme's own colour (contrast); the icon and the word carry the warning.
                          Row(
                            children: [
                              if (_n(l['available']) < _n(l['remaining']) - _n(l['planned'])) ...[
                                Icon(Icons.warning_amber_rounded, size: 15, color: toneAccent(context, Tone.warning)),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  'Saldo ${fmt(_n(l['remaining']) - _n(l['planned']))} ${l['unit']} · disponível ${fmt(l['available'])}'
                                  '${_n(l['available']) < _n(l['remaining']) - _n(l['planned']) ? ' (menos que o saldo)' : ''}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        key: ValueKey('dl-qty-${l['id']}'),
                        controller: _qty[l['id']],
                        textAlign: TextAlign.right,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _ok(),
                        decoration: InputDecoration(labelText: 'Qtd. (${l['unit']})', border: const OutlineInputBorder(), isDense: true),
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Observações', border: OutlineInputBorder(), isDense: true),
            ),
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
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(key: const ValueKey('delivery-ok'), onPressed: _ok, child: const Text('Programar')),
    ],
  );
}

/// Confirmation with a list of consequences, a required reason and an optional extra choice. [danger] paints the confirm button as destructive.
class ReasonDialog extends StatefulWidget {
  const ReasonDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.details,
    this.reasonLabel = 'Motivo',
    this.optionLabel,
    this.optionHelp,
    this.danger = true,
  });

  final String title;
  final String confirmLabel;
  final String reasonLabel;
  final List<String> details;
  final String? optionLabel;
  final String? optionHelp;
  final bool danger;

  @override
  State<ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<ReasonDialog> {
  final _reason = TextEditingController();
  bool _option = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.warning_amber_rounded),
    title: Text(widget.title),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final d in widget.details)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $d'),
              ),
            if (widget.optionLabel != null)
              CheckboxListTile(
                key: const ValueKey('reason-option'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _option,
                onChanged: (v) => setState(() => _option = v ?? false),
                title: Text(widget.optionLabel!),
                subtitle: widget.optionHelp == null ? null : Text(widget.optionHelp!),
              ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('reason-field'),
              controller: _reason,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: widget.reasonLabel, border: const OutlineInputBorder()),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(
        key: const ValueKey('confirm-step'),
        style: widget.danger ? dangerButtonStyle(context) : null,
        onPressed: _reason.text.trim().isEmpty ? null : () => Navigator.pop(context, (reason: _reason.text.trim(), option: _option)),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
