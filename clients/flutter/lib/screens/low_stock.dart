import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/record_list.dart';

/// Materials below their minimum stock, with the quantity that would bring them back to the maximum (or the minimum when none is set).
class LowStockScreen extends StatefulWidget {
  const LowStockScreen({super.key, required this.session});

  final Session session;

  @override
  State<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockScreenState extends State<LowStockScreen> {
  final _list = GlobalKey<RecordListState>();

  ApiClient get api => widget.session.api;

  Future<void> _draft(List<int> ids) async {
    final r = await runAction(context, () => api.post('/api/stock/low-stock/requisitions', {'materialIds': ids}));
    if (r is! Map || !mounted) return;
    final made = (r['requisitionIds'] as List).length;
    final skipped = (r['skipped'] as List).cast<String>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          [
            made == 0 ? 'Nenhuma requisição criada' : '$made requisição(ões) criada(s), aguardando aprovação',
            if (skipped.isNotEmpty) skipped.join('\n'),
          ].join('\n'),
        ),
      ),
    );
    _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final canRequest = widget.session.permissions.contains('purchasing-request');
    return RecordList(
      key: _list,
      api: api,
      path: '/api/stock/low-stock',
      searchable: false,
      emptyText: 'Nenhum material abaixo do estoque mínimo',
      columns: [
        col('Código', 'code'),
        col('Material', 'description'),
        ColumnSpec('Saldo', (e) => '${fmt(e['onHand'])} ${e['stockUnit']}', numeric: true),
        ColumnSpec('Mínimo', (e) => '${fmt(e['minStock'])} ${e['stockUnit']}', numeric: true),
        ColumnSpec('Máximo', (e) => e['maxStock'] == null ? '—' : '${fmt(e['maxStock'])} ${e['stockUnit']}', numeric: true),
        ColumnSpec('A caminho', (e) => '${fmt(e['incoming'])} ${e['stockUnit']}', numeric: true),
        ColumnSpec('Sugestão de compra', (e) => '${fmt(e['suggestedPurchase'])} ${e['purchaseUnit']}', numeric: true),
        ColumnSpec('Requisição', (e) => e['hasOpenRequisition'] == true ? 'Em aberto' : (e['purchasable'] == true ? '—' : 'Não comprado')),
      ],
      rowColor: (ctx, e) => (e['onHand'] as num) <= 0 ? Theme.of(ctx).colorScheme.errorContainer : null,
      rowActions: (e) => [
        if (canRequest && e['purchasable'] == true && e['hasOpenRequisition'] != true)
          RowAction('Gerar requisição', Icons.assignment_add, () => _draft([e['materialId'] as int])),
      ],
      fab: canRequest
          ? FloatingActionButton.extended(
              key: const ValueKey('low-stock-draft-all'),
              onPressed: () async {
                final items = (_list.currentState?.items ?? const <Map<String, dynamic>>[])
                    .where((e) => e['purchasable'] == true && e['hasOpenRequisition'] != true)
                    .map((e) => e['materialId'] as int)
                    .toList();
                if (items.isNotEmpty) await _draft(items);
              },
              icon: const Icon(Icons.assignment_add),
              label: const Text('Gerar requisições'),
            )
          : null,
    );
  }
}
