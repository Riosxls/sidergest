import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';

/// One entry of a [RecordList] row menu; the list reloads after [run].
class RowAction {
  const RowAction(this.label, this.icon, this.run);

  final String label;
  final IconData icon;
  final Future<void> Function() run;
}

class RecordList extends StatefulWidget {
  const RecordList({
    super.key,
    required this.api,
    required this.path,
    required this.columns,
    this.query = const {},
    this.onTap,
    this.searchable = true,
    this.searchParam = 'q',
    this.searchHint = 'Buscar',
    this.filters = const [],
    this.fab,
    this.enrich,
    this.rowColor,
    this.rowActions,
    this.emptyText = 'Nenhum registro',
    this.pageSize = 50,
    this.filtersActive = false,
    this.onClearFilters,
    this.emptyAction,
  });

  final ApiClient api;
  final String path;
  final List<ColumnSpec> columns;
  final Map<String, dynamic> query;
  final Future<void> Function(Map<String, dynamic> e)? onTap;
  final bool searchable;
  final String searchParam;
  final String searchHint;
  final List<Widget> filters;
  final Widget? fab;
  final Future<void> Function(List<Map<String, dynamic>> items)? enrich;
  final Color? Function(BuildContext context, Map<String, dynamic> e)? rowColor;

  /// Per-row ⋮ menu (e.g. quick cancel); an empty list hides the menu for that row.
  final List<RowAction> Function(Map<String, dynamic> e)? rowActions;
  final String emptyText;
  final int pageSize;

  /// True while a screen filter narrows the list; the empty state then offers to clear it.
  final bool filtersActive;
  final VoidCallback? onClearFilters;

  /// Shown under the empty message when nothing is filtered (e.g. a "create the first" button).
  final Widget? emptyAction;

  @override
  State<RecordList> createState() => RecordListState();
}

class RecordListState extends State<RecordList> {
  PageResult? _page;
  String? _error;
  bool _loading = false;
  String _q = '';
  int _skip = 0;
  int _request = 0;
  Timer? _debounce;
  final _search = TextEditingController();
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  int? _sortColumn;
  bool _ascending = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(RecordList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || !mapEquals(oldWidget.query, widget.query)) {
      _skip = 0;
      reload();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _clearFilters() {
    _search.clear();
    _q = '';
    _skip = 0;
    widget.onClearFilters?.call();
    reload();
  }

  /// Orders the visible page by one column; numbers, dd/mm/yyyy dates and text each compare in their own way.
  List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> items) {
    final i = _sortColumn;
    if (i == null || i >= widget.columns.length) return items;
    final col = widget.columns[i];
    final out = [...items]..sort((a, b) => _compareCells(col.value(a), col.value(b)));
    return _ascending ? out : out.reversed.toList();
  }

