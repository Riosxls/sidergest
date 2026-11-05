import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/entity_form.dart' show LookupField;
import '../widgets/page_column.dart';
import '../widgets/pipeline.dart' show Tone, toneColors;
import '../widgets/record_list.dart' show SimpleTable;
import '../widgets/responsive.dart';
import '../widgets/tube_diagram.dart';

/// How the import button asks for the CSV; tests replace it (the system file dialog does not run there).
Future<({String name, Uint8List bytes})?> Function() priceHistoryFilePicker = pickPriceHistoryFile;

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

/// Weight the way a shop floor reads it: grams below 10 kg, kilograms above.
String fmtWeight(num kg) => kg < 10 ? '${fmtNum(kg * 1000, 0)} g' : '${fmtNum(kg, 3)} kg';

/// Material specification classes the server prices apart, with the label of the dropdown.
const materialSpecs = {
  'BK': 'BK (DIN 2393)',
  'NBK': 'NBK (DIN 2393 normalizado)',
  'EN10305': 'EN 10305',
  'NBR': 'NBR 5599',
  'SAE': 'SAE',
};

/// The class of a standard written on a product or order line ("EN 10305-1 E355", "NBR 5599"), or null when it is not recognised.
String? classifyMaterialSpec(Object? standard) {
  final t = '${standard ?? ''}'.toUpperCase();
  if (t.trim().isEmpty) return null;
  if (t.contains('E420') || t.contains('E355') || t.contains('10305') || t.contains('CR2')) return 'EN10305';
  if (t.contains('NBK')) return 'NBK';
  if (t.contains('BK')) return 'BK';
  if (t.contains('5599') || t.contains('NBR')) return 'NBR';
  if (t.contains('SAE') || t.contains('1010') || t.contains('1008') || t.contains('1020')) return 'SAE';
  return null;
}

String _perUnit(Object? price, bool kg) => price is num ? '${fmtMoney(price)}/${kg ? 'kg' : 'peça'}' : '—';

/// Opens the simulator in a dialog. With [onUse] it offers "Usar este preço", which hands back the price of the item's own unit (per kg when
/// [unitIsKg], else per piece) written like the form field, and also returns it. Returns null when the dialog is closed without using a price.
Future<String?> showPriceSimulator(
  BuildContext context,
  Session session, {
  num? diameter,
  num? thickness,
  num? length,
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
    required this.spec,
    required this.customer,
    required this.quantity,
    required this.unitIsKg,
    required this.canUse,
  });

  final Session session;
  final num? diameter, thickness, length, quantity;
  final String? spec;
  final ({int id, String name})? customer;
  final bool unitIsKg, canUse;

  @override
  State<_SimulatorDialog> createState() => _SimulatorDialogState();
}

class _SimulatorDialogState extends State<_SimulatorDialog> {
  String? _price;

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
          spec: widget.spec,
          customer: widget.customer,
          quantity: widget.quantity,
          unitIsKg: widget.unitIsKg,
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
          child: FilledButton(key: const ValueKey('price-sim-use'), onPressed: _price == null ? null : () => Navigator.pop(context, _price), child: const Text('Usar este preço')),
        ),
    ],
  );
}

/// The simulator as a screen of Comercial: history strip on top, then the calculator.
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

  ApiClient get api => widget.session.api;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSummary());
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _strip(context),
        Card(
          child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: PriceSimulatorPanel(session: widget.session)),
        ),
      ],
    ),
  );
}

class _ImportResultDialog extends StatelessWidget {
  const _ImportResultDialog(this.fileName, this.r);

  final String fileName;
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    final from = fmtDay(r['firstDate']), to = fmtDay(r['lastDate']);
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
          Text('Já existiam (repetidas): ${fmtNum(n('duplicates'), 0)}'),
          Text('Ignoradas (dados incompletos): ${fmtNum(n('skipped'), 0)}'),
          if (from.isNotEmpty) Text('Período: $from a $to'),
        ],
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}

/// Dimensions, customer and quantity in, weight and suggested price out; it recomputes by itself shortly after each change.
class PriceSimulatorPanel extends StatefulWidget {
  const PriceSimulatorPanel({
    super.key,
    required this.session,
    this.diameter,
    this.thickness,
    this.length,
    this.spec,
    this.customer,
    this.quantity,
    this.unitIsKg = false,
    this.onPrice,
  });

  final Session session;
  final num? diameter, thickness, length, quantity;

  /// Material specification class to start with (see [classifyMaterialSpec]); null = any.
  final String? spec;
  final ({int id, String name})? customer;

  /// The item the price is for is sold by the kilogram (the price handed to [onPrice] is per kg), else per piece.
  final bool unitIsKg;

  /// Called with the price of the item's unit written like a form field ("20,25"), or null when there is none to use.
  final ValueChanged<String?>? onPrice;

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
  late int? _customerId = widget.customer?.id;
  late String? _customerName = widget.customer?.name;
  late String? _spec = materialSpecs.containsKey(widget.spec) ? widget.spec : null;
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

