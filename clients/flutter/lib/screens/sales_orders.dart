import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../reports/print_docs.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/pipeline.dart';
import '../widgets/record_list.dart';
import 'production_orders.dart';
import 'sales_common.dart';
import 'sales_quotes.dart';

num _n(Object? v) => v is num ? v : 0;

class SalesOrdersScreen extends StatefulWidget {
  const SalesOrdersScreen({super.key, required this.session});

  final Session session;

  @override
  State<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

class _SalesOrdersScreenState extends State<SalesOrdersScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _status;
  bool _open = true;

  Future<void> _new() async {
    final o = await Navigator.of(context)
        .push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => QuoteEditorScreen(session: widget.session, asOrder: true)));
    _list.currentState?.reload();
    if (o == null || !mounted) return;
    await openSalesOrder(context, widget.session, o['id'] as int);
    _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: widget.session.api,
    path: '/api/sales/orders',
    query: {'status': _status, 'open': _open && _status == null ? true : null},
    searchHint: 'Pedido, cliente ou pedido do cliente',
    filters: [
      ChoiceFilter(label: 'Situação', value: _status, choices: salesOrderStatuses, onChanged: (v) => setState(() => _status = v)),
      FilterChip(label: const Text('Somente abertos'), selected: _open, onSelected: (v) => setState(() => _open = v)),
    ],
    fab: widget.session.canSell
        ? FloatingActionButton.extended(heroTag: 'new-sales-order', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Novo pedido'))
        : null,
    columns: [
      col('Pedido', 'reference'),
      col('Cliente', 'customerName'),
      col('Pedido do cliente', 'customerPo'),
      labelCol('Situação', 'status', salesOrderStatuses),
      moneyCol('Total', 'total'),
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
      _list.currentState?.reload();
    },
  );
}

class SalesOrderScreen extends StatefulWidget {
  const SalesOrderScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<SalesOrderScreen> createState() => _SalesOrderScreenState();
}

class _SalesOrderScreenState extends State<SalesOrderScreen> {
  Map<String, dynamic>? _o;
  String? _error;

  ApiClient get api => widget.session.api;
  Session get s => widget.session;
  String get base => '/api/sales/orders/${widget.id}';
  String get status => '${_o?['status']}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await api.get(base) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _o = o;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _release() async {
    var useStock = true;
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
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
            FilledButton(key: const ValueKey('confirm-step'), onPressed: () => Navigator.pop(c, true), child: const Text('Liberar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final r = await runAction(context, () => api.post('$base/release', {'useStock': useStock}), success: 'Pedido liberado para produção');
    if (r is Map<String, dynamic>) setState(() => _o = r);
  }

  Future<void> _planDelivery() async {
    final o = _o!;
    final lines = (o['lines'] as List).cast<Map<String, dynamic>>().where((l) => _n(l['remaining']) - _n(l['planned']) > 0).toList();
    if (lines.isEmpty) return showError(context, 'Todos os itens já estão programados ou expedidos');
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DeliveryDialog(order: o, lines: lines),
    );
    if (r == null || !mounted) return;
    final d = await runAction(context, () => api.post('$base/deliveries', r), success: 'Entrega programada');
    if (d is Map<String, dynamic>) {
      await _load();
      if (mounted) await openDelivery(context, s, d['id'] as int);
      _load();
    }
  }

  Future<void> _cancel() async {
    final reason = await promptText(context, title: 'Cancelar ${_o!['reference']}', label: 'Motivo', required: true, confirmLabel: 'Cancelar pedido');
    if (reason == null || !mounted) return;
    final r = await runAction(context, () => api.post('$base/cancel', {'reason': reason}), success: 'Pedido cancelado');
    if (r is Map<String, dynamic>) setState(() => _o = r);
  }

