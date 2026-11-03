import 'dart:async';
import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/pipeline.dart' show confirmStep;
import '../widgets/record_list.dart';
import 'requisitions.dart' show openRequisition;

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
    final created = (r['requisitionIds'] as List).cast<int>();
    final skipped = (r['skipped'] as List).cast<String>();
    unawaited(_list.currentState?.reload());
    final session = widget.session;
    if (created.isNotEmpty) {
      // The new requisitions wait for approval; the snackbar leads to the first one.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${created.length} requisição(ões) criada(s), aguardando aprovação'),
          duration: const Duration(seconds: 10),
          persist: false,
          action: SnackBarAction(label: created.length == 1 ? 'Abrir requisição' : 'Abrir a primeira', onPressed: () => unawaited(openRequisition(context, session, created.first))),
        ),
      );
    }
    if (skipped.isNotEmpty || created.isEmpty) {
      // What was left out stays on screen until read, unlike a snackbar.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(created.isEmpty ? 'Nenhuma requisição criada' : 'Alguns materiais ficaram de fora'),
          content: SingleChildScrollView(child: Text(skipped.isEmpty ? 'Nenhum dos materiais escolhidos precisava de requisição.' : skipped.join('\n'))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
        ),
      );
    }
  }

  /// One requisition per purchasable material on the list that has none open; says how many and asks first.
  Future<void> _draftAll() async {
    final rows = _list.currentState?.items ?? const <Map<String, dynamic>>[];
    final ids = [
      for (final e in rows)
        if (e['purchasable'] == true && e['hasOpenRequisition'] != true) e['materialId'] as int,
    ];
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nada a requisitar: os materiais da lista já têm requisição em aberto ou não são comprados')));
      return;
    }
    final left = rows.length - ids.length;
    final ok = await confirmStep(
      context,
      title: 'Gerar ${ids.length} ${ids.length == 1 ? 'requisição' : 'requisições'}?',
      message:
          'Uma requisição por material, com a quantidade sugerida, aguardando aprovação.${left > 0 ? ' $left ${left == 1 ? 'material fica' : 'materiais ficam'} de fora: já ${left == 1 ? 'tem' : 'têm'} requisição em aberto ou não ${left == 1 ? 'é comprado' : 'são comprados'}.' : ''}',
      confirmLabel: 'Gerar',
      icon: Icons.assignment_add,
    );
    if (ok && mounted) await _draft(ids);
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
              onPressed: _draftAll,
              icon: const Icon(Icons.assignment_add),
              label: const Text('Gerar requisições'),
            )
          : null,
    );
  }
}
