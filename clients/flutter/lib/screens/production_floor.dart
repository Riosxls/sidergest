import 'dart:async';

import 'package:flutter/material.dart';

import '../entities.dart';
import '../labels.dart';
import '../reports/nf_doc.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/record_list.dart';
import 'orders.dart' show isLate;
import 'production_orders.dart';

const reportFields = [
  FieldSpec('goodQuantity', 'Quantidade boa', type: FieldType.decimal, required: true),
  FieldSpec('scrapQuantity', 'Refugo', type: FieldType.decimal, defaultValue: 0),
  // Scrap reasons and downtime reasons share one list on the server; each lookup asks for its own kind.
  FieldSpec(
    'scrapOccurrenceId',
    'Motivo do refugo',
    type: FieldType.lookup,
    lookup: LookupSpec('/api/production/occurrences', query: {'kind': 'Scrap'}),
  ),
  FieldSpec(
    'employeeId',
    'Funcionário',
    type: FieldType.lookup,
    lookup: LookupSpec('/api/production/employees', query: {'active': true}),
  ),
  FieldSpec('shiftId', 'Turno', type: FieldType.lookup, lookup: LookupSpec('/api/production/shifts')),
  FieldSpec('startTime', 'Início', type: FieldType.time),
  FieldSpec('endTime', 'Fim', type: FieldType.time),
  // What the operator rarely fills in stays folded under "Mais campos".
  FieldSpec('machineId', 'Máquina', type: FieldType.lookup, lookup: LookupSpec('/api/machines'), hint: 'Vazio = máquina da operação', advanced: true),
  FieldSpec('hours', 'Horas trabalhadas', type: FieldType.decimal, hint: 'Vazio = calculado pelo início/fim', advanced: true),
  FieldSpec('setupHours', 'Setup (h)', type: FieldType.decimal, advanced: true),
  FieldSpec('operators', 'Operadores', type: FieldType.decimal, advanced: true),
  FieldSpec('downtimeHours', 'Parada (h)', type: FieldType.decimal, advanced: true),
  FieldSpec(
    'downtimeOccurrenceId',
    'Motivo da parada',
    type: FieldType.lookup,
    lookup: LookupSpec('/api/production/occurrences', query: {'kind': 'Downtime'}),
    advanced: true,
  ),
  FieldSpec('weightKg', 'Peso (kg)', type: FieldType.decimal, advanced: true),
  FieldSpec('notes', 'Observações', advanced: true),
];

Future<Map<String, dynamic>?> showReportForm(BuildContext context, Session s, Map<String, dynamic> order, Map<String, dynamic> op) async {
  final r = await submitForm(
    context,
    api: s.api,
    title: 'Apontamento · ${order['reference']} · operação ${op['sequence']}${op['description'] == null ? '' : ' ${op['description']}'}',
    fields: const [
      FieldSpec('date', 'Data', type: FieldType.date, required: true),
      ...reportFields,
    ],
    initial: {'date': isoDate(DateTime.now()), 'scrapQuantity': 0, 'goodQuantity': (op['remaining'] as num? ?? 0) > 0 ? op['remaining'] : null},
    submit: (b) =>
        s.api.post('/api/production/reports', {...b, 'orderId': order['id'], 'operationSequence': op['sequence'], 'scrapQuantity': b['scrapQuantity'] ?? 0}),
  );
  if (r != null && context.mounted) {
    final left = ((op['remaining'] as num?) ?? 0) - ((r['goodQuantity'] as num?) ?? 0) - ((r['scrapQuantity'] as num?) ?? 0);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Apontamento registrado${op['remaining'] == null ? '' : ' · saldo da operação ${fmt(left < 0 ? 0 : left)}'}')));
  }
  return r;
}

/// Picks the operation of an open order and opens the report form on it. Only a running order takes reports.
Future<void> reportOnOrder(BuildContext context, Session s, Map<String, dynamic> order) async {
  if (!runningProductionStatuses.contains(order['status'])) {
    return showError(
      context,
      '${order['reference']} está ${(productionStatuses[order['status']] ?? '${order['status']}').toLowerCase()}: só OF liberada ou em produção recebe apontamento',
    );
  }
  final ops = (order['operations'] as List).cast<Map<String, dynamic>>().where((o) => o['external'] != true && ((o['remaining'] as num?) ?? 0) > 0).toList();
  if (ops.isEmpty) return showError(context, '${order['reference']} não tem operação interna com saldo para apontar');
  final op = ops.length == 1
      ? ops.first
      : await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (c) => SimpleDialog(
            title: Text('Operação · ${order['reference']}'),
            children: [
              for (final o in ops)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, o),
                  child: Text('${o['sequence']} · ${o['description'] ?? o['machineCode'] ?? ''} · saldo ${fmt(o['remaining'])}'),
                ),
            ],
          ),
        );
  if (op == null || !context.mounted) return;
  await showReportForm(context, s, order, op);
}

