import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import '../widgets/entity_form.dart';
import 'product_detail.dart';
import 'where_used.dart';

class EntityListScreen extends StatefulWidget {
  const EntityListScreen({super.key, required this.session, required this.spec});

  final Session session;
  final EntitySpec spec;

  @override
  State<EntityListScreen> createState() => _EntityListScreenState();
}

class _EntityListScreenState extends State<EntityListScreen> {
  static const pageSize = 50;
  PageResult? _page;
  String? _error;
  bool _loading = false;
  String _q = '';
  int _skip = 0;
  Timer? _debounce;

  ApiClient get api => widget.session.api;
  EntitySpec get spec => widget.spec;
  bool get isProduct => spec.path == products.path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await api.list(spec.path, q: _q, skip: _skip, take: pageSize);
      if (mounted) {
        setState(() {
          _page = page;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _q = q;
      _skip = 0;
      _load();
    });
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final result = await showEntityForm(
      context,
      api: api,
      title: item == null ? 'Novo: ${spec.singular}' : '${spec.singular} ${item['code'] ?? ''}',
      fields: spec.fields,
      initial: item,
      readOnly: !widget.session.canWrite,
      onSubmit: (body) async => (item == null ? await api.post(spec.path, body) : await api.put('${spec.path}/${item['id']}', body)) as Map<String, dynamic>?,
      onDelete: item == null ? null : () => api.delete('${spec.path}/${item['id']}'),
    );
    if (result == null) return;
    await _load();
    if (isProduct && item == null && result['id'] != null && mounted) _open(result);
  }

  Future<void> _open(Map<String, dynamic> item) async {
    if (!isProduct) return _edit(item);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(session: widget.session, productId: item['id'] as int),
      ),
    );
    _load();
  }

  void _whereUsed(Map<String, dynamic> item) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => WhereUsedScreen(session: widget.session, path: '${spec.path}/${item['id']}/where-used', title: 'Onde é usado: ${item['code']}'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final page = _page;
    return Scaffold(
      floatingActionButton: widget.session.canWrite
          ? FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Novo'))
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                if (spec.searchable)
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar', isDense: true, border: OutlineInputBorder()),
                      onChanged: _onSearch,
                    ),
                  )
                else
                  const Spacer(),
                IconButton(tooltip: 'Atualizar', onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator() else const SizedBox(height: 4),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (page != null)
            Expanded(
              child: page.items.isEmpty
                  ? const Center(child: Text('Nenhum registro'))
                  : wide
                  ? _table(page.items)
                  : _list(page.items),
            ),
          if (page != null && page.total > 0) _pager(page),
        ],
      ),
    );
  }

  Widget _rowActions(Map<String, dynamic> e) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (spec.whereUsed) IconButton(tooltip: 'Onde é usado', icon: const Icon(Icons.account_tree_outlined, size: 20), onPressed: () => _whereUsed(e)),
      if (isProduct) IconButton(tooltip: 'Editar cadastro', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _edit(e)),
    ],
  );

  Widget _table(List<Map<String, dynamic>> items) => SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: 80),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        columns: [
          for (final c in spec.columns) DataColumn(label: Text(c.label), numeric: c.numeric),
          if (spec.whereUsed || isProduct) const DataColumn(label: Text('')),
        ],
        rows: [
          for (final e in items)
            DataRow(
              onSelectChanged: (_) => _open(e),
              cells: [
                for (final c in spec.columns)
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(c.value(e), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                if (spec.whereUsed || isProduct) DataCell(_rowActions(e)),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _list(List<Map<String, dynamic>> items) => ListView.separated(
    padding: const EdgeInsets.only(bottom: 80),
    itemCount: items.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (_, i) {
      final e = items[i];
      final cols = spec.columns;
      final subtitle = cols.skip(2).map((c) => (c.label, c.value(e))).where((p) => p.$2.isNotEmpty).map((p) => '${p.$1}: ${p.$2}').join(' · ');
      return ListTile(
        title: Text('${cols[0].value(e)}  ${cols.length > 1 ? cols[1].value(e) : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: _rowActions(e),
        onTap: () => _open(e),
      );
    },
  );

  Widget _pager(PageResult page) {
    final from = page.skip + 1;
    final to = page.skip + page.items.length;
    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Text('$from–$to de ${page.total}'),
            const Spacer(),
            IconButton(
              tooltip: 'Anterior',
              onPressed: _skip == 0
                  ? null
                  : () {
                      _skip = (_skip - pageSize).clamp(0, page.total);
                      _load();
                    },
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Próxima',
              onPressed: to >= page.total
                  ? null
                  : () {
                      _skip += pageSize;
                      _load();
                    },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
