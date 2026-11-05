import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../api.dart';
import '../entities.dart';
import '../reports/print_docs.dart' show buildSimulationPdf;
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/entity_form.dart' show LookupField;
import '../widgets/page_column.dart';
import '../widgets/pipeline.dart' show Tone, toneColors;
import '../widgets/price_trend_chart.dart';
import '../widgets/print_panel.dart' show printPdf;
import '../widgets/record_list.dart' show SimpleTable;
import '../widgets/responsive.dart';
import '../widgets/tube_diagram.dart';

/// How the import button asks for the CSV; tests replace it (the system file dialog does not run there).
Future<({String name, Uint8List bytes})?> Function() priceHistoryFilePicker = pickPriceHistoryFile;

/// Today, for the age of the sales ("vendas de 3 a 17 meses atrás"); tests replace it.
DateTime Function() priceSimulatorNow = DateTime.now;

/// Lets the user choose the CSV of past sales to import.
Future<({String name, Uint8List bytes})?> pickPriceHistoryFile() async {
  final files = await FilePicker.pickFiles(dialogTitle: 'Importar histórico de vendas', type: FileType.custom, allowedExtensions: const ['csv', 'txt']);
  if (files.isEmpty) return null;
  final f = files.first;
  return (name: f.name, bytes: await f.readAsBytes());
}

const _months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

/// "out/2015" of an ISO date, or '' when it is not one.
String monthYear(Object? v) {
  final d = DateTime.tryParse('$v');
  return d == null ? '' : '${_months[d.month - 1]}/${d.year}';
}

/// Whole months between an ISO date and today (0 for this month or the future), or null when it is not a date.
int? monthsAgo(Object? v) {
  final d = v == null ? null : DateTime.tryParse('$v');
  if (d == null) return null;
  final now = priceSimulatorNow();
  return math.max(0, (now.year - d.year) * 12 + now.month - d.month);
}

/// Lower case without accents, to compare names the way a person does ("Açotubo" = "acotubo").
String foldText(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ', to = 'aaaaaeeeeiiiiooooouuuucn';
  var t = s.toLowerCase().trim();
  for (var i = 0; i < from.length; i++) {
    t = t.replaceAll(from[i], to[i]);
  }
  return t;
}

/// Weight the way a shop floor reads it: grams below 10 kg, kilograms above.
String fmtWeight(num kg) => kg < 10 ? '${fmtNum(kg * 1000, 0)} g' : '${fmtNum(kg, 3)} kg';

/// Material specification classes the server prices apart, with the label of the dropdown.
const materialSpecs = {
  'BK': 'BK (DIN 2393)',
  'GBK': 'GBK (DIN 2393, recozido em forno)',
  'NBK': 'NBK (DIN 2393 normalizado)',
  'EN10305': 'EN 10305',
  'NBR': 'NBR 5599',
  'SAE': 'SAE',
  'STKM13A': 'STKM13A (JIS G3445)',
};

/// The class of a standard written on a product or order line ("EN 10305-1 E355", "NBR 5599"), or null when it is not recognised.
String? classifyMaterialSpec(Object? standard) {
  // Mirrors the server (PriceSpec.Classify): accents folded, upper case, the most specific class first.
  final t = foldText('${standard ?? ''}').toUpperCase();
  if (t.trim().isEmpty) return null;
  if (RegExp(r'STKM\s*-?\s*13\s*-?\s*A').hasMatch(t)) return 'STKM13A';
  if (RegExp(r'\bGBK\b').hasMatch(t)) return 'GBK';
  if (RegExp(r'\bNBK\b').hasMatch(t)) return 'NBK';
  if (RegExp(r'\bBK\b').hasMatch(t)) return 'BK';
  if (t.contains('E420') || t.contains('E355') || t.contains('10305') || t.contains('CR2')) return 'EN10305';
  if (t.contains('5599') || t.contains('NBR')) return 'NBR';
  if (t.contains('SAE') || t.contains('1010') || t.contains('1008') || t.contains('1020')) return 'SAE';
  return null;
}

String _perUnit(Object? price, bool kg) => price is num ? '${fmtMoney(price)}/${kg ? 'kg' : 'peça'}' : '—';

/// The panel's door for its host: the host reads what is on screen (to save it) and puts a saved simulation back in the form.
class PriceSimulatorHandle {
  /// The simulation as `POST /api/sales/price-simulations` takes it, or null while there is no price on screen.
  Map<String, dynamic>? Function()? snapshot;

  /// Puts the inputs of a saved simulation back in the form.
  void Function(Map<String, dynamic> saved)? load;
}

/// Opens the simulator in a dialog. With [onUse] it offers "Usar este preço", which hands back the price of the item's own unit (per kg when
/// [unitIsKg], else per piece) written like the form field, and also returns it. Returns null when the dialog is closed without using a price.
/// [productId] lets the server use the product's own loss percent; [profile] with [width] and [height] opens the rectangular (or oblong) form.
Future<String?> showPriceSimulator(
  BuildContext context,
  Session session, {
  num? diameter,
  num? thickness,
  num? length,
  num? width,
  num? height,
  TubeProfile profile = TubeProfile.round,
  int? productId,
  String? spec,
  ({int id, String name})? customer,
  num? quantity,
  bool unitIsKg = false,
  void Function(String price)? onUse,
}) async {
  final price = await showDialog<String>(
    context: context,
    builder: (_) => _SimulatorDialog(
      session: session,
      diameter: diameter,
      thickness: thickness,
      length: length,
      width: width,
      height: height,
      profile: profile,
      productId: productId,
      spec: spec,
      customer: customer,
      quantity: quantity,
      unitIsKg: unitIsKg,
      canUse: onUse != null,
    ),
  );
  if (price != null) onUse?.call(price);
  return price;
}

class _SimulatorDialog extends StatefulWidget {
  const _SimulatorDialog({
    required this.session,
    required this.diameter,
    required this.thickness,
    required this.length,
    required this.width,
    required this.height,
    required this.profile,
    required this.productId,
    required this.spec,
    required this.customer,
    required this.quantity,
    required this.unitIsKg,
    required this.canUse,
  });

  final Session session;
  final num? diameter, thickness, length, width, height, quantity;
  final TubeProfile profile;
  final int? productId;
  final String? spec;
  final ({int id, String name})? customer;
  final bool unitIsKg, canUse;

  @override
  State<_SimulatorDialog> createState() => _SimulatorDialogState();
}

class _SimulatorDialogState extends State<_SimulatorDialog> {
  String? _price;
  final _handle = PriceSimulatorHandle();