Future<void> newReport(BuildContext context, Session s) async {
  final picked = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => LookupPicker(api: s.api, path: '/api/production/orders', title: 'Ordem de fabricação', query: const {'open': true}),
  );
  if (picked == null || !context.mounted) return;
  final order = await runAction(context, () => s.api.get('/api/production/orders/${picked['id']}'));
  if (order is! Map<String, dynamic> || !context.mounted) return;
  await reportOnOrder(context, s, order);
}

/// Production reports list, optionally limited to one order.
class ReportsView extends StatefulWidget {
  const ReportsView({super.key, required this.session, this.order, this.onChanged});

  final Session session;
  final Map<String, dynamic>? order;
  final VoidCallback? onChanged;

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  final _list = GlobalKey<RecordListState>();
  String? _from;
  String? _to;

  Session get s => widget.session;

  Future<void> _new() async {
    final order = widget.order;
    if (order == null) {
      await newReport(context, s);
    } else {
      await reportOnOrder(context, s, order);
    }
    unawaited(_list.currentState?.reload());
    widget.onChanged?.call();
  }

  Future<void> _open(Map<String, dynamic> r) async {
    final cs = Theme.of(context).colorScheme;
    // In the standalone list the OF of a report is one tap away.
    final openOrder = widget.order == null && r['orderId'] is int;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Apontamento ${r['reference']} · op. ${r['operationSequence']}'),
        content: SizedBox(
          width: 520,
          child: InfoGrid([
            ('Data', fmtDay(r['date'])),
            ('Funcionário', fmt(r['employeeName'])),
            ('Máquina', fmt(r['machineCode'])),
            ('Horário', r['startTime'] == null ? '' : '${fmtTime(r['startTime'])} – ${fmtTime(r['endTime'])}'),
            ('Horas', fmt(r['hours'])),
            ('Setup (h)', fmt(r['setupHours'])),
            ('Operadores', fmt(r['operators'])),
            ('Boas', fmt(r['goodQuantity'])),
            ('Refugo', fmt(r['scrapQuantity'])),
            ('Parada (h)', fmt(r['downtimeHours'])),
            ('Peso (kg)', fmt(r['weightKg'])),
            ('Retorno de terceiro', r['outsideShipmentId'] == null ? '' : 'Remessa ${r['outsideShipmentId']}'),
            ('Observações', fmt(r['notes'])),
            ('Lançado', '${fmt(r['reportedBy'])} · ${fmtDate(r['reportedAt'])}'),
          ]),
        ),
        actions: [
          if (s.canProduce)
            TextButton(
              key: const ValueKey('report-delete'),
              onPressed: () => Navigator.pop(c, 'delete'),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Excluir'),
            ),
          if (openOrder)
            TextButton(key: const ValueKey('report-open-order'), onPressed: () => Navigator.pop(c, 'order'), child: Text('Abrir ${r['reference']}')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fechar')),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'order') {
      await openProductionOrder(context, s, r['orderId'] as int);
      unawaited(_list.currentState?.reload());
      return;
    }
    if (action != 'delete') return;
    if (!await confirm(context, 'Excluir este apontamento?') || !mounted) return;
    await runAction(context, () => s.api.delete('/api/production/reports/${r['id']}'), success: 'Apontamento excluído');
    unawaited(_list.currentState?.reload());
    widget.onChanged?.call();
  }

  /// Cancelling the picker keeps the date the chip already has; the chip's own x clears it.
  Future<void> _pickDate(bool from) async {
    final current = DateTime.tryParse((from ? _from : _to) ?? '');
    final d = await showDatePicker(context: context, initialDate: current ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    final iso = isoDate(d);
    if (from ? (_to != null && iso.compareTo(_to!) > 0) : (_from != null && iso.compareTo(_from!) < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A data inicial não pode ser depois da data final')));
      return;
    }
    setState(() => from ? _from = iso : _to = iso);
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return RecordList(
      key: _list,
      api: s.api,
      path: '/api/production/reports',
      query: {'orderId': order?['id'], 'from': _from, 'to': _to},
      searchable: false,
      emptyText: order == null ? 'Nenhum apontamento' : 'Nenhum apontamento nesta OF. Use "Apontar" na aba Operações ou o botão abaixo.',
      filtersActive: _from != null || _to != null,
      onClearFilters: () => setState(() {
        _from = null;
        _to = null;
      }),
      filters: [
        InputChip(
          avatar: const Icon(Icons.event, size: 18),
          label: Text(_from == null ? 'De' : 'De ${fmtDay(_from)}'),
          onPressed: () => _pickDate(true),
          onDeleted: _from == null ? null : () => setState(() => _from = null),
        ),
        InputChip(
          avatar: const Icon(Icons.event, size: 18),
          label: Text(_to == null ? 'Até' : 'Até ${fmtDay(_to)}'),
          onPressed: () => _pickDate(false),
          onDeleted: _to == null ? null : () => setState(() => _to = null),
        ),
      ],
      // On an order only a running one takes reports; on the standalone list the order is picked first.
      fab: s.canProduce && (order == null || runningProductionStatuses.contains(order['status']))
          ? FloatingActionButton.extended(
              heroTag: order == null ? 'new-report' : 'new-report-of',
              onPressed: _new,
              icon: const Icon(Icons.edit_note),
              label: Text(order == null ? 'Novo apontamento' : 'Apontar operação'),
            )
          : null,
      columns: [
        dateCol('Data', 'date'),
        col('OF', 'reference'),
        col('Op.', 'operationSequence'),
        col('Funcionário', 'employeeName'),
        col('Máquina', 'machineCode'),
        col('Boas', 'goodQuantity', numeric: true),
        col('Refugo', 'scrapQuantity', numeric: true),
        col('Horas', 'hours', numeric: true),
        col('Parada (h)', 'downtimeHours', numeric: true),
        col('Usuário', 'reportedBy'),
      ],
      onTap: _open,
    );
  }
}

/// Screen wrapper around [ReportsView].
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) => ReportsView(session: session);
}

/// Outside-processing shipments list, optionally limited to one order.
class ShipmentsView extends StatefulWidget {
  const ShipmentsView({super.key, required this.session, this.orderId, this.onChanged});