  static int _compareCells(String a, String b) {
    num? number(String s) => num.tryParse(s.replaceAll(RegExp(r'[^0-9,\-]'), '').replaceAll(',', '.'));
    String date(String s) {
      final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})').firstMatch(s);
      return m == null ? '' : '${m[3]}${m[2]}${m[1]}';
    }

    final da = date(a), db = date(b);
    if (da.isNotEmpty && db.isNotEmpty) return da.compareTo(db);
    final na = number(a), nb = number(b);
    if (na != null && nb != null && RegExp(r'\d').hasMatch(a) && RegExp(r'\d').hasMatch(b) && !RegExp(r'[A-Za-z]{2}').hasMatch('$a$b')) return na.compareTo(nb);
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  Future<void> reload() async {
    final r = ++_request;
    setState(() => _loading = true);
    try {
      final raw = await widget.api.get(widget.path, {...widget.query, widget.searchParam: _q, 'skip': _skip, 'take': widget.pageSize});
      final page = raw is List ? PageResult(raw.cast<Map<String, dynamic>>(), raw.length, 0, raw.length) : PageResult.fromJson(raw as Map<String, dynamic>);
      if (widget.enrich != null) await widget.enrich!(page.items);
      if (mounted && r == _request) {
        setState(() {
          _page = page;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && r == _request) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && r == _request) setState(() => _loading = false);
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _q = q.trim();
      _skip = 0;
      reload();
    });
  }

  Future<void> _tap(Map<String, dynamic> e) async {
    if (widget.onTap == null) return;
    await widget.onTap!(e);
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final page = _page;
    return Scaffold(
      floatingActionButton: widget.fab,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (widget.searchable)
                        SizedBox(
                          width: wide ? 320 : width - 96,
                          child: TextField(
                            key: const ValueKey('record-search'),
                            controller: _search,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: widget.searchHint,
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: _onSearch,
                          ),
                        ),
                      ...widget.filters,
                    ],
                  ),
                ),
                IconButton(tooltip: 'Atualizar', onPressed: reload, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator() else const SizedBox(height: 4),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                    TextButton(onPressed: reload, child: const Text('Tentar novamente')),
                  ],
                ),
              ),
            ),
          if (page == null && _error == null) const Expanded(child: Center(child: CircularProgressIndicator())),
          if (page != null)
            Expanded(
              child: page.items.isEmpty
                  ? _empty()
                  : wide
                  ? _table(_sorted(page.items))
                  : _list(_sorted(page.items)),
            ),
          if (page != null && page.total > page.items.length) _pager(page),
        ],
      ),
    );
  }

  Widget _empty() {
    final cs = Theme.of(context).colorScheme;
    final narrowed = _q.isNotEmpty || widget.filtersActive;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(narrowed ? Icons.filter_alt_off_outlined : Icons.inbox_outlined, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(narrowed ? 'Nada encontrado com a busca e os filtros atuais' : widget.emptyText, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            if (narrowed)
              OutlinedButton.icon(
                key: const ValueKey('clear-filters'),
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear_all),
                label: const Text('Limpar filtros'),
              )
            else if (widget.emptyAction != null)
              widget.emptyAction!,
          ],
        ),
      ),
    );
  }

  Widget _table(List<Map<String, dynamic>> items) => Scrollbar(
    controller: _vertical,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: _vertical,
      padding: const EdgeInsets.only(bottom: 80),
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        notificationPredicate: (n) => n.depth == 0,
        child: SingleChildScrollView(controller: _horizontal, scrollDirection: Axis.horizontal, child: _dataTable(items)),
      ),
    ),
  );

  Widget _dataTable(List<Map<String, dynamic>> items) => DataTable(
    showCheckboxColumn: false,
    headingRowHeight: 40,
    dataRowMinHeight: 36,
    dataRowMaxHeight: 44,
    sortColumnIndex: _sortColumn,
    sortAscending: _ascending,
    columns: [
      for (var i = 0; i < widget.columns.length; i++)
        DataColumn(
          label: Text(widget.columns[i].label),
          numeric: widget.columns[i].numeric,
          onSort: (col, asc) => setState(() {
            _sortColumn = col;
            _ascending = asc;
          }),
        ),
      if (widget.rowActions != null) const DataColumn(label: SizedBox.shrink()),
    ],
    rows: [
      for (final e in items)
        DataRow(
          color: WidgetStateProperty.resolveWith((_) => widget.rowColor?.call(context, e)),
          onSelectChanged: widget.onTap == null ? null : (_) => _tap(e),
          cells: [
            for (final c in widget.columns)
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(c.value(e), overflow: TextOverflow.ellipsis),
                ),
              ),
            if (widget.rowActions != null) DataCell(_menu(e)),
          ],
        ),
    ],
  );

  Widget _menu(Map<String, dynamic> e) {
    final actions = widget.rowActions?.call(e) ?? const <RowAction>[];
    if (actions.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<RowAction>(
      tooltip: 'Ações',
      onSelected: (a) async {
        await a.run();
        if (mounted) reload();
      },
      itemBuilder: (_) => [
        for (final a in actions)
          PopupMenuItem(
            value: a,
            child: ListTile(leading: Icon(a.icon), title: Text(a.label)),
          ),
      ],
    );
  }

  Widget _list(List<Map<String, dynamic>> items) => ListView.separated(
    padding: const EdgeInsets.only(bottom: 80),
    itemCount: items.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (_, i) {
      final e = items[i];
      final cols = widget.columns;
      final pairs = cols.skip(2).map((c) => (c.label, c.value(e))).where((p) => p.$2.isNotEmpty).toList();
      final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
      return ListTile(
        tileColor: widget.rowColor?.call(context, e),
        title: Text(
          '${cols[0].value(e)}  ${cols.length > 1 ? cols[1].value(e) : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: pairs.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    for (final p in pairs.take(6))
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${p.$1} ', style: muted),
                            TextSpan(text: p.$2),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
        trailing: widget.rowActions == null ? null : _menu(e),
        onTap: widget.onTap == null ? null : () => _tap(e),
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
                      _skip = (_skip - widget.pageSize).clamp(0, page.total);
                      reload();
                    },
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Próxima',
              onPressed: to >= page.total
                  ? null
                  : () {
                      _skip += widget.pageSize;
                      reload();
                    },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

class ChoiceFilter extends StatelessWidget {
  const ChoiceFilter({super.key, required this.label, required this.value, required this.choices, required this.onChanged, this.allLabel = 'Todos'});

  final String label;
  final String? value;
  final Map<String, String> choices;
  final ValueChanged<String?> onChanged;
  final String allLabel;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: DropdownButtonFormField<String?>(
      key: ValueKey('filter-$label'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(allLabel)),
        for (final e in choices.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
      ],
      onChanged: onChanged,
    ),
  );
}

class NameCache {
  static final _cache = <String, Future<String>>{};

  static void clear() => _cache.clear();

  static Future<String> name(ApiClient api, String path, int id, [String Function(Map<String, dynamic>)? label]) => _cache.putIfAbsent('$path/$id', () async {
    try {
      final e = await api.get('$path/$id') as Map<String, dynamic>;
      return (label ?? LookupSpec.display)(e);
    } catch (_) {
      return '#$id';
    }
  });

  static Future<void> attach(
    ApiClient api,
    List<Map<String, dynamic>> items,
    String idKey,
    String path,
    String target, [
    String Function(Map<String, dynamic>)? label,
  ]) async {
    await Future.wait(
      items.where((e) => e[idKey] is int).map((e) async {
        e[target] = await name(api, path, e[idKey] as int, label);
      }),
    );
  }

  static Future<void> attachItem(ApiClient api, List<Map<String, dynamic>> items, {String target = 'itemCode'}) async {
    await attach(api, items, 'materialId', '/api/materials', target, (e) => '${e['code']}');
    await attach(api, items, 'productId', '/api/products', target, (e) => '${e['code']}');
  }

  static Future<void> attachSupplier(ApiClient api, List<Map<String, dynamic>> items) =>
      attach(api, items, 'supplierId', '/api/suppliers', 'supplierName', (e) => '${e['name']}');
}

class InfoGrid extends StatelessWidget {
  const InfoGrid(this.entries, {super.key});

  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 24,
      runSpacing: 8,
      children: [
        for (final (k, v) in entries.where((e) => e.$2.isNotEmpty))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(k, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(v, style: theme.textTheme.bodyLarge),
            ],
          ),
      ],
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.alert = false, this.ok = false});

  final String label;
  final bool alert;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Chip(visualDensity: VisualDensity.compact, label: Text(label), backgroundColor: alert ? cs.errorContainer : (ok ? cs.primaryContainer : null));
  }
}

