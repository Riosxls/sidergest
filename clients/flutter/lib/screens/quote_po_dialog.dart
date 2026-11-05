import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../workdays.dart';

// The customer's purchase order step of a quote ("Registrar pedido de compra"): the date helpers shared by both forms of the step and the
// single dialog that attaches the file or text and registers the order in one go.

/// Our delivery date for a line: its lead time in working days counted from the day the customer approved the quote ('' without a lead time).
String poOurDate(Map<String, dynamic> q, Map<String, dynamic> l) {
  final approved = DateTime.tryParse('${q['decidedAt'] ?? ''}')?.toLocal() ?? DateTime.now();
  return l['leadTimeDays'] is! int ? '' : isoDate(addWorkDays(DateTime(approved.year, approved.month, approved.day), l['leadTimeDays'] as int));
}

/// What a line's date field starts with: its saved date, else ours.
String? poDateDefault(Map<String, dynamic> q, Map<String, dynamic> l) {
  final ours = poOurDate(q, l);
  return (l['deliveryDate'] ?? (ours.isEmpty ? null : ours)) as String?;
}

/// The hint under a line's date field.
String poDateHint(Map<String, dynamic> q, Map<String, dynamic> l) {
  final ours = poOurDate(q, l);
  return ours.isEmpty
      ? 'Sem prazo em dias úteis: informe a data'
      : 'Nossa data: ${fmtDay(ours)} (${l['leadTimeDays']} dias úteis após a aprovação). Se o pedido do cliente traz outra data, use a dele.';
}

/// Body of `POST /purchase-order`. Only dates that differ from what the item has now (its saved date, else ours) are sent as the customer's:
/// the customer's date wins, ours stays as working days. [chosen] maps a line id to the ISO date typed for it.
Map<String, dynamic> poBody(Map<String, dynamic> q, {required String? customerPo, required String? note, required Map<Object?, String?> chosen}) {
  final lines = (q['lines'] as List).cast<Map<String, dynamic>>();
  bool changed(Map<String, dynamic> l, String? c) => c != null && c.isNotEmpty && c != (l['deliveryDate'] ?? poOurDate(q, l));
  return {
    'customerPo': customerPo,
    'note': note,
    'deliveryDates': [
      for (final l in lines)
        if (changed(l, chosen[l['id']])) {'lineId': l['id'], 'deliveryDate': chosen[l['id']] == poOurDate(q, l) ? null : chosen[l['id']]},
    ],
  };
}

/// What the dialog leaves behind: the quote as last saved, and whether the purchase order was registered (false = only attached).
class QuotePoOutcome {
  const QuotePoOutcome(this.quote, {required this.registered});

  final Map<String, dynamic> quote;
  final bool registered;
}

/// One dialog for the whole step when the customer's order is not attached yet: choose the file or write the text, type the customer's order
/// number and delivery dates, and register. The file/text is uploaded first, then the order is registered; if the registration fails the
/// attachment stays saved (the dialog says so) and a retry does not upload it again.
class QuotePoDialog extends StatefulWidget {
  const QuotePoDialog({super.key, required this.api, required this.quote, required this.pickFile, this.startWithText = false});

  final ApiClient api;
  final Map<String, dynamic> quote;
  final Future<({String name, Uint8List bytes})?> Function() pickFile;

  /// Opens with the cursor in the text field (the "Escrever texto" entry point).
  final bool startWithText;

  @override
  State<QuotePoDialog> createState() => _QuotePoDialogState();
}

class _QuotePoDialogState extends State<QuotePoDialog> {
  late final _number = TextEditingController(text: '${widget.quote['customerPo'] ?? ''}');
  final _text = TextEditingController();
  final _note = TextEditingController();
  late final List<Map<String, dynamic>> _lines = (widget.quote['lines'] as List).cast<Map<String, dynamic>>();
  late final Map<Object?, TextEditingController> _dates = {
    for (final l in _lines) l['id']: TextEditingController(text: fmtDay(poDateDefault(widget.quote, l))),
  };
  final Map<Object?, String> _dateErrors = {};
  ({String name, Uint8List bytes})? _file;
  String? _error;
  bool _busy = false;

  /// The quote as last saved by an upload of this dialog; what was already uploaded is not sent again on a retry.
  late Map<String, dynamic> _saved = widget.quote;
  String? _uploadedFile;
  String? _uploadedText;

  String get _base => '/api/sales/quotes/${widget.quote['id']}';

