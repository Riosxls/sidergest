import 'package:flutter/material.dart';

import '../../api.dart';
import '../../session.dart';
import 'settings_widgets.dart';

/// Portuguese names of the records the server can flag, in the order they are listed.
const dataSourceEntities = <String, String>{
  'Customer': 'Clientes',
  'Supplier': 'Fornecedores',
  'Product': 'Produtos',
  'Material': 'Materiais',
  'Quote': 'Orçamentos',
  'SalesOrder': 'Pedidos de venda',
  'Delivery': 'Entregas',
  'ProductionOrder': 'Ordens de fabricação',
  'PurchaseRequisition': 'Requisições de compra',
  'PurchaseOrder': 'Pedidos de compra',
  'StockDocument': 'Movimentações de estoque',
};

/// Where the records come from: typed in the system (Manual), brought from the old system (Importado) or only for trying things out (Teste).
/// Teste records stay out of the Painel and the reports.
enum DataSourceKind {
  manual('Manual', 'Manual'),
  imported('Imported', 'Importado'),
  test('Test', 'Teste');

  const DataSourceKind(this.api, this.label);

  final String api;
  final String label;
}

class DataSourceView extends StatefulWidget {
  const DataSourceView({super.key, required this.session});

  final Session session;

  @override
  State<DataSourceView> createState() => _DataSourceViewState();
}

class _DataSourceViewState extends State<DataSourceView> {
  int _version = 0;
  bool _busy = false;

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await widget.session.api.get('/api/admin/data-source') as List;
    final rows = [for (final r in raw) r as Map<String, dynamic>];
    final order = dataSourceEntities.keys.toList();
    rows.sort((a, b) => order.indexOf(a['entity'] as String).compareTo(order.indexOf(b['entity'] as String)));
    return rows;
  }

  Future<void> _move(Map<String, dynamic> row, DataSourceKind from, DataSourceKind to) async {
    final entity = row['entity'] as String;
    final name = dataSourceEntities[entity] ?? entity;
    setState(() => _busy = true);
    try {
      final body = {'entity': entity, 'allManual': true, 'from': from.api, 'target': to.api};
      final preview = await widget.session.api.post('/api/admin/data-source', {...body, 'apply': false}) as Map<String, dynamic>;
      final count = (preview['rows'] as num).toInt();
      if (!mounted) return;
      if (count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nada a mudar em $name')));
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Marcar $count de $name como ${to.label}?'),
          content: Text(
            to == DataSourceKind.test
                ? 'Registros de teste deixam de aparecer no Painel e nos relatórios. Você pode devolvê-los a "${from.label}" aqui mesmo.'
                : 'Os $count registros que estão como "${from.label}" passam a "${to.label}". A mudança fica no registro de auditoria.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(key: const ValueKey('data-source-confirm'), onPressed: () => Navigator.pop(c, true), child: const Text('Marcar')),
          ],
        ),
      );
      if (ok != true) return;
      await widget.session.api.post('/api/admin/data-source', {...body, 'apply': true});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count de $name marcados como ${to.label}')));
      setState(() => _version++);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LoadView<List<Map<String, dynamic>>>(
      key: ValueKey(_version),
      load: _load,
      builder: (context, rows, reload) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Manual: digitado neste sistema. Importado: veio do sistema antigo. Teste: só para experimentar; fica fora do Painel e dos relatórios (a não ser que o relatório peça para incluir).',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const ValueKey('data-source-table'),
              columnSpacing: 20,
              horizontalMargin: 8,
              columns: const [
                DataColumn(label: Text('Registro')),
                DataColumn(label: Text('Manual'), numeric: true),
                DataColumn(label: Text('Importado'), numeric: true),
                DataColumn(label: Text('Teste'), numeric: true),
                DataColumn(label: Text('Marcar')),
              ],
              rows: [
                for (final r in rows)
                  DataRow(
                    cells: [
                      DataCell(Text(dataSourceEntities[r['entity']] ?? '${r['entity']}')),
                      DataCell(Text('${r['manual']}')),
                      DataCell(Text('${r['imported']}')),
                      DataCell(Text('${r['test']}')),
                      DataCell(
                        PopupMenuButton<(DataSourceKind, DataSourceKind)>(
                          key: ValueKey('data-source-menu-${r['entity']}'),
                          enabled: !_busy,
                          tooltip: 'Marcar registros',
                          icon: const Icon(Icons.more_horiz),
                          onSelected: (m) => _move(r, m.$1, m.$2),
                          itemBuilder: (_) => [
                            for (final (from, to) in const [
                              (DataSourceKind.manual, DataSourceKind.test),
                              (DataSourceKind.test, DataSourceKind.manual),
                              (DataSourceKind.manual, DataSourceKind.imported),
                              (DataSourceKind.imported, DataSourceKind.manual),
                            ])
                              PopupMenuItem(value: (from, to), child: Text('${from.label} para ${to.label}')),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: reload, icon: const Icon(Icons.refresh), label: const Text('Atualizar contagem')),
        ],
      ),
    );
  }
}