  final Session session;
  final int? orderId;
  final VoidCallback? onChanged;

  @override
  State<ShipmentsView> createState() => _ShipmentsViewState();
}

class _ShipmentsViewState extends State<ShipmentsView> {
  final _list = GlobalKey<RecordListState>();
  late bool _open = widget.orderId == null;

  Session get s => widget.session;

  bool _late(Map<String, dynamic> e) => e['dueDate'] != null && (e['open'] as num) > 0 && isLate(e['dueDate']);

  /// Only the actions that do something here: a return while the shipment is open, the OF when it is not already the page, the NF paper.
  Future<void> _tap(Map<String, dynamic> e) async {
    final canReturn = s.canProduce && (e['open'] as num) > 0;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canReturn)
              ListTile(
                key: const ValueKey('shipment-return'),
                leading: const Icon(Icons.assignment_returned_outlined),
                title: const Text('Registrar retorno'),
                onTap: () => Navigator.pop(ctx, 'return'),
              ),
            if (widget.orderId == null)
              ListTile(
                key: const ValueKey('shipment-open-order'),
                leading: const Icon(Icons.open_in_new),
                title: Text('Abrir ${e['reference']}'),
                onTap: () => Navigator.pop(ctx, 'order'),
              ),
            ListTile(leading: const Icon(Icons.print_outlined), title: const Text('Imprimir NF de remessa'), onTap: () => Navigator.pop(ctx, 'nf')),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'order') {
      await openProductionOrder(context, s, e['orderId'] as int);
      unawaited(_list.currentState?.reload());
      return;
    }
    if (action == 'nf') {
      await printNf(
        context,
        name: 'NF remessa ${e['reference']}',
        number: e['invoiceNumber'] == null ? '' : '${e['invoiceNumber']}',
        build: (f) => buildOutsideNfPdf(s.api, e, f),
      );
      return;
    }
    if (!canReturn) return;
    final r = await submitForm(
      context,
      api: s.api,
      title: 'Retorno de ${e['supplierName']} · ${e['reference']} op. ${e['operationSequence']} · em aberto ${fmt(e['open'])}',
      fields: [
        FieldSpec('date', 'Data', type: FieldType.date, required: true, defaultValue: isoDate(DateTime.now())),
        FieldSpec('goodQuantity', 'Quantidade boa', type: FieldType.decimal, required: true, defaultValue: e['open']),
        const FieldSpec('scrapQuantity', 'Refugo', type: FieldType.decimal, required: true, defaultValue: 0),
        const FieldSpec(
          'scrapOccurrenceId',
          'Motivo do refugo',
          type: FieldType.lookup,
          lookup: LookupSpec('/api/production/occurrences', query: {'kind': 'Scrap'}),
        ),
        // No default: a price of 0 would pass and zero the service cost of the OF.
        const FieldSpec(
          'serviceUnitPrice',
          'Preço do serviço (R\$/peça)',
          type: FieldType.decimal,
          required: true,
          hint: 'Valor por peça cobrado pelo fornecedor',
        ),
        const FieldSpec('invoiceNumber', 'NF de retorno'),
        const FieldSpec('notes', 'Observações', advanced: true),
      ],
      submit: (b) => s.api.post('/api/production/outside-shipments/${e['id']}/returns', b),
    );
    if (r == null) return;
    // The form is a dialog, so the list is not told that something changed: reload it here.
    unawaited(_list.currentState?.reload());
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: s.api,
    path: '/api/production/outside-shipments',
    query: {'orderId': widget.orderId, 'open': _open ? true : null},
    searchable: false,
    emptyText: 'Nenhuma remessa a terceiros',
    filtersActive: _open,
    onClearFilters: () => setState(() => _open = false),
    filters: [FilterChip(label: const Text('Somente em aberto'), selected: _open, onSelected: (v) => setState(() => _open = v))],
    // A shipment still open after its expected return date (sent + the supplier lead time of the operation) is late.
    rowColor: (context, e) => _late(e) ? Theme.of(context).colorScheme.errorContainer : null,
    columns: [
      col('OF', 'reference'),
      col('Op.', 'operationSequence'),
      col('Fornecedor', 'supplierName'),
      dateCol('Enviado', 'sentOn'),
      ColumnSpec('Retorno previsto', (e) => e['dueDate'] == null ? '' : '${fmtDay(e['dueDate'])}${_late(e) ? ' · atrasada' : ''}'),
      col('Enviado (qtd)', 'quantity', numeric: true),
      col('Retornado', 'returnedQuantity', numeric: true),
      col('Refugo', 'scrapQuantity', numeric: true),
      col('Em aberto', 'open', numeric: true),
      moneyCol('Serviço', 'serviceValue'),
      col('NF', 'invoiceNumber'),
    ],
    onTap: _tap,
  );
}

