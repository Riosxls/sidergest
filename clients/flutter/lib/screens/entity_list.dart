import 'dart:async';

import 'package:flutter/material.dart';

import '../entities.dart';
import '../session.dart';
import '../widgets/entity_form.dart';
import '../widgets/record_list.dart';
import '../widgets/record_nav.dart';
import 'product_detail.dart';
import 'stock_balances.dart';
import 'where_used.dart';

/// Generic list/detail screen driven by an [EntitySpec] for simple master data. Built on [RecordList], so it sorts, remembers its view,
/// reloads when shown again or when a page closes, and offers a retry after an error.
class EntityListScreen extends StatefulWidget {
  const EntityListScreen({super.key, required this.session, required this.spec});

  final Session session;
  final EntitySpec spec;

  @override
  State<EntityListScreen> createState() => _EntityListScreenState();
}

class _EntityListScreenState extends State<EntityListScreen> {
  final _list = GlobalKey<RecordListState>();

  EntitySpec get spec => widget.spec;
  bool get isProduct => spec.path == products.path;
  bool get isMaterial => spec.path == materials.path;
  bool get canWrite => widget.session.permissions.contains(spec.writePolicy);

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final api = widget.session.api;
    final result = await showEntityForm(
      context,
      api: api,
      title: item == null ? 'Novo: ${spec.singular}' : '${spec.singular} ${item['code'] ?? ''}',
      fields: spec.fields,
      initial: item,
      readOnly: !canWrite,
      onSubmit: (body) async => (item == null ? await api.post(spec.path, body) : await api.put('${spec.path}/${item['id']}', body)) as Map<String, dynamic>?,
      onDelete: item == null ? null : () => api.delete('${spec.path}/${item['id']}'),
      deleteMessage: 'O cadastro é apagado. Se já estiver em uso em outro cadastro, o sistema recusa a exclusão.',
    );
    if (result == null) return;
    unawaited(_list.currentState?.reload());
    // Other lists show what this one just changed (a subgroup's name in the Materiais tab): the ones kept alive behind reload when they show again.
    RecordTrail.closed.value++;
    if (isProduct && item == null && result['id'] != null && mounted) unawaited(_open(result));
  }

  Future<void> _open(Map<String, dynamic> item) async {
    if (!isProduct) return _edit(item);
    await openProduct(context, widget.session, item['id'] as int);
  }

  Future<void> _whereUsed(Map<String, dynamic> item) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => WhereUsedScreen(session: widget.session, path: '${spec.path}/${item['id']}/where-used', title: 'Onde é usado: ${item['code']}'),
    ),
  );

  List<RowAction> _rowActions(Map<String, dynamic> e) => [
    if (isMaterial)
      RowAction('Saldo e movimentos', Icons.inventory_outlined, () => openItemStock(context, widget.session, materialId: e['id'] as int, title: '${e['code']} · ${e['description'] ?? ''}')),
    if (isProduct)
      RowAction('Saldo em estoque', Icons.inventory_outlined, () => openItemStock(context, widget.session, productId: e['id'] as int, title: '${e['code']} · ${e['name'] ?? ''}')),
    if (spec.whereUsed) RowAction('Onde é usado', Icons.account_tree_outlined, () => _whereUsed(e)),
    if (isProduct) RowAction('Editar cadastro', Icons.edit_outlined, () => _edit(e)),
  ];

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: widget.session.api,
    path: spec.path,
    columns: spec.columns,
    searchable: spec.searchable,
    onTap: _open,
    rowChevron: true,
    rowActions: spec.whereUsed || isProduct ? _rowActions : null,
    // One "Novo" button, the floating one; the empty state points to it instead of repeating it.
    emptyText: canWrite ? 'Nenhum registro. Use "Novo: ${spec.singular}" para cadastrar o primeiro.' : 'Nenhum registro',
    fab: canWrite
        ? FloatingActionButton.extended(heroTag: 'new-${spec.path}', onPressed: _edit, icon: const Icon(Icons.add), label: Text('Novo: ${spec.singular}'))
        : null,
  );
}
