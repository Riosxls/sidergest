import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/pipeline.dart';
import '../widgets/record_list.dart';
import '../widgets/responsive.dart';

const receivableStatuses = {
  'pending': 'A receber (todas em aberto)',
  'Open': 'A vencer',
  'Partial': 'Pago em parte',
  'Overdue': 'Vencida',
  'Paid': 'Paga',
  'Cancelled': 'NF cancelada',
};

/// Query value of a status choice: the API takes lower-case names.
String? _statusQuery(String? v) => v?.toLowerCase();

/// Contas a receber: the duplicatas of the authorized sale NFs, with the aging summary on top and the baixa / estorno actions per row.
class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key, required this.session, this.customerId, this.initialFilter});

  final Session session;

  /// 'overdue' (from the Painel alert): only the late duplicatas.
  final String? initialFilter;

  /// Limits the list to one customer (opened from the customer page).
  final int? customerId;

  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  final _list = GlobalKey<RecordListState>();
  final _aging = GlobalKey<ReceivablesAgingCardState>();
  static const _defaultStatus = 'pending';
  late String? _status = widget.initialFilter == 'overdue' ? null : _defaultStatus;
  late bool _overdue = widget.initialFilter == 'overdue';

  ApiClient get api => widget.session.api;

  void _changed() {
    unawaited(_list.currentState?.reload());
    unawaited(_aging.currentState?.reload());
  }

  Future<void> _post(Map<String, dynamic> e) async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Dar baixa · NF ${e['number']} (${e['sequence']}/${e['count']})',
      fields: [
        FieldSpec('paidOn', 'Data do pagamento', type: FieldType.date, required: true, defaultValue: isoDate(DateTime.now())),
        FieldSpec(
          'amount',
          'Valor recebido (R\$)',
          type: FieldType.decimal,
          required: true,
          positive: true,
          defaultValue: e['balance'],
          hint: 'Saldo da duplicata: ${fmtMoney(e['balance'])}. Menos que o saldo = baixa parcial',
        ),
        const FieldSpec('method', 'Forma', hint: 'PIX, boleto, transferência...'),
        const FieldSpec('notes', 'Observação'),
      ],
      submit: (b) => api.post('/api/receivables/installments/${e['id']}/payments', b),
    );
    if (r != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Baixa registrada')));
      _changed();
    }
  }

  /// Opens the read-only payment list of a duplicata; Dar baixa / Estornar are explicit buttons there.
  Future<void> _reverse(Map<String, dynamic> e) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _PaymentsDialog(session: widget.session, row: e, onPost: () => _post(e)),
    );
    // Always reloaded: closing by a tap outside answers null, and the row's balance (and so its "Dar baixa" / "Estornar" actions) may have moved.
    if (mounted) _changed();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ReceivablesAgingCard(key: _aging, api: api, customerId: widget.customerId),
      Expanded(
        child: RecordList(
          key: _list,
          api: api,
          path: '/api/receivables',
          query: {'customerId': widget.customerId, 'status': _statusQuery(_status), 'overdue': _overdue ? true : null},
          searchHint: 'Cliente ou número da NF',
          filtersActive: _status != _defaultStatus || _overdue,
          onClearFilters: () => setState(() {
            _status = _defaultStatus;
            _overdue = false;
          }),
          filters: [
            ChoiceFilter(label: 'Situação', value: _status, choices: receivableStatuses, onChanged: (v) => setState(() => _status = v)),
            FilterChip(label: const Text('Só vencidas'), selected: _overdue, onSelected: (v) => setState(() => _overdue = v)),
          ],
          emptyText: 'Nenhuma duplicata. Elas nascem quando a NF de venda é autorizada.',
          columns: [
            col('NF', 'number', numeric: true),
            col('Cliente', 'customerName'),
            ColumnSpec('Parcela', (e) => '${e['sequence']}/${e['count']}'),
            dateCol('Vencimento', 'dueDate'),
            moneyCol('Valor', 'amount'),
            moneyCol('Pago', 'paid'),
            moneyCol('Saldo', 'balance'),
            ColumnSpec(
              'Situação',
              (e) => receivableStatuses[e['status']] ?? fmt(e['status']),
              cell: (_, e) => StatusBadge(
                e['status'] == 'Overdue' ? 'Vencida há ${e['daysOverdue']} d' : (receivableStatuses[e['status']] ?? fmt(e['status'])),
                tone: switch (e['status']) {
                  'Overdue' => Tone.danger,
                  'Paid' => Tone.success,
                  _ => Tone.neutral,
                },
              ),
            ),
          ],
          rowActions: (e) => [
            if (widget.session.canPostReceivables && (e['balance'] as num) > 0) RowAction('Dar baixa', Icons.payments_outlined, () => _post(e)),
            if (widget.session.canPostReceivables && (e['paid'] as num) > 0) RowAction('Estornar', Icons.undo, () => _reverse(e)),
          ],
          onTap: _reverse,
        ),
      ),
    ],
  );
}