  // Round (diameter) or oblong (width x height). The oblong tube's price is the round one's, plus a markup for the shape that the person types.
  TubeProfile _profile = TubeProfile.round;
  final _w = TextEditingController(), _h = TextEditingController(), _p = TextEditingController();

  ApiClient get api => widget.session.api;

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
    if (_validation().ready) WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_d, _t, _l, _q, _w, _h, _p]) {
      c.dispose();
    }
    for (final f in [_fd, _fw, _fh, _ft, _fl]) {
      f.dispose();
    }
    super.dispose();
  }

  num? _n(TextEditingController c) => parseDecimal(c.text.trim());

  /// Messages for the fields that were typed wrong, and whether the three dimensions are good to send.
  ({String? diameter, String? width, String? height, String? thickness, String? length, String? quantity, bool ready}) _validation() {
    String? check(TextEditingController c) {
      if (c.text.trim().isEmpty) return null;
      final v = _n(c);
      if (v == null) return 'Digite um número.';
      if (v <= 0) return 'Informe um valor maior que zero.';
      return null;
    }

    final oblong = _profile == TubeProfile.oblong;
    final d = oblong ? null : check(_d), t = check(_t), l = check(_l), q = check(_q);
    var w = oblong ? check(_w) : null;
    final h = oblong ? check(_h) : null;
    String? thick = t;
    final tv = _n(_t);
    if (oblong) {
      final wv = _n(_w), hv = _n(_h);
      if (w == null && wv != null && hv != null && wv > 0 && hv > 0 && wv < hv) w = 'A largura é o lado maior: não pode ser menor que a altura.';
      if (thick == null && hv != null && tv != null && hv > 0 && tv > 0 && tv * 2 >= hv) {
        thick = 'A espessura é grande demais: 2 × espessura precisa ser menor que a altura.';
      }
    } else {
      final dv = _n(_d);
      if (thick == null && dv != null && tv != null && dv > 0 && tv > 0 && tv * 2 >= dv) {
        thick = 'A espessura é grande demais: 2 × espessura precisa ser menor que o diâmetro.';
      }
    }
    final all = (oblong ? [_w, _h, _t, _l] : [_d, _t, _l]).every((c) => c.text.trim().isNotEmpty);
    return (
      diameter: d,
      width: w,
      height: h,
      thickness: thick,
      length: l,
      quantity: q,
      ready: all && d == null && w == null && h == null && thick == null && l == null && q == null,
    );
  }

  void _changed() {
    _timer?.cancel();
    final v = _validation();
    setState(() {
      if (!v.ready) {
        // Old numbers for other measures would mislead; wait for a valid set.
        _seq++;
        _loading = false;
        _error = null;
      }
    });
    if (!v.ready) {
      setState(() => _data = null);
      _report(null);
      return;
    }
    _timer = Timer(PriceSimulatorPanel.debounce, _run);
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
        if (_profile == TubeProfile.oblong) ...{'shape': 'oblong', 'width': _n(_w), 'height': _n(_h)} else 'diameter': _n(_d),
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

  /// The markup typed for the oblong shape (percent, 0 when empty or not a number).
  num get _markup {
    if (_profile != TubeProfile.oblong) return 0;
    final v = _n(_p);
    return v != null && v > 0 ? v : 0;
  }

  /// [price] with the shape's markup on it, to cents.
  num _marked(num price) => _markup == 0 ? price : (price * (1 + _markup / 100) * 100).round() / 100;

  Widget _numberField(String key, String label, TextEditingController c, String? error, {bool last = false, bool autofocus = false, FocusNode? focusNode}) => TextField(
    key: ValueKey(key),
    controller: c,
    focusNode: focusNode,
    autofocus: autofocus,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: last ? TextInputAction.done : TextInputAction.next,
    decoration: InputDecoration(labelText: label, errorText: error, errorMaxLines: 3, isDense: true),
    onChanged: (_) => _changed(),
  );

  @override
  Widget build(BuildContext context) {
    final v = _validation();
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 520;
        // Wide: the drawing sits beside the four fields, like a dimensioned sketch; otherwise it comes first.
        final sideBySide = box.maxWidth >= 720;
        const drawingWidth = 300.0;
        final fieldsWidth = sideBySide ? box.maxWidth - drawingWidth - AppSpacing.lg : box.maxWidth;
        final perRow = fieldsWidth < 520 ? (fieldsWidth < 340 ? 1 : 2) : 4;
        final w = perRow == 1 ? fieldsWidth : (fieldsWidth - (perRow - 1) * AppSpacing.md) / perRow;
        Widget sized(Widget child, [double? width]) => SizedBox(width: width ?? w, child: child);
        final oblong = _profile == TubeProfile.oblong;
        final drawing = TubeDiagram(profile: _profile, diameter: _d.text, width: _w.text, height: _h.text, thickness: _t.text, length: _l.text, highlight: _focused);
        final fields = Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            if (oblong) ...[
              sized(_numberField('price-sim-width', 'Largura, lado maior (mm)', _w, v.width, autofocus: true, focusNode: _fw)),
              sized(_numberField('price-sim-height', 'Altura, lado menor (mm)', _h, v.height, focusNode: _fh)),
            ] else
              sized(_numberField('price-sim-diameter', 'Diâmetro externo (mm)', _d, v.diameter, autofocus: widget.diameter == null, focusNode: _fd)),
            sized(_numberField('price-sim-thickness', 'Espessura (mm)', _t, v.thickness, focusNode: _ft)),
            sized(_numberField('price-sim-length', 'Comprimento (mm)', _l, v.length, focusNode: _fl)),
            sized(_numberField('price-sim-quantity', 'Quantidade (peças)', _q, v.quantity, last: !oblong)),
            if (oblong)
              sized(
                TextField(
                  key: const ValueKey('price-sim-markup'),
                  controller: _p,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Acréscimo pela forma (%)', helperText: 'Conformação do oblongo', helperMaxLines: 2, isDense: true),
                  onChanged: (_) {
                    setState(() {});
                    _report(_usablePrice());
                  },
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
              Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: narrow ? 260 : drawingWidth), child: drawing)),
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
            LookupField(
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
            const SizedBox(height: AppSpacing.lg),
            if (_loading) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: LinearProgressIndicator(key: ValueKey('price-sim-loading'))),
            if (_error != null)
              Text(_error!, key: const ValueKey('price-sim-error'), style: TextStyle(color: theme.colorScheme.error))
            else if (_data != null)
              _result(context, _data!)
            else if (!v.ready)
              Text(
                _profile == TubeProfile.oblong ? 'Digite a largura, a altura, a espessura e o comprimento para ver o peso e o preço sugerido.' : 'Digite o diâmetro, a espessura e o comprimento para ver o peso e o preço sugerido.',
                key: const ValueKey('price-sim-hint'),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        );
      },
    );
  }

  Widget _result(BuildContext context, Map<String, dynamic> r) {
    final theme = Theme.of(context);
    final weight = (r['weight'] as Map?)?.cast<String, dynamic>() ?? const {};
    final s = (r['suggestion'] as Map?)?.cast<String, dynamic>() ?? const {};
    final basis = s['basis'] as String? ?? 'None';
    final net = weight['netKg'] as num?, gross = weight['grossKg'] as num?, loss = weight['lossPercent'] as num?;
    final last = (r['customerLast'] as Map?)?.cast<String, dynamic>();
    final rows = [for (final e in (r['similar'] as List? ?? const [])) (e as Map).cast<String, dynamic>()]
      ..sort((a, b) => ((a['distance'] as num?) ?? double.infinity).compareTo((b['distance'] as num?) ?? double.infinity));
    final q = _n(_q);
    final hasPrice = basis != 'None';
    final profile = (r['profile'] as Map?)?.cast<String, dynamic>();
    num? adj(Object? v) => v is num ? _marked(v) : null;
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
              child: Text('faixa ${fmtMoney(adj(s['low']))} – ${fmtMoney(adj(s['high']))}/kg', key: const ValueKey('price-sim-range'), style: theme.textTheme.bodyLarge),
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
        ] else
          Text('Sem vendas parecidas: digite o preço', key: const ValueKey('price-sim-none'), style: theme.textTheme.titleMedium),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(_reason(basis, rows.length, last), key: const ValueKey('price-sim-reason'), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        if (profile != null && profile['shape'] == 'Oblong')
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Preço do tubo redondo de mesmo perímetro (Ø ${fmt(profile['equivalentDiameter'])} mm), porque o histórico só tem tubos redondos.'
              '${_markup > 0 ? ' Já inclui o acréscimo de ${fmt(_markup)}% pela forma.' : ' Some o acréscimo da conformação do oblongo no campo ao lado.'}',
              key: const ValueKey('price-sim-oblong-note'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        if (last != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(_lastText(last), key: const ValueKey('price-sim-last'), style: theme.textTheme.bodyMedium),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text('Vendas parecidas', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.xs),
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
          ],
          rows: rows,
          rowColor: (e) => (_customerName != null && e['customer'] == _customerName) || (_spec != null && e['spec'] == _spec) ? toneColors(context, Tone.info).$1 : null,
        ),
      ],
    );
  }

  String _reason(String basis, int similar, Map<String, dynamic>? last) {
    switch (basis) {
      case 'CustomerRepeat':
        final who = _customerName ?? 'este cliente';
        final date = last == null ? '' : fmtDay(last['date']);
        return 'Mesmo preço cobrado de $who${date.isEmpty ? '' : ' em $date'} para esta medida';
      case 'Neighbours':
        return 'Baseado em $similar ${similar == 1 ? 'venda parecida' : 'vendas parecidas'} dos últimos 24 meses';
      default:
        return 'Sem vendas parecidas: digite o preço';
    }
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
          child: Text('Confiança $label', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
