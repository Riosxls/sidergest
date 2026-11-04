import 'dart:convert';

import 'package:flutter/material.dart';

import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/record_list.dart';
import '../widgets/responsive.dart';

/// Portuguese names for audited entities, used where [auditEntityLabels] has none; the shared map wins when it has one.
const _fallbackEntityLabels = {
  'Customer': 'Cliente',
  'CustomerAddress': 'Endereço de cliente',
  'Supplier': 'Fornecedor',
  'SupplierAddress': 'Endereço de fornecedor',
  'Material': 'Matéria-prima',
  'Product': 'Produto',
  'AppUser': 'Usuário',
  'StockLocation': 'Local de estoque',
  'StockSettings': 'Parâmetros de Estoque',
  'StockClosing': 'Fechamento de estoque',
  'FiscalSettings': 'Parâmetros fiscais',
  'Cfop': 'CFOP',
  'TaxRule': 'Regra de imposto',
  'MonthlyPrice': 'Preço mensal',
  'PaymentTerm': 'Prazo de pagamento',
  'PriceListEntry': 'Tabela de preços',
  'SalesSettings': 'Parâmetros de Vendas',
  'ProductionSettings': 'Parâmetros de Produção',
  'PurchasingSettings': 'Parâmetros de Suprimentos',
  'BackupSettings': 'Cópia de segurança',
  'SteelLot': 'Bobina de aço',
  'SlitterJob': 'Corte no slitter',
  'ProductionOrder': 'Ordem de fabricação',
  'QualityCertificate': 'Certificado',
};

String auditEntityName(Object? entity) => auditEntityLabels['$entity'] ?? _fallbackEntityLabels['$entity'] ?? '$entity';

/// "customerName" or "CustomerName" becomes "Customer name": a field name a person can read.
String humanizeField(String key) {
  final words = key.replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ').replaceAll('_', ' ').trim();
  if (words.isEmpty) return key;
  return words[0].toUpperCase() + words.substring(1).toLowerCase();
}

/// Audit trail list: who changed what and when.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.session});

  final Session session;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  String? _entity;
  String? _action;
  List<String> _actions = auditActions.keys.toList();
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _loadActions();
  }

  /// The actions the log really holds; the static list stays when the call fails or answers nothing usable.
  Future<void> _loadActions() async {
    try {
      final r = await widget.session.api.get('/api/audit/actions');
      final list = r is List ? [for (final a in r) '$a'] : const <String>[];
      if (list.isNotEmpty && mounted) setState(() => _actions = list);
    } catch (e) {
      debugPrint('audit: actions list failed, using the static list: $e');
    }
  }

  Future<void> _pick(bool start) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: (start ? _from : _to) ?? now, firstDate: DateTime(2000), lastDate: DateTime(now.year + 1));
    if (d == null) return;
    setState(() => start ? _from = d : _to = d);
  }

  Widget _dateButton(String label, DateTime? value, bool start) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      OutlinedButton.icon(
        key: ValueKey('audit-${start ? 'from' : 'to'}'),
        onPressed: () => _pick(start),
        icon: const Icon(Icons.event, size: 18),
        label: Text(value == null ? label : '$label ${fmtDay(isoDate(value))}'),
      ),
      if (value != null) IconButton(tooltip: 'Limpar $label', icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => start ? _from = null : _to = null)),
    ],
  );

  @override
  Widget build(BuildContext context) => RecordList(
    api: widget.session.api,
    path: '/api/audit',
    query: {
      'entity': _entity,
      'action': _action,
      'from': _from == null ? null : DateTime(_from!.year, _from!.month, _from!.day).toUtc().toIso8601String(),
      'to': _to == null ? null : DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59).toUtc().toIso8601String(),
    },
    searchParam: 'user',
    searchHint: 'Usuário',
    emptyText: 'Nenhum registro de auditoria ainda. Alterações em cadastros, parâmetros e usuários aparecem aqui.',
    filtersActive: _entity != null || _action != null || _from != null || _to != null,
    onClearFilters: () => setState(() {
      _entity = null;
      _action = null;
      _from = null;
      _to = null;
    }),
    filters: [
      ChoiceFilter(label: 'Entidade', value: _entity, choices: {for (final e in auditEntities) e: auditEntityName(e)}, onChanged: (v) => setState(() => _entity = v)),
      ChoiceFilter(label: 'Ação', value: _action, choices: {for (final a in _actions) a: auditActions[a] ?? humanizeField(a)}, onChanged: (v) => setState(() => _action = v)),
      _dateButton('Desde', _from, true),
      _dateButton('Até', _to, false),
    ],
    columns: [
      ColumnSpec('Data/hora', (e) => fmtDate(e['at'])),
      col('Usuário', 'user'),
      ColumnSpec('Entidade', (e) => auditEntityName(e['entity'])),
      col('Id', 'entityId'),
      ColumnSpec('Ação', (e) => auditActions[e['action']] ?? humanizeField('${e['action']}')),
    ],
    onTap: (e) => showDialog<void>(context: context, builder: (_) => AuditDetailDialog(entry: e)),
  );
}

String _show(Object? v) => v == null ? '—' : (v is String ? v : (v is num || v is bool ? '$v' : jsonEncode(v)));

/// Shows the details of one audit entry.
class AuditDetailDialog extends StatelessWidget {
  const AuditDetailDialog({super.key, required this.entry});

  final Map<String, dynamic> entry;

  Map<String, dynamic> get _changes {
    try {
      final c = entry['changes'];
      final d = c is String ? jsonDecode(c) : c;
      return d is Map<String, dynamic> ? d : {};
    } catch (e) {
      debugPrint('audit: lookup failed, using fallback: $e');
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final update = entry['action'] == 'Update';
    final changes = _changes;
    Widget cell(String t, {bool head = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      child: SelectableText(t, style: head ? theme.textTheme.labelMedium : null),
    );
    final width = dialogWidth(context, 560);
    return AlertDialog(
      title: Text('${auditActions[entry['action']] ?? entry['action']} · ${auditEntityName(entry['entity'])} #${entry['entityId']}'),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${fmtDate(entry['at'])} · ${entry['user']}', style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.md),
              if (changes.isEmpty)
                const Text('Sem detalhes de alteração')
              else
                // Long values widen the table past the dialog; it scrolls sideways instead of squeezing the columns.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: width),
                    child: Table(
                      defaultColumnWidth: const IntrinsicColumnWidth(),
                      border: TableBorder(horizontalInside: BorderSide(color: theme.dividerColor)),
                      children: [
                        TableRow(children: [cell('Campo', head: true), if (update) ...[cell('De', head: true), cell('Para', head: true)] else cell('Valor', head: true)]),
                        for (final e in changes.entries)
                          TableRow(
                            children: [
                              cell(humanizeField(e.key)),
                              if (update && e.value is Map<String, dynamic>) ...[
                                cell(_show((e.value as Map<String, dynamic>)['from'])),
                                cell(_show((e.value as Map<String, dynamic>)['to'])),
                              ] else if (update) ...[
                                cell('—'),
                                cell(_show(e.value)),
                              ] else
                                cell(_show(e.value)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
