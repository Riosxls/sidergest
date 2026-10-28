import 'package:flutter/material.dart';

import '../entities.dart';
import '../reports/report_doc.dart';
import '../session.dart';
import '../widgets/record_list.dart';

DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month);
DateTime _lastOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

/// Period selector: previous/next month arrows plus free start/end dates.
class PeriodPicker extends StatelessWidget {
  const PeriodPicker({super.key, required this.from, required this.to, required this.onChanged});

  final DateTime from;
  final DateTime to;
  final void Function(DateTime from, DateTime to) onChanged;

  Future<void> _pick(BuildContext c, bool start) async {
    final d = await showDatePicker(context: c, initialDate: start ? from : to, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null) return;
    start ? onChanged(d, d.isAfter(to) ? d : to) : onChanged(d.isBefore(from) ? d : from, d);
  }

  void _shift(int months) {
    final f = DateTime(from.year, from.month + months);
    onChanged(f, _lastOfMonth(f));
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      IconButton(tooltip: 'Mês anterior', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
      OutlinedButton.icon(onPressed: () => _pick(context, true), icon: const Icon(Icons.event, size: 18), label: Text(fmtDay(isoDate(from)))),
      const Text('até'),
      OutlinedButton.icon(onPressed: () => _pick(context, false), icon: const Icon(Icons.event, size: 18), label: Text(fmtDay(isoDate(to)))),
      IconButton(tooltip: 'Próximo mês', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
    ],
  );
}

/// Sortable, scrollable view of a [ReportDoc].
class ReportTable extends StatelessWidget {
  const ReportTable({super.key, required this.doc, required this.sortCol, required this.ascending, required this.onSort});