/// Aging summary: what is still to fall due and what is late by 1-30, 31-60, 61-90 and 90+ days.
class ReceivablesAgingCard extends StatefulWidget {
  const ReceivablesAgingCard({super.key, required this.api, this.customerId});

  final ApiClient api;
  final int? customerId;

  @override
  State<ReceivablesAgingCard> createState() => ReceivablesAgingCardState();
}

class ReceivablesAgingCardState extends State<ReceivablesAgingCard> {
  Map<String, dynamic>? _total;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  Future<void> reload() async {
    try {
      final rows = await widget.api.get('/api/receivables/aging', {'customerId': widget.customerId});
      final total = (rows as List).cast<Map<String, dynamic>>().where((r) => r['customerId'] == null).firstOrNull;
      if (mounted) {
        setState(() {
          _total = total;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _total;
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }
    if (t == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    Widget cell(String label, String key, {bool alert = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(fmtMoney(t[key]), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: alert && (t[key] as num) > 0 ? cs.error : null)),
        ],
      ),
    );
    return Card(
      key: const ValueKey('receivables-aging'),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(
          children: [
            cell('A receber', 'total'),
            cell('A vencer', 'notDue'),
            cell('1 a 30 dias', 'days1To30', alert: true),
            cell('31 a 60 dias', 'days31To60', alert: true),
            cell('61 a 90 dias', 'days61To90', alert: true),
            cell('Mais de 90 dias', 'over90', alert: true),
          ],
        ),
      ),
    );
  }
}

/// Payments posted on one duplicata, each with its estorno button.
class _PaymentsDialog extends StatefulWidget {
  const _PaymentsDialog({required this.session, required this.row, required this.onPost});

  final Session session;
  final Map<String, dynamic> row;
  final Future<void> Function() onPost;

  @override
  State<_PaymentsDialog> createState() => _PaymentsDialogState();
}

class _PaymentsDialogState extends State<_PaymentsDialog> {
  List<Map<String, dynamic>>? _payments;
  String? _error;
  bool _changed = false;

  ApiClient get api => widget.session.api;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final r = await api.get('/api/receivables/installments/${widget.row['id']}/payments');
      if (mounted) setState(() => _payments = (r as List).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _reverse(Map<String, dynamic> p) async {
    final reason = await promptText(
      context,
      title: 'Estornar pagamento de ${fmtMoney(p['amount'])}',
      label: 'Motivo do estorno',
      required: true,
      confirmLabel: 'Estornar',
      danger: true,
    );
    if (reason == null || !mounted) return;
    final ok = await runAction(context, () async {
      await api.delete('/api/receivables/payments/${p['id']}?reason=${Uri.encodeQueryComponent(reason)}');
      return true;
    }, success: 'Pagamento estornado');
    if (ok == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _post() async {
    await widget.onPost();
    _changed = true;
    if (mounted) await _load();
  }

  /// Paid and balance of the duplicata from its live payments (the row the list passed in is a snapshot that an estorno makes stale).
  ({num paid, num balance})? get _figures {
    final p = _payments;
    final amount = widget.row['amount'];
    if (p == null || amount is! num) return null;
    final paid = p.where((x) => x['reversedAt'] == null).fold<num>(0, (a, x) => a + ((x['amount'] as num?) ?? 0));
    return (paid: paid, balance: ((amount - paid) * 100).round() / 100);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final canPost = widget.session.canPostReceivables;
    final f = _figures;
    final balance = f?.balance ?? r['balance'] as num;
    return AlertDialog(
      title: Text('Pagamentos · NF ${r['number']} (${r['sequence']}/${r['count']})'),
      content: DialogBody(
        ideal: 460,
        child: _error != null
            ? Text(_error!)
            : _payments == null
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : _payments!.isEmpty
            ? const Text('Nenhum pagamento nesta duplicata.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (f != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Valor ${fmtMoney(r['amount'])} · pago ${fmtMoney(f.paid)} · saldo ${fmtMoney(f.balance)}',
                          key: const ValueKey('payments-balance'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    for (final p in _payments!)
                      ListTile(
                        key: ValueKey('payment-${p['id']}'),
                        dense: true,
                        title: Text(fmtMoney(p['amount']), style: p['reversedAt'] != null ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                        subtitle: Text(
                          [
                            fmtDay(p['paidOn']),
                            if (p['method'] != null) p['method'],
                            if (p['createdBy'] != null) 'por ${p['createdBy']}',
                            if (p['reversedAt'] != null) 'estornado: ${p['reverseReason']}',
                          ].join(' · '),
                        ),
                        trailing: p['reversedAt'] == null && canPost ? TextButton(onPressed: () => _reverse(p), child: const Text('Estornar')) : null,
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, _changed), child: const Text('Fechar')),
        if (canPost && balance > 0) FilledButton.icon(onPressed: _post, icon: const Icon(Icons.payments_outlined), label: const Text('Dar baixa')),
      ],
    );
  }
}