  @override
  void dispose() {
    _number.dispose();
    _text.dispose();
    _note.dispose();
    for (final c in _dates.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _choose() async {
    final f = await widget.pickFile();
    if (f != null && mounted) {
      setState(() {
        _file = f;
        _error = null;
      });
    }
  }

  Future<void> _pickDate(Object? id) async {
    final current = DateTime.tryParse(parseDate(_dates[id]!.text) ?? '') ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: current, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null && mounted) setState(() => _dates[id]!.text = fmtDay(isoDate(d)));
  }

  void _close() => Navigator.pop(context, _uploadedFile == null && _uploadedText == null ? null : QuotePoOutcome(_saved, registered: false));

  Future<void> _register() async {
    final text = _text.text.trim();
    final chosen = <Object?, String?>{};
    _dateErrors.clear();
    for (final l in _lines) {
      final s = _dates[l['id']]!.text.trim();
      if (s.isEmpty) continue;
      final iso = parseDate(s);
      if (iso == null) {
        _dateErrors[l['id']] = 'Data inválida (dd/mm/aaaa)';
      } else {
        chosen[l['id']] = iso;
      }
    }
    final attached = _file != null || text.isNotEmpty || _uploadedFile != null || _uploadedText != null;
    if (!attached || _dateErrors.isNotEmpty) {
      setState(() => _error = attached ? null : 'Escolha o arquivo do pedido de compra ou escreva o texto dele.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final f = _file;
      if (f != null && _uploadedFile != '${f.name}:${f.bytes.length}') {
        _saved = await widget.api.upload('$_base/request-file', 'file', f.name, f.bytes) as Map<String, dynamic>;
        _uploadedFile = '${f.name}:${f.bytes.length}';
      }
      if (text.isNotEmpty && _uploadedText != text) {
        _saved = await widget.api.put('$_base/request', {'text': text}) as Map<String, dynamic>;
        _uploadedText = text;
      }
      final r = await widget.api.post('$_base/purchase-order', poBody(widget.quote, customerPo: _blank(_number), note: _blank(_note), chosen: chosen));
      if (mounted) Navigator.pop(context, QuotePoOutcome(r as Map<String, dynamic>, registered: true));
    } catch (e) {
      if (!mounted) return;
      final saved = _uploadedFile != null || _uploadedText != null;
      setState(() {
        _busy = false;
        _error = '${friendlyError(e)}${saved ? '\nO pedido de compra já está anexado; falta registrá-lo. Corrija e tente de novo.' : ''}';
      });
    }
  }

  String? _blank(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text('Pedido de compra de ${widget.quote['reference']}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('O pedido que o cliente enviou: o arquivo (PDF, imagem ou texto) ou o texto escrito aqui.', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('po-pick-file'),
                      onPressed: _busy ? null : _choose,
                      icon: const Icon(Icons.attach_file),
                      label: Text(_file == null ? 'Escolher arquivo' : 'Trocar arquivo'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _file?.name ?? 'Nenhum arquivo escolhido',
                        key: const ValueKey('po-file-name'),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (_file != null)
                      IconButton(tooltip: 'Tirar o arquivo', icon: const Icon(Icons.close, size: 18), onPressed: _busy ? null : () => setState(() => _file = null)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('po-text'),
                  controller: _text,
                  autofocus: widget.startWithText,
                  enabled: !_busy,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Texto do pedido de compra (opcional se há arquivo)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('po-number'),
                  controller: _number,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Nº do pedido de compra do cliente', border: OutlineInputBorder(), isDense: true),
                ),
                for (final l in _lines) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: ValueKey('po-date-${l['id']}'),
                    controller: _dates[l['id']],
                    enabled: !_busy,
                    keyboardType: TextInputType.datetime,
                    decoration: InputDecoration(
                      labelText: 'Item ${l['sequence']} · data de entrega',
                      helperText: poDateHint(widget.quote, l),
                      helperMaxLines: 4,
                      errorText: _dateErrors[l['id']],
                      hintText: 'dd/mm/aaaa',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(tooltip: 'Calendário', icon: const Icon(Icons.calendar_today, size: 18), onPressed: _busy ? null : () => _pickDate(l['id'])),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('po-note'),
                  controller: _note,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Observação', border: OutlineInputBorder(), isDense: true),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(_error!, key: const ValueKey('po-error'), style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(key: const ValueKey('po-cancel'), onPressed: _busy ? null : _close, child: const Text('Cancelar')),
          FilledButton.icon(
            key: const ValueKey('po-register'),
            onPressed: _busy ? null : _register,
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.assignment_turned_in_outlined),
            label: Text(_busy ? 'Registrando…' : 'Registrar'),
          ),
        ],
      ),
    );
  }
}