  /// Keeps a record of the simulation that became a quote price. Fire and forget: a failure never holds the quote back.
  void _recordUse() {
    final body = _handle.snapshot?.call();
    if (body == null) return;
    unawaited(
      widget.session.api
          .post('/api/sales/price-simulations', {...body, 'usedInQuote': true})
          .then<void>((_) {}, onError: (Object e) => debugPrint('price_simulator: Not recording the simulation does not stop the quote: $e')),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Simulador de preço'),
    content: SizedBox(
      width: dialogWidth(context, 760),
      child: SingleChildScrollView(
        child: PriceSimulatorPanel(
          session: widget.session,
          diameter: widget.diameter,
          thickness: widget.thickness,
          length: widget.length,
          width: widget.width,
          height: widget.height,
          profile: widget.profile,
          productId: widget.productId,
          spec: widget.spec,
          customer: widget.customer,
          quantity: widget.quantity,
          unitIsKg: widget.unitIsKg,
          handle: _handle,
          onPrice: (p) {
            if (mounted && p != _price) setState(() => _price = p);
          },
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
      if (widget.canUse)
        Tooltip(
          message: _price == null ? 'Sem preço sugerido para usar' : 'Preenche o preço do item: R\$ $_price ${widget.unitIsKg ? 'por kg' : 'por peça'}',
          child: FilledButton(
            key: const ValueKey('price-sim-use'),
            onPressed: _price == null
                ? null
                : () {
                    _recordUse();
                    Navigator.pop(context, _price);
                  },
            child: const Text('Usar este preço'),
          ),
        ),
    ],
  );
}

/// The simulator as a screen of Comercial: history strip on top, then the calculator, then the saved simulations.
class PriceSimulatorScreen extends StatefulWidget {
  const PriceSimulatorScreen({super.key, required this.session});

  final Session session;

  @override
  State<PriceSimulatorScreen> createState() => _PriceSimulatorScreenState();
}

class _PriceSimulatorScreenState extends State<PriceSimulatorScreen> {
  Map<String, dynamic>? _summary;
  bool _loaded = false;
  bool _importing = false;
  final _handle = PriceSimulatorHandle();
  final _scroll = ScrollController();
  int _savedRev = 0;

  ApiClient get api => widget.session.api;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSummary());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    Map<String, dynamic>? s;
    try {
      final r = await api.get('/api/sales/price-history/summary');
      if (r is Map<String, dynamic>) s = r;
    } catch (e) {
      debugPrint('price_simulator: Without the summary the strip is left out; the calculator still works: $e');
    }
    if (mounted) {
      setState(() {
        _summary = s;
        _loaded = true;
      });
    }
  }

  Future<void> _import() async {
    if (_importing) return;
    final file = await priceHistoryFilePicker();
    if (file == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final r = await api.upload('/api/sales/price-history/import', 'file', file.name, file.bytes);
      if (!mounted) return;
      setState(() => _importing = false);
      await showDialog<void>(context: context, builder: (_) => _ImportResultDialog(file.name, r is Map<String, dynamic> ? r : const {}));
      await _loadSummary();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _strip(BuildContext context) {
    final s = _summary;
    if (!_loaded || s == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final count = (s['count'] as num?)?.toInt() ?? 0;
    final canImport = widget.session.canEditPrices;
    final empty = count == 0;
    final String text;
    if (empty) {
      text = canImport
          ? 'O histórico de vendas ainda não foi importado. Importe o arquivo CSV das vendas antigas para que a sugestão use os preços já praticados.'
          : 'O histórico de vendas ainda não foi importado: peça a um gerente para importar. Enquanto isso, só as vendas feitas no MetaGest entram na sugestão.';
    } else {
      final from = monthYear(s['firstDate']), to = monthYear(s['lastDate']);
      text = 'Histórico: ${fmtNum(count, 0)} vendas${from.isEmpty ? '' : ' ($from a $to)'}';
    }
    final (bg, fg) = toneColors(context, empty ? Tone.warning : Tone.neutral);
    return Card(
      key: const ValueKey('price-sim-history'),
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(empty ? Icons.inbox_outlined : Icons.history, color: fg),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
            ),
            if (canImport)
              OutlinedButton.icon(
                key: const ValueKey('price-sim-import'),
                onPressed: _importing ? null : _import,
                icon: _importing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file),
                label: const Text('Importar histórico (CSV)'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageColumn(
    maxWidth: 1000,
    child: ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _strip(context),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: PriceSimulatorPanel(session: widget.session, handle: _handle, onSaved: () => setState(() => _savedRev++)),
          ),
        ),
        _SavedSimulations(
          session: widget.session,
          revision: _savedRev,
          onOpen: (saved) {
            _handle.load?.call(saved);
            if (_scroll.hasClients) unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
          },
        ),
      ],
    ),
  );
}

/// "Simulações salvas": the last 20, newest first; opens when asked, tapping one puts its inputs back in the form.
class _SavedSimulations extends StatefulWidget {
  const _SavedSimulations({required this.session, required this.revision, required this.onOpen});

  final Session session;

  /// Changes when a simulation was saved, so an open list reloads.
  final int revision;
  final void Function(Map<String, dynamic> saved) onOpen;

  @override
  State<_SavedSimulations> createState() => _SavedSimulationsState();
}

class _SavedSimulationsState extends State<_SavedSimulations> {
  bool _open = false, _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  ApiClient get api => widget.session.api;

  @override
  void didUpdateWidget(_SavedSimulations old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision && _open) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get('/api/sales/price-simulations', {'take': 20});
      final list = r is List ? r : (r is Map ? (r['items'] as List? ?? const []) : const []);
      if (!mounted) return;
      setState(() {
        _items = [for (final e in list) (e as Map).cast<String, dynamic>()];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  bool _canDelete(Map<String, dynamic> e) {
    final s = widget.session;
    return e['createdBy'] == s.username || s.canApproveSales || s.role == 'Admin';
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir simulação?'),
        content: const Text('A simulação salva será apagada da lista. Isso não afeta nenhum orçamento.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await api.delete('/api/sales/price-simulations/${e['id']}');
      await _load();
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(err))));
    }
  }

  static String measureOf(Map<String, dynamic> e) {
    String p(Object? v) => v is num ? fmt(v) : '?';
    return switch (e['shape']) {
      'Oblong' => 'L ${p(e['width'])} × A ${p(e['height'])} × ${p(e['thickness'])} × ${p(e['length'])}',
      'Rectangular' => '${p(e['width'])} × ${p(e['height'])} × ${p(e['thickness'])} × ${p(e['length'])}',
      _ => 'ø ${p(e['diameter'])} × ${p(e['thickness'])} × ${p(e['length'])}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        key: const ValueKey('price-sim-saved'),
        title: const Text('Simulações salvas'),
        subtitle: const Text('As últimas 20. Toque numa para refazer a conta.'),
        initiallyExpanded: _open,
        onExpansionChanged: (v) {
          setState(() => _open = v);
          if (v) unawaited(_load());
        },
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (!_loading && _error == null && _items.isEmpty)
            const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Text('Nenhuma simulação salva ainda.')),
          for (final e in _items)
            ListTile(
              key: ValueKey('price-sim-saved-${e['id']}'),
              onTap: () => widget.onOpen(e),
              title: Text(
                [
                  measureOf(e),
                  if (materialSpecs[e['spec']] != null) '${e['spec']}',
                  if ('${e['customerName'] ?? ''}'.isNotEmpty) '${e['customerName']}',
                ].join(' · '),
              ),
              subtitle: Text(
                [
                  fmtDay(e['createdAt']),
                  '${e['createdBy'] ?? ''}',
                  if (e['pricePerKg'] is num) _perUnit(e['pricePerKg'], true),
                  if (e['pricePerPiece'] is num) _perUnit(e['pricePerPiece'], false),
                  if ('${e['note'] ?? ''}'.isNotEmpty) '${e['note']}',
                ].where((x) => x.isNotEmpty).join(' · '),
              ),
              trailing: Wrap(
                spacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (e['usedInQuote'] == true) _chip(context, 'usada no orçamento', Tone.success),
                  if (_canDelete(e))
                    IconButton(
                      key: ValueKey('price-sim-saved-delete-${e['id']}'),
                      tooltip: 'Excluir',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(e),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Widget _chip(BuildContext context, String text, Tone tone) {
  final (bg, fg) = toneColors(context, tone);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
    ),
  );
}

/// Asks for the optional note of a simulation to save. Pops the note ('' for none), or null when cancelled.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog();

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Salvar simulação'),
    content: TextField(
      key: const ValueKey('price-sim-note'),
      controller: _note,
      autofocus: true,
      maxLines: 2,
      decoration: const InputDecoration(labelText: 'Observação (opcional)', helperText: 'Por exemplo: para quem foi, ou por que esse preço'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: () => Navigator.pop(context, _note.text.trim()), child: const Text('Salvar')),
    ],
  );
}

class _ImportResultDialog extends StatelessWidget {
  const _ImportResultDialog(this.fileName, this.r);

  final String fileName;
  final Map<String, dynamic> r;

  /// "Ignoradas: 3 sem unidade válida, 1 com data inválida", from the server's counts by reason.
  static String skippedText(Object? reasons) {
    if (reasons is! Map) return '';
    const names = {'unidade': 'sem unidade válida', 'data': 'com data inválida', 'medidas': 'sem medidas válidas', 'preço': 'sem preço válido'};
    final parts = <String>[];
    for (final e in reasons.entries) {
      final n = e.value is num ? (e.value as num).toInt() : 0;
      if (n > 0) parts.add('${fmtNum(n, 0)} ${names['${e.key}'] ?? 'por ${e.key}'}');
    }
    return parts.isEmpty ? '' : 'Ignoradas: ${parts.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    final from = fmtDay(r['firstDate']), to = fmtDay(r['lastDate']);
    final why = skippedText(r['skippedReasons']);
    return AlertDialog(
      title: const Text('Histórico importado'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fileName, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          Text('Linhas lidas: ${fmtNum(n('read'), 0)}'),
          Text('Vendas importadas: ${fmtNum(n('imported'), 0)}'),
          Text('Atualizadas: ${fmtNum(n('updated'), 0)}'),
          Text('Já existiam (repetidas): ${fmtNum(n('duplicates'), 0)}'),
          Text('Ignoradas (dados incompletos): ${fmtNum(n('skipped'), 0)}'),
          if (why.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: Text(why, key: const ValueKey('price-sim-skipped-reasons')),
            ),
          if (from.isNotEmpty) Text('Período: $from a $to'),
        ],
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}

/// The clipboard text of a simulation sheet (see [buildSimulationPdf] for the keys).
String simulationSummary(Map<String, dynamic> s) {
  String money(Object? v, [String unit = '']) => v is num ? '${fmtMoney(v)}$unit' : '';
  String weight(Object? kg) => kg is num ? fmtWeight(kg) : '';
  final q = s['quantity'];
  final lines = <String>[
    'Simulação de preço${'${s['date'] ?? ''}'.isEmpty ? '' : ' de ${fmtDay(s['date'])}'}',
    '${s['shape'] ?? ''}: ${s['measures'] ?? ''}',
    if ('${s['spec'] ?? ''}'.isNotEmpty) 'Especificação: ${s['spec']}',
    if ('${s['customer'] ?? ''}'.isNotEmpty) 'Cliente: ${s['customer']}',
    if (q is num && q > 0) 'Quantidade: ${fmt(q)} ${q == 1 ? 'peça' : 'peças'}',
    'Peso: líquido ${weight(s['netKg'])}${s['grossKg'] is num ? ', bruto ${weight(s['grossKg'])}' : ''}',
    'Preço sugerido: ${money(s['pricePerKg'], '/kg')} · ${money(s['pricePerPiece'], '/peça')}${s['low'] is num && s['high'] is num ? ' (faixa ${money(s['low'])} a ${money(s['high'])}/kg)' : ''}',
    if (s['total'] is num) 'Total: ${money(s['total'])}',
    if (s['markupPercent'] is num && (s['markupPercent'] as num) > 0) 'Acréscimo pela forma: ${fmt(s['markupPercent'])}%',
    if ('${s['margin'] ?? ''}'.isNotEmpty) '${s['margin']}',
    'Confiança: ${s['confidence'] ?? ''}',
    '${s['reason'] ?? ''}',
    if ('${s['warning'] ?? ''}'.isNotEmpty) '${s['warning']}',
    if ('${s['note'] ?? ''}'.isNotEmpty) 'Observação: ${s['note']}',
    'Simulação interna, não é proposta.',
  ];
  return lines.where((l) => l.trim().isNotEmpty).join('\n');
}

/// Dimensions, customer and quantity in, weight and suggested price out; it recomputes by itself shortly after each change.
class PriceSimulatorPanel extends StatefulWidget {
  const PriceSimulatorPanel({
    super.key,
    required this.session,
    this.diameter,
    this.thickness,
    this.length,
    this.width,
    this.height,
    this.profile = TubeProfile.round,
    this.productId,
    this.spec,
    this.customer,
    this.quantity,
    this.unitIsKg = false,
    this.onPrice,
    this.handle,
    this.onSaved,
  });

  final Session session;
  final num? diameter, thickness, length, quantity;

  /// Outer sides of an oblong (width, height) or rectangular (side A, side B) tube.
  final num? width, height;

  /// The section to start with.
  final TubeProfile profile;

  /// The product the item is for, when known: the server then uses its own loss percent.
  final int? productId;

  /// Material specification class to start with (see [classifyMaterialSpec]); null = any.
  final String? spec;
  final ({int id, String name})? customer;

  /// The item the price is for is sold by the kilogram (the price handed to [onPrice] is per kg), else per piece.
  final bool unitIsKg;

  /// Called with the price of the item's unit written like a form field ("20,25"), or null when there is none to use.
  final ValueChanged<String?>? onPrice;

  /// Lets the host read the simulation on screen and load a saved one.
  final PriceSimulatorHandle? handle;

  /// Called after a simulation was saved.
  final VoidCallback? onSaved;

  /// Quiet time after the last keystroke before the request goes out.
  static const debounce = Duration(milliseconds: 400);

  @override
  State<PriceSimulatorPanel> createState() => _PriceSimulatorPanelState();
}

class _PriceSimulatorPanelState extends State<PriceSimulatorPanel> {
  late final _d = TextEditingController(text: widget.diameter == null ? '' : fmt(widget.diameter));
  late final _t = TextEditingController(text: widget.thickness == null ? '' : fmt(widget.thickness));
  late final _l = TextEditingController(text: widget.length == null ? '' : fmt(widget.length));
  late final _q = TextEditingController(text: widget.quantity == null ? '' : fmt(widget.quantity));
  late final _w = TextEditingController(text: widget.width == null ? '' : fmt(widget.width));
  late final _h = TextEditingController(text: widget.height == null ? '' : fmt(widget.height));
  late int? _customerId = widget.customer?.id;
  late String? _customerName = widget.customer?.name;
  late String? _spec = materialSpecs.containsKey(widget.spec) ? widget.spec : null;
  int _customerEpoch = 0;
  Timer? _timer;
  int _seq = 0;
  bool _loading = false;
  String? _error;
  bool _unavailable = false;
  Map<String, dynamic>? _data;
  String? _reportedPrice;

  // The field being edited is the measure the drawing draws strong.
  final _fd = FocusNode(), _fw = FocusNode(), _fh = FocusNode(), _ft = FocusNode(), _fl = FocusNode();
  TubeMeasure? _focused;

  // Round (diameter), oblong (width x height) or rectangular (side A x side B). The oblong and rectangular tubes are priced like the round tube
  // of the same perimeter, plus a markup for the shape that the person types. The steel cost is only for the margin line; it is never sent.
  late TubeProfile _profile = widget.profile;
  final _p = TextEditingController(), _cost = TextEditingController();

  ApiClient get api => widget.session.api;

  bool get _twoSides => _profile != TubeProfile.round;

  void _focusChanged() {
    final m = _fd.hasFocus
        ? TubeMeasure.diameter
        : _fw.hasFocus
        ? TubeMeasure.width
        : _fh.hasFocus
        ? TubeMeasure.height
        : _ft.hasFocus
        ? TubeMeasure.thickness
        : (_fl.hasFocus ? TubeMeasure.length : null);
    if (m != _focused && mounted) setState(() => _focused = m);
  }

  @override
  void initState() {
    super.initState();
    for (final f in [_fd, _fw, _fh, _ft, _fl]) {
      f.addListener(_focusChanged);
    }
    widget.handle
      ?..snapshot = _payload
      ..load = _loadSaved;
    if (_validation().ready) WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.handle?.snapshot == _payload) widget.handle?.snapshot = null;
    for (final c in [_d, _t, _l, _q, _w, _h, _p, _cost]) {
      c.dispose();
    }
    for (final f in [_fd, _fw, _fh, _ft, _fl]) {
      f.dispose();
    }
    super.dispose();
  }

  num? _n(TextEditingController c) => parseDecimal(c.text.trim());

  /// Messages for the fields that were typed wrong, and whether the dimensions are good to send.
  ({String? diameter, String? width, String? height, String? thickness, String? length, String? quantity, String? cost, bool ready}) _validation() {
    String? check(TextEditingController c) {
      if (c.text.trim().isEmpty) return null;
      final v = _n(c);
      if (v == null) return 'Digite um número.';
      if (v <= 0) return 'Informe um valor maior que zero.';
      return null;
    }

    final oblong = _profile == TubeProfile.oblong, rect = _profile == TubeProfile.rectangular;
    final d = _twoSides ? null : check(_d), t = check(_t), l = check(_l), q = check(_q);
    var w = _twoSides ? check(_w) : null;
    final h = _twoSides ? check(_h) : null;
    String? thick = t;
    final tv = _n(_t);
    final wv = _n(_w), hv = _n(_h);
    if (oblong) {
      if (w == null && wv != null && hv != null && wv > 0 && hv > 0 && wv < hv) w = 'A largura é o lado maior: não pode ser menor que a altura.';
      if (thick == null && hv != null && tv != null && hv > 0 && tv > 0 && tv * 2 >= hv) {
        thick = 'A espessura é grande demais: 2 × espessura precisa ser menor que a altura.';
      }
    } else if (rect) {
      if (thick == null && wv != null && hv != null && wv > 0 && hv > 0 && tv != null && tv > 0 && tv * 2 >= math.min(wv, hv)) {
        thick = 'A espessura é grande demais: 2 × espessura precisa ser menor que o menor lado.';
      }
    } else {
      final dv = _n(_d);
      if (thick == null && dv != null && tv != null && dv > 0 && tv > 0 && tv * 2 >= dv) {
        thick = 'A espessura é grande demais: 2 × espessura precisa ser menor que o diâmetro.';
      }
    }
    final all = (_twoSides ? [_w, _h, _t, _l] : [_d, _t, _l]).every((c) => c.text.trim().isNotEmpty);
    return (
      diameter: d,
      width: w,
      height: h,
      thickness: thick,
      length: l,
      quantity: q,
      cost: check(_cost),
      ready: all && d == null && w == null && h == null && thick == null && l == null && q == null,
    );
  }

  /// An input changed: whatever is on screen, or still on its way, belongs to other inputs. It is dropped at once (so "Usar este preço" cannot
  /// hand over the price of other measures), and the request for the new inputs goes out after a quiet moment.
  void _changed() {
    _timer?.cancel();
    final v = _validation();
    _seq++;
    setState(() {
      _data = null;
      _error = null;
      _loading = v.ready;
    });
    _report(null);
    if (v.ready) _timer = Timer(PriceSimulatorPanel.debounce, _run);
  }

  Future<void> _run() async {
    if (!mounted) return;
    final v = _validation();
    if (!v.ready) return;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final q = _n(_q);
    try {
      final r = await api.get('/api/sales/price-suggestion', {
        if (widget.productId != null) 'productId': widget.productId,
        if (_profile == TubeProfile.oblong) ...{
          'shape': 'oblong',
          'width': _n(_w),
          'height': _n(_h),
        } else if (_profile == TubeProfile.rectangular) ...{
          'shape': 'rect',
          'width': _n(_w),
          'height': _n(_h),
        } else
          'diameter': _n(_d),
        'thickness': _n(_t),
        'length': _n(_l),
        'customerId': _customerId,
        'spec': _spec,
        'quantity': q != null && q > 0 ? q : null,
      });
      if (!mounted || seq != _seq) return;
      setState(() {
        _data = r is Map<String, dynamic> ? r : null;
        _loading = false;
      });
      _report(_usablePrice());
    } catch (e) {
      if (!mounted || seq != _seq) return;
      final status = e is ApiException ? e.status : 0;
      setState(() {
        _loading = false;
        _data = null;
        _unavailable = status == 403 || status == 404;
        _error = _unavailable ? 'O simulador de preço não está disponível para o seu perfil.' : friendlyError(e);
      });
      _report(null);
    }
  }

  void _report(String? price) {
    if (price == _reportedPrice) return;
    _reportedPrice = price;
    widget.onPrice?.call(price);
  }

  /// The price of the item's unit, written like a form field; null when the history gave none.
  String? _usablePrice() {
    final s = _data?['suggestion'];
    if (s is! Map || s['basis'] == 'None') return null;
    final v = widget.unitIsKg ? s['pricePerKg'] : s['pricePerPiece'];
    return v is num ? fmtDecimalInput(_marked(v)) : null;
  }

  /// The markup typed for the oblong or rectangular shape (percent, 0 when empty or not a number).
  num get _markup {
    if (_profile == TubeProfile.round) return 0;
    final v = _n(_p);
    return v != null && v > 0 ? v : 0;
  }

  /// [price] with the shape's markup on it, to cents.
  num _marked(num price) => _markup == 0 ? price : (price * (1 + _markup / 100) * 100).round() / 100;

  Widget _numberField(
    String key,
    String label,
    TextEditingController c,
    String? error, {
    bool last = false,
    bool autofocus = false,
    FocusNode? focusNode,
    String? helper,
  }) => TextField(
    key: ValueKey(key),
    controller: c,
    focusNode: focusNode,
    autofocus: autofocus,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: last ? TextInputAction.done : TextInputAction.next,
    decoration: InputDecoration(labelText: label, errorText: error, errorMaxLines: 3, helperText: helper, helperMaxLines: 2, isDense: true),
    onChanged: (_) => _changed(),
  );

  String get _shapeName => switch (_profile) {
    TubeProfile.oblong => 'Oblong',
    TubeProfile.rectangular => 'Rectangular',
    TubeProfile.round => 'Round',
  };

  /// The simulation on screen as the server's `price-simulations` takes it, or null while there is no price.
  Map<String, dynamic>? _payload() {
    final r = _data;
    if (r == null) return null;
    final s = (r['suggestion'] as Map?)?.cast<String, dynamic>() ?? const {};
    final basis = s['basis'] as String? ?? 'None';
    if (basis == 'None') return null;
    final q = _n(_q), cost = _n(_cost);
    num? adj(Object? v) => v is num ? _marked(v) : null;
    return {
      'shape': _shapeName,
      'diameter': _twoSides ? null : _n(_d),
      'width': _twoSides ? _n(_w) : null,
      'height': _twoSides ? _n(_h) : null,
      'thickness': _n(_t),
      'length': _n(_l),
      'spec': _spec,
      'quantity': q != null && q > 0 ? q : null,
      'customerId': _customerId,
      'customerName': _customerName,
      'markupPercent': _markup == 0 ? null : _markup,
      'costPerKg': cost != null && cost > 0 ? cost : null,
      'pricePerKg': adj(s['pricePerKg']),
      'pricePerPiece': adj(s['pricePerPiece']),
      'basis': basis,
      'confidence': s['confidence'],
      'reason': _reason(r),
      'note': null,
      'usedInQuote': false,
    };
  }

  /// Puts the inputs of a saved simulation back in the form and asks for a new suggestion.
  void _loadSaved(Map<String, dynamic> s) {
    String t(Object? v) => v is num ? fmt(v) : '';
    setState(() {
      _profile = switch (s['shape']) {
        'Oblong' => TubeProfile.oblong,
        'Rectangular' => TubeProfile.rectangular,
        _ => TubeProfile.round,
      };
      _d.text = t(s['diameter']);
      _w.text = t(s['width']);
      _h.text = t(s['height']);
      _t.text = t(s['thickness']);
      _l.text = t(s['length']);
      _q.text = t(s['quantity']);
      _p.text = t(s['markupPercent']);
      _cost.text = t(s['costPerKg']);
      _spec = materialSpecs.containsKey(s['spec']) ? s['spec'] as String : null;
      _customerId = (s['customerId'] as num?)?.toInt();
      _customerName = '${s['customerName'] ?? ''}'.isEmpty ? null : '${s['customerName']}';
      _customerEpoch++;
    });
    _changed();
  }

  /// The sheet that goes to the clipboard and to the PDF.
  Map<String, dynamic> _sheet(Map<String, dynamic> r) {
    final weight = (r['weight'] as Map?)?.cast<String, dynamic>() ?? const {};
    final s = (r['suggestion'] as Map?)?.cast<String, dynamic>() ?? const {};
    num? adj(Object? v) => v is num ? _marked(v) : null;
    String m(TextEditingController c) => fmt(_n(c));
    final rest = 'espessura ${m(_t)} mm, comprimento ${m(_l)} mm';
    final (shape, measures) = switch (_profile) {
      TubeProfile.oblong => ('Tubo oblongo', 'largura ${m(_w)} mm × altura ${m(_h)} mm (por fora), $rest'),
      TubeProfile.rectangular => ('Tubo retangular', 'lados ${m(_w)} × ${m(_h)} mm (por fora), $rest'),
      TubeProfile.round => ('Tubo redondo', 'Ø ${m(_d)} mm, $rest'),
    };
    final margin = _margin(adj(s['pricePerKg']));
    final q = _n(_q);
    final cost = _n(_cost);
    return {
      'date': isoDate(priceSimulatorNow()),
      'shape': shape,
      'measures': measures,
      'spec': _spec == null ? '' : materialSpecs[_spec],
      'customer': _customerName ?? '',
      'quantity': q != null && q > 0 ? q : null,
      'netKg': weight['netKg'],
      'grossKg': weight['grossKg'],
      'lossPercent': weight['lossPercent'],
      'pricePerKg': adj(s['pricePerKg']),
      'pricePerPiece': adj(s['pricePerPiece']),
      'low': adj(s['low']),
      'high': adj(s['high']),
      'total': adj(s['totalForQuantity']),
      'confidence': switch (s['confidence']) {
        'High' => 'Alta',
        'Medium' => 'Média',
        _ => 'Baixa',
      },
      'reason': _reason(r),
      'warning': _weakNote(r) ?? '',
      'markupPercent': _markup == 0 ? null : _markup,
      'costPerKg': cost != null && cost > 0 ? cost : null,
      'margin': margin?.text ?? '',
      'similar': r['similar'] ?? const [],
    };
  }

  Future<void> _copy(Map<String, dynamic> r) async {
    await Clipboard.setData(ClipboardData(text: simulationSummary(_sheet(r))));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resumo copiado.')));
  }

  Future<void> _save() async {
    final body = _payload();
    if (body == null) return;
    final text = await showDialog<String>(context: context, builder: (_) => const _NoteDialog());
    if (text == null || !mounted) return;
    try {
      await api.post('/api/sales/price-simulations', {...body, 'note': text.isEmpty ? null : text, 'usedInQuote': false});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Simulação salva.')));
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _validation();
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 520;
        // Wide: the drawing sits beside the four fields, like a dimensioned sketch; otherwise it comes first.
        final sideBySide = box.maxWidth >= 860;
        const drawingWidth = 420.0;
        final fieldsWidth = sideBySide ? box.maxWidth - drawingWidth - AppSpacing.lg : box.maxWidth;
        // Every field gets room for its whole label (about 220 px); fewer per row rather than cut text.
        final fit = ((fieldsWidth + AppSpacing.md) / (220 + AppSpacing.md)).floor();
        final perRow = fit < 1 ? 1 : (fit > 4 ? 4 : fit);
        final w = perRow == 1 ? fieldsWidth : (fieldsWidth - (perRow - 1) * AppSpacing.md) / perRow;
        Widget sized(Widget child, [double? width]) => SizedBox(width: width ?? w, child: child);
        final oblong = _profile == TubeProfile.oblong, rect = _profile == TubeProfile.rectangular;
        final drawing = TubeDiagram(
          profile: _profile,
          diameter: _d.text,
          width: _w.text,
          height: _h.text,
          thickness: _t.text,
          length: _l.text,
          highlight: _focused,
        );
        final fields = Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            if (oblong) ...[
              sized(_numberField('price-sim-width', 'Largura (mm)', _w, v.width, autofocus: true, focusNode: _fw, helper: 'lado maior, por fora')),
              sized(_numberField('price-sim-height', 'Altura (mm)', _h, v.height, focusNode: _fh, helper: 'lado menor, por fora')),
            ] else if (rect) ...[
              sized(_numberField('price-sim-side-a', 'Lado A (mm)', _w, v.width, autofocus: widget.width == null, focusNode: _fw, helper: 'por fora')),
              sized(_numberField('price-sim-side-b', 'Lado B (mm)', _h, v.height, focusNode: _fh, helper: 'por fora. Quadrado: use lados iguais')),
            ] else
              sized(_numberField('price-sim-diameter', 'Diâmetro externo (mm)', _d, v.diameter, autofocus: widget.diameter == null, focusNode: _fd)),
            sized(_numberField('price-sim-thickness', 'Espessura (mm)', _t, v.thickness, focusNode: _ft)),
            sized(_numberField('price-sim-length', 'Comprimento (mm)', _l, v.length, focusNode: _fl)),
            sized(_numberField('price-sim-quantity', 'Quantidade (peças)', _q, v.quantity)),
            if (oblong || rect)
              sized(
                TextField(
                  key: const ValueKey('price-sim-markup'),
                  controller: _p,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Acréscimo (%)',
                    helperText: oblong ? 'pela conformação do oblongo' : 'pela conformação',
                    helperMaxLines: 2,
                    isDense: true,
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _report(_usablePrice());
                  },
                ),
              ),
            sized(
              TextField(
                key: const ValueKey('price-sim-cost'),
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Custo do aço (R\$/kg)',
                  errorText: v.cost,
                  helperText: 'opcional: só para ver a margem',
                  helperMaxLines: 2,
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        );
        final shapePicker = Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<TubeProfile>(
            key: const ValueKey('price-sim-shape'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: TubeProfile.round, label: Text('Redondo')),
              ButtonSegment(value: TubeProfile.oblong, label: Text('Oblongo')),
              ButtonSegment(value: TubeProfile.rectangular, label: Text('Retangular')),
            ],
            selected: {_profile},
            onSelectionChanged: (s) {
              setState(() => _profile = s.first);
              _changed();
            },
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            shapePicker,
            const SizedBox(height: AppSpacing.md),
            if (sideBySide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: fields),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(width: drawingWidth, child: drawing),
                ],
              )
            else ...[
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: narrow ? 320 : drawingWidth),
                  child: drawing,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              fields,
            ],
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String?>(
              key: const ValueKey('price-sim-spec'),
              initialValue: _spec,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Especificação', helperText: 'O tipo de aço muda bastante o preço por kg', isDense: true),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Qualquer')),
                for (final e in materialSpecs.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                setState(() => _spec = v);
                _changed();
              },
            ),
            const SizedBox(height: AppSpacing.md),
            KeyedSubtree(
              key: ValueKey('price-sim-customer-$_customerEpoch'),
              child: LookupField(
                key: const ValueKey('price-sim-customer'),
                api: api,
                spec: const LookupSpec('/api/customers'),
                label: 'Cliente (opcional)',
                hint: 'Com o cliente, o último preço cobrado dele pesa na sugestão',
                value: _customerId,
                initialDisplay: _customerName,
                onChanged: (id, entity) {
                  setState(() {
                    _customerId = id;
                    _customerName = entity == null ? null : (entity['name'] ?? entity['tradeName'] ?? '${entity['id']}') as String;
                  });
                  _changed();
                },
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
                child: LinearProgressIndicator(key: ValueKey('price-sim-loading')),
              ),
            // A live region: a screen reader announces the new suggestion (or the error) when it replaces the old one.
            Semantics(
              liveRegion: true,
              container: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Text(
                      _error!,
                      key: const ValueKey('price-sim-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    )
                  else if (_data != null)
                    _result(context, _data!)
                  else if (!v.ready)
                    Text(
                      switch (_profile) {
                        TubeProfile.oblong => 'Digite a largura, a altura, a espessura e o comprimento para ver o peso e o preço sugerido.',
                        TubeProfile.rectangular => 'Digite os lados A e B, a espessura e o comprimento para ver o peso e o preço sugerido.',
                        TubeProfile.round => 'Digite o diâmetro, a espessura e o comprimento para ver o peso e o preço sugerido.',
                      },
                      key: const ValueKey('price-sim-hint'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// A short title above a block of the result.
  Widget _title(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
  );

  Widget _result(BuildContext context, Map<String, dynamic> r) {
    final theme = Theme.of(context);
    final weight = (r['weight'] as Map?)?.cast<String, dynamic>() ?? const {};
    final s = (r['suggestion'] as Map?)?.cast<String, dynamic>() ?? const {};
    final basis = s['basis'] as String? ?? 'None';
    final net = weight['netKg'] as num?, gross = weight['grossKg'] as num?, loss = weight['lossPercent'] as num?;
    final last = (r['customerLast'] as Map?)?.cast<String, dynamic>();
    final rows = _similarRows(r);
    final q = _n(_q);
    final hasPrice = basis != 'None';
    final profile = (r['profile'] as Map?)?.cast<String, dynamic>();
    num? adj(Object? v) => v is num ? _marked(v) : null;
    final history = [for (final e in (r['customerHistory'] as List? ?? const [])) (e as Map).cast<String, dynamic>()];
    final factor = (r['customerFactor'] as Map?)?.cast<String, dynamic>();
    final bySpec = [for (final e in (r['bySpec'] as List? ?? const [])) (e as Map).cast<String, dynamic>()];
    final weak = hasPrice ? _weakNote(r) : null;
    final margin = hasPrice ? _margin(adj(s['pricePerKg'])) : null;
    final customerTrend = TrendPoint.parse(r['customerTrend']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (net != null)
          Text(
            'Peso líquido ${fmtWeight(net)}${gross == null ? '' : '  ·  Peso bruto ${fmtWeight(gross)}${loss == null ? '' : ' (+${fmtNum(loss, 1)}%)'}'}',
            key: const ValueKey('price-sim-weight'),
            style: theme.textTheme.titleMedium,
          ),
        const SizedBox(height: AppSpacing.md),
        if (hasPrice) ...[
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Sugestão: ${_perUnit(adj(s['pricePerKg']), true)}  ·  ${_perUnit(adj(s['pricePerPiece']), false)}',
                key: const ValueKey('price-sim-suggestion'),
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              _confidence(context, s['confidence'] as String?),
            ],
          ),
          if (s['low'] is num && s['high'] is num)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'faixa ${fmtMoney(adj(s['low']))} – ${fmtMoney(adj(s['high']))}/kg',
                key: const ValueKey('price-sim-range'),
                style: theme.textTheme.bodyLarge,
              ),
            ),
          if (q != null && q > 0 && s['totalForQuantity'] is num)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '${fmt(q)} ${q == 1 ? 'peça' : 'peças'}: ${fmtMoney(adj(s['totalForQuantity']))}',
                key: const ValueKey('price-sim-total'),
                style: theme.textTheme.titleMedium,
              ),
            ),
          if (margin != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                margin.text,
                key: const ValueKey('price-sim-margin'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: margin.warn ? toneColors(context, Tone.danger).$2 : null,
                  fontWeight: margin.warn ? FontWeight.w700 : null,
                ),
              ),
            ),
        ] else
          Text('Sem vendas parecidas: digite o preço', key: const ValueKey('price-sim-none'), style: theme.textTheme.titleMedium),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            _reason(r),
            key: const ValueKey('price-sim-reason'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        if (weak != null) _weakBanner(context, weak),
        if (hasPrice && _noSpecSales(rows, bySpec)) _specNote(context),
        if (profile != null && (profile['shape'] == 'Oblong' || profile['shape'] == 'Rectangular'))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Preço do tubo redondo de mesmo perímetro (Ø ${fmt(profile['equivalentDiameter'])} mm), porque o histórico só tem tubos redondos.'
              '${_markup > 0 ? ' Já inclui o acréscimo de ${fmt(_markup)}% pela forma.' : ' Some o acréscimo da conformação no campo de acréscimo.'}',
              key: const ValueKey('price-sim-oblong-note'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        if (last != null && history.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(_lastText(last), key: const ValueKey('price-sim-last'), style: theme.textTheme.bodyMedium),
          ),
        if (hasPrice)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('price-sim-copy'),
                  onPressed: () => _copy(r),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copiar resumo'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('price-sim-print'),
                  onPressed: () => printPdf(context, 'Simulação de preço', () => buildSimulationPdf(api, _sheet(r))),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Imprimir / PDF'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('price-sim-save'),
                  onPressed: _save,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Salvar simulação'),
                ),
              ],
            ),
          ),
        if (history.isNotEmpty) ..._customerBlock(context, history, customerTrend),
        if (factor != null && ((factor['sampleSize'] as num?) ?? 0) >= 3 && factor['ratio'] is num) _factorLine(context, factor),
        if (_spec == null && bySpec.length >= 2) ..._bySpecBlock(context, bySpec),
        if (TrendPoint.parse(r['trend']).length >= 3) ...[
          const SizedBox(height: AppSpacing.lg),
          PriceTrendChart(points: TrendPoint.parse(r['trend']), customerPoints: customerTrend, customerLabel: _customerName ?? 'Este cliente'),
        ],
        _title(context, 'Vendas parecidas'),
        SimpleTable(
          key: const ValueKey('price-sim-similar'),
          emptyText: 'Nenhuma venda parecida encontrada',
          columns: [
            ColumnSpec('Data', (e) => fmtDay(e['date'])),
            ColumnSpec('Cliente', (e) => '${e['customer'] ?? ''}'),
            const ColumnSpec('Medida', _measure),
            ColumnSpec('Espec.', (e) => (e['spec'] as String?) ?? '—'),
            ColumnSpec('Un.', (e) => '${e['unit'] ?? ''}'),
            ColumnSpec('Preço unitário', (e) => e['unitPrice'] is num ? fmtMoney(e['unitPrice']) : '', numeric: true),
            ColumnSpec('R\$/kg', (e) => e['pricePerKg'] is num ? fmtMoney(e['pricePerKg']) : '', numeric: true),
            ColumnSpec('Origem', (e) => '${e['source'] ?? ''}'),
            ColumnSpec('Combina', _matchText),
          ],
          rows: rows,
          rowColor: (e) => _matchText(e).isNotEmpty ? toneColors(context, Tone.info).$1 : null,
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _similarRows(Map<String, dynamic> r) =>
      [for (final e in (r['similar'] as List? ?? const [])) (e as Map).cast<String, dynamic>()]
        ..sort((a, b) => ((a['distance'] as num?) ?? double.infinity).compareTo((b['distance'] as num?) ?? double.infinity));

  /// Does the sale of [name] belong to the chosen customer? Names are compared without case and accents, one inside the other.
  bool _sameCustomer(Object? name) {
    final mine = foldText(_customerName ?? ''), theirs = foldText('${name ?? ''}');
    return mine.isNotEmpty && theirs.isNotEmpty && (theirs.contains(mine) || mine.contains(theirs));
  }

  /// What makes a similar sale stand out, in words (the row colour alone would not reach everyone).
  String _matchText(Map<String, dynamic> e) {
    final parts = [if (_sameCustomer(e['customer'])) 'mesmo cliente', if (_spec != null && e['spec'] == _spec) 'mesma espec.'];
    return parts.isEmpty ? '' : '● ${parts.join(' · ')}';
  }

  /// The chosen specification has no sale of its own in the history: neither among the similar sales nor in the by-specification list.
  bool _noSpecSales(List<Map<String, dynamic>> rows, List<Map<String, dynamic>> bySpec) {
    final s = _spec;
    if (s == null) return false;
    return !rows.any((e) => e['spec'] == s) && !bySpec.any((e) => e['spec'] == s);
  }

  Widget _specNote(BuildContext context) {
    final s = _spec!;
    final name = (materialSpecs[s] ?? s).split(' (').first;
    final why = switch (s) {
      'GBK' => 'GBK passa pelo forno (recozimento)',
      'STKM13A' => 'STKM13A é outro aço',
      _ => 'a especificação pode mudar o preço',
    };
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        'Sem vendas de $name no histórico: a sugestão vem de tubos de outra especificação. $why: some o acréscimo no campo de acréscimo.',
        key: const ValueKey('price-sim-spec-note'),
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _weakBanner(BuildContext context, String text) {
    final (bg, fg) = toneColors(context, Tone.warning);
    return Container(
      key: const ValueKey('price-sim-weak'),
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: fg, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Margin on the cost typed by the person: (price - cost) / price, on [pricePerKg], which already has the markup. Null without a cost.
  ({String text, bool warn})? _margin(num? pricePerKg) {
    final c = _n(_cost);
    if (c == null || c <= 0 || pricePerKg == null) return null;
    final p = pricePerKg; // already with the markup
    if (p <= 0) return null;
    final m = (p - c) / p * 100;
    return (text: 'Margem sobre o custo: ${fmtNum(m, 0)}% (${fmtMoney(p - c)}/kg)', warn: m < 10);
  }

  /// A warning when the suggestion stands on little or old data, else null: fewer than 3 sales, the newest more than 12 months old, or the most similar sale that old.
  String? _weakNote(Map<String, dynamic> r) {
    final s = (r['suggestion'] as Map?)?.cast<String, dynamic>() ?? const {};
    final basis = s['basis'] as String? ?? 'None';
    const confirm = ' Confira antes de usar.';
    if (basis == 'CustomerRepeat') {
      final date = (r['repeat'] as Map?)?['date'];
      final age = monthsAgo(date);
      return age != null && age > 12 ? 'O último preço cobrado deste cliente para esta medida é de ${monthYear(date)}.$confirm' : null;
    }
    if (basis != 'Neighbours') return null;
    final used = (s['usedCount'] as num?)?.toInt();
    final newest = s['newestDate'];
    final newestAge = monthsAgo(newest);
    final few = used != null && used < 3;
    final oldNewest = newestAge != null && newestAge > 12;
    if (few || oldNewest) {
      final lead = used != null ? 'Baseado em $used ${used == 1 ? 'venda' : 'vendas'}' : 'Poucas vendas na base';
      return '$lead${newestAge == null ? '' : ', a mais recente de ${monthYear(newest)}'}.$confirm';
    }
    final rows = _similarRows(r);
    if (rows.isNotEmpty) {
      final nearest = rows.first['date'];
      final age = monthsAgo(nearest);
      if (age != null && age > 12) return 'A venda mais parecida é de ${monthYear(nearest)}.$confirm';
    }
    return null;
  }

  static String _monthsText(int n) => n == 0 ? 'deste mês' : (n == 1 ? 'de 1 mês atrás' : 'de $n meses atrás');

  /// Why the price is what it is, with the age of the sales it stands on.
  String _reason(Map<String, dynamic> r) {
    final s = (r['suggestion'] as Map?)?.cast<String, dynamic>() ?? const {};
    final basis = s['basis'] as String? ?? 'None';
    switch (basis) {
      case 'CustomerRepeat':
        final repeat = (r['repeat'] as Map?)?.cast<String, dynamic>();
        final who = '${repeat?['customer'] ?? ''}'.isNotEmpty ? '${repeat!['customer']}' : (_customerName ?? 'este cliente');
        final date = fmtDay(repeat?['date']);
        final kg = repeat?['pricePerKg'];
        final age = monthsAgo(repeat?['date']);
        return 'Mesmo preço cobrado de $who${date.isEmpty ? '' : ' em $date'}${kg is num ? ' (${fmtMoney(kg)}/kg)' : ''} para esta medida${age == null ? '' : ' (venda ${_monthsText(age)})'}';
      case 'Neighbours':
        final used = (s['usedCount'] as num?)?.toInt() ?? _similarRows(r).length;
        final base = 'Baseado em $used ${used == 1 ? 'venda parecida' : 'vendas parecidas'}';
        final newest = s['newestDate'], oldest = s['oldestDate'];
        final newestAge = monthsAgo(newest), oldestAge = monthsAgo(oldest);
        if (newestAge == null) return '$base dos últimos 24 meses';
        final newestMy = monthYear(newest), oldestMy = monthYear(oldest);
        final dates = ', a mais recente é de $newestMy${oldestAge != null && oldestMy != newestMy ? ' e a mais antiga de $oldestMy' : ''}';
        final String age;
        if (oldestAge == null || oldestAge == newestAge) {
          age = ' (venda ${_monthsText(newestAge)})';
        } else {
          age = newestAge == 0 ? ' (vendas de até $oldestAge meses atrás)' : ' (vendas de $newestAge a $oldestAge meses atrás)';
        }
        return '$base$dates$age';
      default:
        return 'Sem vendas parecidas: digite o preço';
    }
  }

  /// "Este cliente pagou": his last sales and how the price moved between them; his own chart when there are two months or more.
  List<Widget> _customerBlock(BuildContext context, List<Map<String, dynamic>> history, List<TrendPoint> trend) {
    String change(int i) {
      if (i + 1 >= history.length) return '—';
      final a = history[i]['pricePerKg'], b = history[i + 1]['pricePerKg'];
      if (a is! num || b is! num || b <= 0) return '—';
      final pct = (a - b) / b * 100;
      if (pct.abs() < 0.5) return 'igual';
      final rounded = pct.round();
      final txt = rounded == 0 ? fmtNum(pct.abs(), 1) : '${rounded.abs()}';
      return '${pct > 0 ? '+' : '-'}$txt%';
    }

    final rows = [
      for (final (i, e) in history.indexed) {...e, '_change': change(i)},
    ];
    return [
      _title(context, 'Este cliente pagou'),
      SimpleTable(
        key: const ValueKey('price-sim-customer-history'),
        columns: [
          ColumnSpec('Data', (e) => fmtDay(e['date'])),
          ColumnSpec('Un.', (e) => '${e['unit'] ?? ''}'),
          ColumnSpec('Qtd.', (e) => e['quantity'] is num ? fmt(e['quantity']) : '—', numeric: true),
          ColumnSpec('Preço unitário', (e) => e['unitPrice'] is num ? fmtMoney(e['unitPrice']) : '', numeric: true),
          ColumnSpec('R\$/kg', (e) => e['pricePerKg'] is num ? fmtMoney(e['pricePerKg']) : '', numeric: true),
          ColumnSpec('Variação', (e) => '${e['_change']}', numeric: true),
        ],
        rows: rows,
      ),
      if (trend.length >= 2) ...[
        const SizedBox(height: AppSpacing.sm),
        PriceTrendChart(
          key: const ValueKey('price-sim-customer-trend'),
          points: trend,
          title: 'R\$/kg pago por este cliente',
          primaryLabel: _customerName ?? 'Este cliente',
          minPoints: 2,
          height: 150,
        ),
      ],
    ];
  }

  Widget _factorLine(BuildContext context, Map<String, dynamic> f) {
    final ratio = (f['ratio'] as num).toDouble();
    final diff = ((1 - ratio) * 100).round();
    final how = diff == 0 ? 'o mesmo que' : '${diff.abs()}% ${diff > 0 ? 'abaixo' : 'acima'} de';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        'Este cliente costuma pagar $how tubos parecidos (${f['sampleSize']} vendas). É só uma informação: não entra na sugestão.',
        key: const ValueKey('price-sim-factor'),
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  /// "Preço por especificação": the median price of each steel class of the similar sales, and how much the class moves it.
  List<Widget> _bySpecBlock(BuildContext context, List<Map<String, dynamic>> bySpec) {
    final prices = [
      for (final e in bySpec)
        if (e['medianPerKg'] is num) (e['medianPerKg'] as num).toDouble(),
    ];
    final lo = prices.isEmpty ? 0.0 : prices.reduce(math.min), hi = prices.isEmpty ? 0.0 : prices.reduce(math.max);
    final spread = lo > 0 ? ((hi - lo) / lo * 100).round() : 0;
    return [
      _title(context, 'Preço por especificação'),
      SimpleTable(
        key: const ValueKey('price-sim-by-spec'),
        columns: [
          ColumnSpec('Especificação', (e) => materialSpecs['${e['spec']}'] ?? '${e['spec']}'),
          ColumnSpec('Mediana R\$/kg', (e) => e['medianPerKg'] is num ? fmtMoney(e['medianPerKg']) : '—', numeric: true),
          ColumnSpec('Vendas', (e) => '${e['count'] ?? 0} ${(e['count'] ?? 0) == 1 ? 'venda' : 'vendas'}', numeric: true),
        ],
        rows: bySpec,
      ),
      if (spread > 0)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            'A especificação muda o preço em até $spread%. Escolha uma acima para a sugestão usar só ela.',
            key: const ValueKey('price-sim-spread'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
    ];
  }

  String _lastText(Map<String, dynamic> last) {
    final kg = last['unit'] == 'KG';
    final extra = !kg && last['pricePerKg'] is num ? ' (${_perUnit(last['pricePerKg'], true)})' : '';
    final date = fmtDay(last['date']);
    return 'Último preço deste cliente: ${_perUnit(last['unitPrice'], kg)}$extra${date.isEmpty ? '' : ' em $date'} · ${_measure(last)}';
  }

  static String _measure(Map<String, dynamic> e) {
    String p(Object? v) => v is num ? fmt(v) : '?';
    return 'ø ${p(e['diameter'])} × ${p(e['thickness'])} × ${p(e['length'])}';
  }

  Widget _confidence(BuildContext context, String? confidence) {
    final (label, tone) = switch (confidence) {
      'High' => ('Alta', Tone.success),
      'Medium' => ('Média', Tone.warning),
      _ => ('Baixa', Tone.danger),
    };
    final (bg, fg) = toneColors(context, tone);
    return Semantics(
      container: true,
      label: 'Confiança da sugestão: $label',
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('price-sim-confidence'),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text(
            'Confiança $label',
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