  Future<void> _edit() async {
    final r = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => QuoteEditorScreen(session: s, quote: _o, asOrder: true),
      ),
    );
    if (r != null) setState(() => _o = r);
  }

  Widget _nextStep(Map<String, dynamic> o) {
    final pct = '${(_n(o['progress']) * 100).round()}%';
    FilledButton primary(String key, String label, IconData icon, VoidCallback onPressed) =>
        FilledButton.icon(key: ValueKey(key), onPressed: onPressed, icon: Icon(icon), label: Text(label));
    return switch (o['status']) {
      'Created' => NextStepCard(
        title: 'Liberar para produção',
        message: 'O estoque livre é reservado para o pedido e as OFs do restante vão para o PCP.',
        actions: [if (s.canReleaseSales) primary('order-release', 'Liberar para produção', Icons.play_arrow, _release)],
      ),
      'Released' || 'PartiallyShipped' when o['ready'] == true => NextStepCard(
        title: 'Pronto para expedir',
        message: 'Há produto acabado para os itens em aberto. Programe a entrega.',
        tone: Tone.success,
        actions: [if (s.canShip) primary('order-deliver', 'Programar entrega', Icons.local_shipping, _planDelivery)],
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
        ],
      ),
      'Shipped' => const NextStepCard(title: 'Tudo expedido', message: 'Confirme o recebimento pelo cliente em cada entrega.', tone: Tone.progress),
      'Delivered' => const NextStepCard(title: 'Pedido entregue', message: 'Todas as entregas foram confirmadas.', tone: Tone.success),
      _ => NextStepCard(title: 'Pedido cancelado', message: '${o['statusReason'] ?? ''}', tone: Tone.danger),
    };
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
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
      if (s.canSell && ['Created', 'Released', 'PartiallyShipped'].contains(status))
        PopupMenuItem(
          value: _cancel,
          child: const ListTile(leading: Icon(Icons.block), title: Text('Cancelar pedido')),
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(o == null ? 'Pedido de venda' : '${o['reference']} · ${o['customerName']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (o != null) PrintButton(name: 'Pedido de venda ${o['reference']}', builder: () => buildSalesOrderPdf(api, o)),
          if (menu.isNotEmpty) PopupMenuButton<VoidCallback>(key: const ValueKey('order-menu'), onSelected: (f) => f(), itemBuilder: (_) => menu),
        ],
      ),
      body: _error != null && o == null
          ? Center(child: Text(_error!))
          : o == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(o)),
    );
  }

  Widget _body(Map<String, dynamic> o) {
    final (step, failed) = orderPath(o['status']);
    final lines = (o['lines'] as List).cast<Map<String, dynamic>>();
    final deliveries = (o['deliveries'] as List).cast<Map<String, dynamic>>();
    final credit = o['credit'] as Map<String, dynamic>;
    final released = !['Created', 'Cancelled'].contains(o['status']);
    return SideBySide(
      main: [
        RecordHeader(
          icon: Icons.receipt_long_outlined,
          kind: 'Pedido de venda',
          title: '${o['reference']}',
          badge: StatusBadge(salesOrderStatuses[o['status']] ?? '${o['status']}', tone: orderTone(o['status'])),
          amount: fmtMoney(o['total']),
          fields: [
            ('Cliente', '${o['customerName']}'),
            ('Pedido do cliente', fmt(o['customerPo'])),
            ('Prazo', fmt(o['paymentTermName'] ?? o['customPaymentTerm'])),
            ('Frete', freightTerms[o['freight']] ?? fmt(o['freight'])),
            ('Orçamento', fmt(o['quoteReference'])),
            ('Crédito', credit['limit'] == null ? 'Sem limite' : '${fmtMoney(credit['open'])} em aberto de ${fmtMoney(credit['limit'])}'),
          ],
        ),
        gap,
        StagePath(steps: flowSteps, current: step, failedLabel: failed),
        gap,
        _nextStep(o),
        if (released) ...[gap, _production(lines)],
        gap,
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
          child: SimpleTable(
            columns: [
              col('Item', 'sequence'),
              ColumnSpec('Produto', (e) => '${e['productCode']}${e['customerPartNumber'] == null ? '' : ' (${e['customerPartNumber']})'}'),
              col('Descrição', 'description'),
              ColumnSpec('Qtd.', (e) => '${fmt(e['quantity'])} ${e['unit']}', numeric: true),
              ColumnSpec('Preço', (e) => fmtNum(e['unitPrice'], 4), numeric: true),
              col('IPI %', 'ipiPercent', numeric: true),
              dateCol('Entrega', 'dueDate'),
              moneyCol('Total', 'total'),
              col('Expedido', 'shipped', numeric: true),
              col('Saldo', 'remaining', numeric: true),
            ],
            rows: lines,
          ),
        ),
        gap,
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
              col('Transportadora', 'carrier'),
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
        ),
        gap,
        Section(
          title: 'Detalhes',
          child: InfoGrid([
            ('Local de entrega', fmt(o['addressText'])),
            ('Observações', fmt(o['notes'])),
            ('Criado', '${fmt(o['createdBy'])} · ${fmtDate(o['createdAt'])}'),
            ('Liberado', o['releasedAt'] == null ? '' : '${fmt(o['releasedBy'])} · ${fmtDate(o['releasedAt'])}'),
            ('Produtos', fmtMoney(o['products'])),
            ('IPI', fmtMoney(o['ipi'])),
          ]),
        ),
      ],
      side: [
        Section(
          title: 'Histórico',
          child: TimelineView(entries: timeline(o['history'] as List)),
        ),
      ],
    );
  }

  Widget _production(List<Map<String, dynamic>> lines) => Section(
    title: 'Produção e disponibilidade',
    child: Column(
      children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 220,
                  child: Column(
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
                  ),
                ),
                if (l['productionReference'] != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => openProductionOrder(context, s, l['productionOrderId'] as int).then((_) => _load()),
                      child: StatusBadge(
                        '${l['productionReference']} · ${productionStatuses[l['productionStatus']] ?? l['productionStatus']}',
                        tone: productionTone(l['productionStatus']),
                        icon: Icons.open_in_new,
                      ),
                    ),
                  ),
                if (l['ready'] == true && _n(l['remaining']) > 0)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: StatusBadge('Pronto', tone: Tone.success, icon: Icons.check),
                  ),
                Expanded(
                  child: ProgressMeter(
                    _n(l['quantity']) == 0
                        ? 0
                        : (_n(l['shipped']) > _n(l['fromStock']) + _n(l['produced']) ? _n(l['shipped']) : _n(l['fromStock']) + _n(l['produced'])) /
                              _n(l['quantity']),
                    label: '${fmt(_n(l['fromStock']) + _n(l['produced']))}/${fmt(l['quantity'])} · exp. ${fmt(l['shipped'])}',
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
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
  final _carrier = TextEditingController();
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
    for (final c in [_date, _carrier, _notes, ..._qty.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _ok() {
    final date = parseDate(_date.text);
    if (date == null) return setState(() => _error = 'Data inválida');
    final lines = [
      for (final e in _qty.entries)
        if ((parseDecimal(e.value.text) ?? 0) > 0) {'orderLineId': e.key, 'quantity': parseDecimal(e.value.text)},
    ];
    if (lines.isEmpty) return setState(() => _error = 'Informe a quantidade de ao menos um item');
    Navigator.pop(context, {
      'plannedDate': date,
      'carrier': _carrier.text.trim().isEmpty ? null : _carrier.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'lines': lines,
    });
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
                    controller: _date,
                    decoration: const InputDecoration(labelText: 'Data *', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _carrier,
                    decoration: const InputDecoration(labelText: 'Transportadora', border: OutlineInputBorder(), isDense: true),
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
                          Text(
                            'Saldo ${fmt(_n(l['remaining']) - _n(l['planned']))} ${l['unit']} · disponível ${fmt(l['available'])}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: _n(l['available']) < _n(l['remaining']) - _n(l['planned']) ? toneAccent(context, Tone.warning) : null),
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
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
      FilledButton(key: const ValueKey('delivery-ok'), onPressed: _ok, child: const Text('Programar')),
    ],
  );
}