/// Outside-processing (industrialização) overview with late items.
class OutsideProcessingScreen extends StatelessWidget {
  const OutsideProcessingScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) => ShipmentsView(session: session);
}

Future<void> showScheduleResult(BuildContext context, List<Map<String, dynamic>> rows, {Session? session}) {
  final cs = Theme.of(context).colorScheme;
  final late = rows.where((r) => r['late'] == true).length;
  return showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('${rows.length} OF(s) programada(s)${late == 0 ? '' : ' · $late atrasada(s)'}'),
      content: SizedBox(
        width: 860,
        child: SingleChildScrollView(
          child: SimpleTable(
            columns: [
              col('OF', 'reference'),
              dateCol('Entrega', 'dueDate'),
              ColumnSpec('Início', (e) => fmtDay(e['adjustedStart'] ?? e['plannedStart'])),
              ColumnSpec('Fim', (e) => fmtDay(e['adjustedEnd'] ?? e['plannedEnd'])),
              ColumnSpec('Atrasada', (e) => e['late'] == true ? 'Sim' : ''),
              ColumnSpec('Avisos', (e) => (e['warnings'] as List).join('; ')),
            ],
            rows: rows,
            rowColor: (e) => e['late'] == true ? cs.errorContainer : null,
            // From a late OF in this list straight to its page, without hunting for it afterwards.
            actions: session == null
                ? null
                : (e) => [
                    IconButton(
                      key: ValueKey('schedule-open-${e['orderId']}'),
                      tooltip: 'Abrir ${e['reference']}',
                      icon: const Icon(Icons.open_in_new, size: 20),
                      onPressed: e['orderId'] is int
                          ? () {
                              Navigator.pop(c);
                              unawaited(openProductionOrder(context, session, e['orderId'] as int));
                            }
                          : null,
                    ),
                  ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fechar'))],
    ),
  );
}

/// PCP planning screen.
class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key, required this.session});

  final Session session;

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  String _groupBy = 'machine';
  int _weeks = 8;
  late Future<dynamic> _load = _fetch();

  Session get s => widget.session;

  Future<dynamic> _fetch() {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    return s.api.get('/api/production/load', {'from': isoDate(from), 'to': isoDate(from.add(Duration(days: _weeks * 7 - 1))), 'groupBy': _groupBy});
  }

  void _reload() => setState(() {
    _load = _fetch();
  });

  Future<void> _scheduleAll() async {
    if (!await confirm(context, 'Reprogramar todas as OFs abertas a partir de hoje?') || !mounted) return;
    final r = await runAction(context, () => s.api.post('/api/production/schedule', {}));
    if (r is! List || !mounted) return;
    await showScheduleResult(context, r.cast<Map<String, dynamic>>(), session: s);
    _reload();
  }

  Color? _color(num pct) {
    final cs = Theme.of(context).colorScheme;
    if (pct > 100) return cs.errorContainer;
    if (pct >= 85) return cs.tertiaryContainer;
    if (pct > 0) return cs.primaryContainer.withValues(alpha: 0.5);
    return null;
  }

  Widget _grid(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Sem carga programada no período'));
    final weeks = rows.map((r) => '${r['weekStart']}').toSet().toList()..sort();
    final codes = rows.map((r) => '${r['code']}').toSet().toList()..sort();
    final cell = {for (final r in rows) '${r['code']}|${r['weekStart']}': r};
    final now = DateTime.now();
    final thisWeek = isoDate(DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1)));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 48,
        columns: [
          DataColumn(label: Text(_groupBy == 'machine' ? 'Máquina' : 'Centro de trabalho')),
          // The week that holds today is marked so the grid reads from "now".
          for (final w in weeks)
            DataColumn(
              label: Text(
                'Sem. ${fmtDay(w).substring(0, 5)}${w == thisWeek ? ' (atual)' : ''}',
                style: w == thisWeek ? TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary) : null,
              ),
              numeric: true,
            ),
        ],
        rows: [
          for (final c in codes)
            DataRow(
              cells: [
                DataCell(Text(c)),
                for (final w in weeks)
                  DataCell(
                    Builder(
                      builder: (_) {
                        final r = cell['$c|$w'];
                        if (r == null) return const Text('');
                        return Tooltip(
                          message: '${fmtNum(r['hours'], 1)} h de ${fmtNum(r['capacity'], 1)} h · ${r['operations']} operação(ões)',
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            color: _color(r['loadPercent'] as num),
                            child: Text('${fmtNum(r['loadPercent'], 0)} %'),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'machine', label: Text('Máquina')),
              ButtonSegment(value: 'workCenter', label: Text('Centro de trabalho')),
            ],
            selected: {_groupBy},
            onSelectionChanged: (v) {
              _groupBy = v.first;
              _reload();
            },
          ),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('4 sem.')),
              ButtonSegment(value: 8, label: Text('8 sem.')),
              ButtonSegment(value: 12, label: Text('12 sem.')),
            ],
            selected: {_weeks},
            onSelectionChanged: (v) {
              _weeks = v.first;
              _reload();
            },
          ),
          IconButton(tooltip: 'Atualizar', onPressed: _reload, icon: const Icon(Icons.refresh)),
          if (s.canProduce)
            FilledButton.icon(
              key: const ValueKey('schedule-all'),
              onPressed: _scheduleAll,
              icon: const Icon(Icons.event_repeat),
              label: const Text('Reprogramar todas'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Section(
        title: 'Carga semanal (% da capacidade)',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A capacidade de cada semana é horas por dia (Parâmetros) × dias úteis; feriados cadastrados (Cadastros > Feriados) ficam de fora. Destaque forte a partir de 85 % da capacidade; vermelho acima de 100 %.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            FutureView<dynamic>(future: _load, onRetry: _reload, builder: (_, r) => _grid((r as List).cast<Map<String, dynamic>>())),
          ],
        ),
      ),
    ],
  );
}