class SimpleTable extends StatelessWidget {
  const SimpleTable({super.key, required this.columns, required this.rows, this.actions, this.rowColor, this.actionsFirst = false});

  final List<ColumnSpec> columns;
  final List<Map<String, dynamic>> rows;
  final List<Widget> Function(Map<String, dynamic> e)? actions;
  final bool actionsFirst;
  final Color? Function(Map<String, dynamic> e)? rowColor;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Nenhum registro'));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (!wide) {
      return Column(
        children: [
          for (final e in rows)
            ListTile(
              tileColor: rowColor?.call(e),
              title: Text('${columns[0].value(e)}  ${columns.length > 1 ? columns[1].value(e) : ''}'),
              subtitle: Text(columns.skip(2).map((c) => (c.label, c.value(e))).where((p) => p.$2.isNotEmpty).map((p) => '${p.$1}: ${p.$2}').join(' · ')),
              trailing: actions == null ? null : Row(mainAxisSize: MainAxisSize.min, children: actions!(e)),
            ),
        ],
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        columns: [
          if (actions != null && actionsFirst) const DataColumn(label: Text('')),
          for (final c in columns) DataColumn(label: Text(c.label), numeric: c.numeric),
          if (actions != null && !actionsFirst) const DataColumn(label: Text('')),
        ],
        rows: [
          for (final e in rows)
            DataRow(
              color: WidgetStateProperty.resolveWith((_) => rowColor?.call(e)),
              cells: [
                if (actions != null && actionsFirst) DataCell(Row(mainAxisSize: MainAxisSize.min, children: actions!(e))),
                for (final c in columns) DataCell(Text(c.value(e))),
                if (actions != null && !actionsFirst) DataCell(Row(mainAxisSize: MainAxisSize.min, children: actions!(e))),
              ],
            ),
        ],
      ),
    );
  }
}

class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.child, this.actions = const []});

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              ...actions,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class FutureView<T> extends StatelessWidget {
  const FutureView({super.key, required this.future, required this.builder, this.onRetry});

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snap) {
      if (snap.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(friendlyError(snap.error!)),
              if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
            ],
          ),
        );
      }
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      return builder(context, snap.data as T);
    },
  );
}