  final ReportDoc doc;
  final int? sortCol;
  final bool ascending;
  final ValueChanged<int> onSort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flex = doc.flex ?? List.filled(doc.headers.length, 1);
    Widget cell(String t, int i, {TextStyle? style}) => Expanded(
      flex: flex[i],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Text(t, style: style, textAlign: doc.numeric[i] ? TextAlign.right : TextAlign.left, overflow: TextOverflow.ellipsis, maxLines: 2),
      ),
    );
    final minWidth = flex.fold<int>(0, (a, b) => a + b) * 70.0;
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: c.maxWidth < minWidth ? minWidth : c.maxWidth,
          height: c.maxHeight,
          child: Column(
            children: [
              Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    for (var i = 0; i < doc.headers.length; i++)
                      Expanded(
                        flex: flex[i],
                        child: InkWell(
                          onTap: () => onSort(i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                            child: Row(
                              mainAxisAlignment: doc.numeric[i] ? MainAxisAlignment.end : MainAxisAlignment.start,
                              children: [
                                Flexible(child: Text(doc.headers[i], style: theme.textTheme.labelLarge, overflow: TextOverflow.ellipsis)),
                                if (sortCol == i) Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 14),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: doc.rows.isEmpty
                    ? const Center(child: Text('Nenhum registro no período'))
                    : ListView.builder(
                        itemCount: doc.rows.length,
                        itemBuilder: (_, n) {
                          final r = doc.rows[n];
                          final strong = r.kind != ReportRowKind.normal;
                          final style = strong ? const TextStyle(fontWeight: FontWeight.w600) : null;
                          final bg = switch (r.kind) {
                            ReportRowKind.section => theme.colorScheme.secondaryContainer,
                            ReportRowKind.total => theme.colorScheme.primaryContainer,
                            ReportRowKind.subtotal => theme.colorScheme.surfaceContainerHigh,
                            _ => null,
                          };
                          return Container(
                            decoration: BoxDecoration(color: bg, border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: .4)))),
                            child: r.kind == ReportRowKind.section
                                ? Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7), child: Text(r.cells.first, style: style))
                                : Row(children: [for (var i = 0; i < doc.headers.length; i++) cell(i < r.cells.length ? r.cells[i] : '', i, style: style)]),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Common layout: filters + search + actions above a table.
class _ReportPage extends StatelessWidget {
  const _ReportPage({required this.filters, required this.onSearch, required this.searchHint, required this.doc, required this.state, required this.sortCol, required this.ascending, required this.onSort});

  final List<Widget> filters;
  final ValueChanged<String> onSearch;
  final String searchHint;
  final ReportDoc doc;
  final ({bool loading, String? error}) state;
  final int? sortCol;
  final bool ascending;
  final ValueChanged<int> onSort;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ...filters,
          SizedBox(
            width: 260,
            child: TextField(
              decoration: InputDecoration(labelText: searchHint, prefixIcon: const Icon(Icons.search), isDense: true, border: const OutlineInputBorder()),
              onChanged: onSearch,
            ),
          ),
          ReportActions(doc: () => doc, enabled: !state.loading && state.error == null),
        ]),
        const SizedBox(height: 8),
        if (state.loading) const LinearProgressIndicator(),
        if (state.error != null) Padding(padding: const EdgeInsets.all(8), child: Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Expanded(child: ReportTable(doc: doc, sortCol: sortCol, ascending: ascending, onSort: onSort)),
        for (final n in doc.notes) Text(n, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

double _n(Object? v) => (v as num?)?.toDouble() ?? 0;

// ---------------------------------------------------------------------------
// Relatório de Consumo de Material Vendido (Consolidado)
// ---------------------------------------------------------------------------

class MaterialConsumptionScreen extends StatefulWidget {
  const MaterialConsumptionScreen({super.key, required this.session});

  final Session session;

  @override
  State<MaterialConsumptionScreen> createState() => _MaterialConsumptionScreenState();
}

class _MaterialConsumptionScreenState extends State<MaterialConsumptionScreen> {
  static const _headers = ['Código material', 'Descrição', 'UN', 'Data Movimento', 'Tipo/Nr.Docto', 'QTDE-KG Retirada', 'NF Venda', 'Observação'];

  late DateTime _from = _firstOfMonth(DateTime.now());
  late DateTime _to = _lastOfMonth(DateTime.now());
  String? _group;
  Map<String, String> _groups = {};
  String _code = '';
  String _q = '';
  int? _sortCol;
  bool _asc = true;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _load();
  }

  Future<void> _loadGroups() async {
    try {
      final g = await widget.session.api.listAll('/api/material-groups');
      if (mounted) setState(() => _groups = {for (final e in g) '${e['id']}': '${e['code']} · ${e['name']}'});
    } catch (_) {}
  }

  Future<void> _load() async {
    final r = ++_request;
    setState(() => _loading = true);
    try {
      final res = await widget.session.api.get('/api/reports/material-consumption', {
        'from': isoDate(_from),
        'to': isoDate(_to),
        'groupId': _group,
        'materialCode': _code,
        'q': _q,
      }) as Map<String, dynamic>;
      if (mounted && r == _request) {
        setState(() {
          _rows = (res['rows'] as List).cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && r == _request) setState(() => _error = '$e');
    } finally {
      if (mounted && r == _request) setState(() => _loading = false);
    }
  }

  Comparable<Object?> _key(Map<String, dynamic> e, int c) => switch (c) {
    0 => '${e['materialCode']}',
    1 => '${e['materialDescription']}',
    2 => '${e['unit']}',
    3 => '${e['date']}',
    4 => '${e['docType']} ${e['docNumber']}',
    5 => _n(e['quantityKg']),
    6 => '${e['invoiceNumber'] ?? ''}',
    _ => '${e['note']}',
  };

  ReportDoc _doc() {
    final byMaterial = <String, List<Map<String, dynamic>>>{};
    for (final e in _rows) {
      byMaterial.putIfAbsent('${e['materialCode']}', () => []).add(e);
    }
    final codes = byMaterial.keys.toList()..sort();
    final rows = <ReportRow>[];
    double total = 0;
    for (final code in codes) {
      final list = [...byMaterial[code]!];
      if (_sortCol != null) {
        list.sort((a, b) => _asc ? _key(a, _sortCol!).compareTo(_key(b, _sortCol!)) : _key(b, _sortCol!).compareTo(_key(a, _sortCol!)));
      }
      double sub = 0;
      for (final e in list) {
        sub += _n(e['quantityKg']);
        rows.add(ReportRow([
          '${e['materialCode']}',
          '${e['materialDescription']}',
          '${e['unit']}',
          fmtDay(e['date']),
          '${e['docType']} ${e['docNumber']}',
          fmtNum(e['quantityKg'], 3),
          fmt(e['invoiceNumber']),
          '${e['note']}',
        ]));
      }
      total += sub;
      rows.add(ReportRow(['Subtotal $code', list.first['materialDescription'] as String, '', '', '', fmtNum(sub, 3), '', ''], ReportRowKind.subtotal));
    }
    if (rows.isNotEmpty) rows.add(ReportRow(['Total geral', '', '', '', '', fmtNum(total, 3), '', ''], ReportRowKind.total));
    return ReportDoc(
      title: 'Relatório de Consumo de Material Vendido (Consolidado)',
      filters: [
        'Período: ${fmtDay(isoDate(_from))} a ${fmtDay(isoDate(_to))}',
        if (_group != null) 'Categoria: ${_groups[_group]}',
        if (_code.isNotEmpty) 'Material: $_code',
        if (_q.isNotEmpty) 'Busca: $_q',
      ],
      headers: _headers,
      numeric: const [false, false, false, false, false, true, false, false],
      flex: const [2, 4, 1, 2, 3, 2, 2, 4],
      rows: rows,
      notes: const ['Consumo = quantidade expedida × material por unidade (OP quando produzido, senão estrutura do produto).'],
    );
  }

  @override
  Widget build(BuildContext context) => _ReportPage(
    filters: [
      PeriodPicker(from: _from, to: _to, onChanged: (f, t) {
        setState(() {
          _from = f;
          _to = t;
        });
        _load();
      }),
      ChoiceFilter(label: 'Categoria', value: _group, choices: _groups, onChanged: (v) {
        setState(() => _group = v);
        _load();
      }),
      SizedBox(
        width: 160,
        child: TextField(
          decoration: const InputDecoration(labelText: 'Código material', isDense: true, border: OutlineInputBorder()),
          onSubmitted: (v) {
            _code = v.trim();
            _load();
          },
        ),
      ),
    ],
    searchHint: 'Buscar',
    onSearch: (v) {
      _q = v.trim();
      _load();
    },
    doc: _doc(),
    state: (loading: _loading, error: _error),
    sortCol: _sortCol,
    ascending: _asc,
    onSort: (i) => setState(() {
      _asc = _sortCol == i ? !_asc : true;
      _sortCol = i;
    }),
  );
}

// ---------------------------------------------------------------------------
// Resumo do Faturamento Consolidado no Período
// ---------------------------------------------------------------------------

class BillingSummaryScreen extends StatefulWidget {
  const BillingSummaryScreen({super.key, required this.session});

  final Session session;

  @override
  State<BillingSummaryScreen> createState() => _BillingSummaryScreenState();
}

class _BillingSummaryScreenState extends State<BillingSummaryScreen> {
  static const _headers = ['Cliente', 'Valor Fat.', '%', 'ICMS', 'IPI', 'Total S/IPI', 'QTD.KG', 'PM.V R\$', 'PM.M R\$'];
  static const _companies = {'EBT': 'EBT', 'BST': 'BST'};

  late DateTime _from = _firstOfMonth(DateTime.now());
  late DateTime _to = _lastOfMonth(DateTime.now());
  String? _company;
  String _q = '';
  int? _sortCol;
  bool _asc = true;
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = ++_request;
    setState(() => _loading = true);
    try {
      final res = await widget.session.api.get('/api/reports/billing-summary', {'from': isoDate(_from), 'to': isoDate(_to), 'company': _company}) as Map<String, dynamic>;
      if (mounted && r == _request) {
        setState(() {
          _data = res;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && r == _request) setState(() => _error = '$e');
    } finally {
      if (mounted && r == _request) setState(() => _loading = false);
    }
  }

  double _sortKey(Map<String, dynamic> e, int c) => switch (c) {
    1 || 2 => _n(e['billed']),
    3 => _n(e['icms']),
    4 => _n(e['ipi']),
    5 => _n(e['totalNoIpi']),
    6 => _n(e['kg']),
    7 => _n(e['avgSalePrice']),
    _ => _n(e['avgMaterialCost']),
  };

  List<String> _cells(Map<String, dynamic> e, String name, double base) => [
    name,
    fmtNum(e['billed']),
    base > 0 ? '${fmtNum(_n(e['billed']) / base * 100)}%' : '',
    fmtNum(e['icms']),
    fmtNum(e['ipi']),
    fmtNum(e['totalNoIpi']),
    fmtNum(e['kg'], 3),
    e['avgSalePrice'] == null ? '' : fmtNum(e['avgSalePrice'], 4),
    e['avgMaterialCost'] == null ? '' : fmtNum(e['avgMaterialCost'], 4),
  ];

  List<Map<String, dynamic>> _customers(Map<String, dynamic> section) {
    var list = (section['rows'] as List).cast<Map<String, dynamic>>();
    if (_q.isNotEmpty) list = list.where((e) => '${e['customer']}'.toLowerCase().contains(_q.toLowerCase())).toList();
    list = [...list];
    if (_sortCol != null) {
      list.sort((a, b) => _sortCol == 0
          ? (_asc ? '${a['customer']}'.compareTo('${b['customer']}') : '${b['customer']}'.compareTo('${a['customer']}'))
          : (_asc ? _sortKey(a, _sortCol!).compareTo(_sortKey(b, _sortCol!)) : _sortKey(b, _sortCol!).compareTo(_sortKey(a, _sortCol!))));
    }
    return list;
  }

  ReportDoc _doc() {
    final d = _data;
    final rows = <ReportRow>[];
    var notes = <String>[];
    if (d != null) {
      notes = (d['notes'] as List).cast<String>();
      final grand = d['grandTotal'] as Map<String, dynamic>;
      final base = _n(grand['billed']);
      for (final s in (d['companies'] as List).cast<Map<String, dynamic>>()) {
        final list = _customers(s);
        rows.add(ReportRow(['Empresa ${s['key']}'], ReportRowKind.section));
        for (final e in list) {
          rows.add(ReportRow(_cells(e, '${e['customer']}', base)));
        }
        rows.add(ReportRow(_cells(s['total'] as Map<String, dynamic>, 'Total ${s['key']}', base), ReportRowKind.subtotal));
      }
      rows.add(ReportRow(_cells(grand, 'Total faturado', base), ReportRowKind.total));
      final ret = d['returns'] as Map<String, dynamic>;
      rows.add(const ReportRow(['Devoluções'], ReportRowKind.section));
      for (final e in _customers(ret)) {
        rows.add(ReportRow(_cells(e, '${e['customer']}', base)));
      }
      rows.add(ReportRow(_cells(ret['total'] as Map<String, dynamic>, 'Total devoluções', base), ReportRowKind.subtotal));
      rows.add(ReportRow(_cells(d['net'] as Map<String, dynamic>, 'Faturamento líquido', base), ReportRowKind.total));
    }
    return ReportDoc(
      title: 'Resumo do Faturamento Consolidado no Período',
      filters: [
        'Período: ${fmtDay(isoDate(_from))} a ${fmtDay(isoDate(_to))}',
        'Empresa: ${_company ?? 'EBT + BST'}',
        if (_q.isNotEmpty) 'Busca: $_q',
      ],
      headers: _headers,
      numeric: const [false, true, true, true, true, true, true, true, true],
      flex: const [5, 2, 1, 2, 2, 2, 2, 2, 2],
      rows: rows,
      notes: notes,
    );
  }

  @override
  Widget build(BuildContext context) => _ReportPage(
    filters: [
      PeriodPicker(from: _from, to: _to, onChanged: (f, t) {
        setState(() {
          _from = f;
          _to = t;
        });
        _load();
      }),
      ChoiceFilter(label: 'Empresa', value: _company, choices: _companies, allLabel: 'EBT + BST', onChanged: (v) {
        setState(() => _company = v);
        _load();
      }),
    ],
    searchHint: 'Buscar cliente',
    onSearch: (v) => setState(() => _q = v.trim()),
    doc: _doc(),
    state: (loading: _loading, error: _error),
    sortCol: _sortCol,
    ascending: _asc,
    onSort: (i) => setState(() {
      _asc = _sortCol == i ? !_asc : true;
      _sortCol = i;
    }),
  );
}
