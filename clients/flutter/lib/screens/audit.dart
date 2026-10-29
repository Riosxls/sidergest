import 'dart:convert';

import 'package:flutter/material.dart';

import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/record_list.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.session});

  final Session session;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  String? _entity;

  @override
  Widget build(BuildContext context) => RecordList(
    api: widget.session.api,
    path: '/api/audit',
    query: {'entity': _entity},
    searchParam: 'user',
    searchHint: 'Usuário',
    emptyText: 'Nenhum registro de auditoria',
    filters: [
      ChoiceFilter(label: 'Entidade', value: _entity, choices: {for (final e in auditEntities) e: e}, onChanged: (v) => setState(() => _entity = v)),
    ],
    columns: [
      ColumnSpec('Data/hora', (e) => fmtDate(e['at'])),
      col('Usuário', 'user'),
      col('Entidade', 'entity'),
      col('Id', 'entityId'),
      labelCol('Ação', 'action', auditActions),
    ],
    onTap: (e) => showDialog<void>(context: context, builder: (_) => AuditDetailDialog(entry: e)),
  );
}

String _show(Object? v) => v == null ? '—' : (v is String ? v : (v is num || v is bool ? '$v' : jsonEncode(v)));

class AuditDetailDialog extends StatelessWidget {
  const AuditDetailDialog({super.key, required this.entry});

  final Map<String, dynamic> entry;

  Map<String, dynamic> get _changes {
    try {
      final c = entry['changes'];
      final d = c is String ? jsonDecode(c) : c;
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final update = entry['action'] == 'Update';
    final changes = _changes;
    Widget cell(String t, {bool head = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SelectableText(t, style: head ? theme.textTheme.labelMedium : null),
    );
    return AlertDialog(
      title: Text('${auditActions[entry['action']] ?? entry['action']} · ${entry['entity']} #${entry['entityId']}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${fmtDate(entry['at'])} · ${entry['user']}', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              if (changes.isEmpty)
                const Text('Sem detalhes de alteração')
              else
                Table(
                  columnWidths: const {0: IntrinsicColumnWidth()},
                  border: TableBorder(horizontalInside: BorderSide(color: theme.dividerColor)),
                  children: [
                    TableRow(children: [cell('Campo', head: true), if (update) ...[cell('De', head: true), cell('Para', head: true)] else cell('Valor', head: true)]),
                    for (final e in changes.entries)
                      TableRow(
                        children: [
                          cell(e.key),
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
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
