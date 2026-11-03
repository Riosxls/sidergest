import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, LogicalKeyboardKey, TextEditingValue, TextInputFormatter;

import '../api.dart';
import '../entities.dart';
import '../workdays.dart';
import 'discard_guard.dart';
import 'drafts.dart';
import 'pipeline.dart' show confirmStep;

Future<Map<String, dynamic>?> showEntityForm(
  BuildContext context, {
  required ApiClient api,
  required String title,
  required List<FieldSpec> fields,
  Map<String, dynamic>? initial,
  required Future<Map<String, dynamic>?> Function(Map<String, dynamic> body) onSubmit,
  Future<void> Function()? onDelete,
  String? deleteMessage,
  bool readOnly = false,
  String submitLabel = 'Salvar',
  String? saveAndNewLabel,
  Object? draftId,
  bool openFirstLookup = false,
  PickHook? onPick,
  HintHook? hintFor,
}) => showDialog<Map<String, dynamic>>(
  context: context,
  barrierDismissible: true, // backdrop click and Esc ask before discarding edits (DiscardGuard)
  builder: (_) => EntityFormDialog(
    api: api,
    title: title,
    fields: fields,
    initial: initial,
    onSubmit: onSubmit,
    onDelete: onDelete,
    deleteMessage: deleteMessage,
    readOnly: readOnly,
    submitLabel: submitLabel,
    saveAndNewLabel: saveAndNewLabel,
    draftId: draftId,
    openFirstLookup: openFirstLookup,
    onPick: onPick,
    hintFor: hintFor,
  ),
);

/// Runs after a lookup field picked a record; returns values for the form's still empty text fields (a price found for the product).
typedef PickHook = Future<Map<String, Object?>?> Function(String key, int? id, Map<String, dynamic>? entity);

/// Helper text of a field that depends on what is typed elsewhere in the form ("Tabela R$ 10,00 · desconto 5%"); null keeps the field's own hint.
typedef HintHook = String? Function(String key, Map<String, dynamic> values);

Future<bool> confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
        ],
      ),
    ) ??
    false;

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is String ? e : friendlyError(e)), backgroundColor: Theme.of(context).colorScheme.error));
}

/// Dialog form built from a list of field specs; validates, shows API field errors and calls [onSubmit] (and [onDelete] when given).
class EntityFormDialog extends StatefulWidget {
  const EntityFormDialog({
    super.key,
    required this.api,
    required this.title,
    required this.fields,
    this.initial,
    required this.onSubmit,
    this.onDelete,
    this.deleteMessage,
    this.readOnly = false,
    this.submitLabel = 'Salvar',
    this.saveAndNewLabel,
    this.draftId,
    this.openFirstLookup = false,
    this.onPick,
    this.hintFor,
  });

  final ApiClient api;
  final String title;
  final List<FieldSpec> fields;
  final Map<String, dynamic>? initial;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic> body) onSubmit;
  final Future<void> Function()? onDelete;

  /// What the delete confirmation says is lost; its title names the record.
  final String? deleteMessage;
  final bool readOnly;

  /// Text of the main button ("Adicionar item" where nothing is stored until a page is saved).
  final String submitLabel;

  /// When set, a second button saves and returns `_again: true` so the caller can open the form for the next record.
  final String? saveAndNewLabel;

  /// Tells apart the drafts of forms that share a title and have no id (the lines of a quote).
  final Object? draftId;

  /// Opens the picker of the first field when it is a lookup, so a new record starts by choosing it.
  final bool openFirstLookup;
  final PickHook? onPick;
  final HintHook? hintFor;

  @override
  State<EntityFormDialog> createState() => _EntityFormDialogState();
}

class _EntityFormDialogState extends State<EntityFormDialog> {
  final _text = <String, TextEditingController>{};
  final _values = <String, Object?>{};
  final _lookupKeys = <String, int>{};
  final _labels = <String, String>{};
  Map<String, List<String>> _serverErrors = {};
  final _clientErrors = <String, String>{};
  bool _more = false;
  String? _message;
  bool _busy = false;
  late final String _initial;
  bool _recovered = false;
  bool _lockSaved = false;

  String get _draftKey => 'form:${widget.title}:${widget.initial?['id'] ?? widget.draftId ?? 'new'}';

  /// Keys of the fields on screen, in order; Enter in the last one saves and in the others moves on.
  List<String> _shown = const [];

  /// Called when the session ends under an open form: keeps what was typed so it can be offered again.
  void _saveDraft() {
    if (widget.readOnly || _busy || _signature() == _initial) return;
    _lockSaved = true;
    unawaited(
      DraftStore.save(_draftKey, {
        'text': {for (final e in _text.entries) e.key: e.value.text},
        'values': {for (final e in _values.entries) e.key: e.value},
        'labels': Map<String, String>.of(_labels),
      }),
    );
  }

  Future<void> _restoreDraft() async {
    if (widget.readOnly) return;
    final d = await DraftStore.load(_draftKey);
    if (d == null || !mounted) return;
    setState(() {
      final text = d['text'];
      if (text is Map) {
        for (final e in text.entries) {
          _text['${e.key}']?.text = '${e.value}';
        }
      }
      final values = d['values'];
      if (values is Map) {
        for (final e in values.entries) {
          if (_values.containsKey(e.key)) _values['${e.key}'] = e.value;
        }
      }
      final labels = d['labels'];
      if (labels is Map) _labels.addAll({for (final e in labels.entries) '${e.key}': '${e.value}'});
      for (final k in _values.keys) {
        _lookupKeys[k] = (_lookupKeys[k] ?? 0) + 1;
      }
      _recovered = true;
    });
  }

  String _signature() => jsonEncode([for (final f in widget.fields) _text[f.key]?.text ?? _values[f.key]]);

  bool _isText(FieldSpec f) =>
      f.type == FieldType.text || f.type == FieldType.integer || f.type == FieldType.decimal || f.type == FieldType.date || f.type == FieldType.time;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final v = widget.initial?[f.key] ?? (widget.initial == null ? f.defaultValue : null);
      if (_isText(f)) {
        _text[f.key] = TextEditingController(
          text: f.type == FieldType.text
              ? (v as String? ?? '')
              : (f.type == FieldType.date
                    ? fmtDay(v)
                    : (f.type == FieldType.time ? fmtTime(v) : (f.money && v is num ? v.toStringAsFixed(2).replaceAll('.', ',') : fmt(v)))),
        );
      } else {
        _values[f.key] = f.type == FieldType.boolean ? (v as bool? ?? false) : v;
      }
    }
    final labels = widget.initial?['_labels'];
    if (labels is Map) _labels.addAll(labels.cast<String, String>());
    _initial = _signature();
    DraftRegistry.register(_saveDraft);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    DraftRegistry.unregister(_saveDraft);
    if (!_lockSaved && !widget.readOnly) unawaited(DraftStore.clear(_draftKey));
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? _body() {
    _clientErrors.clear();
    final body = <String, dynamic>{};
    for (final f in widget.fields) {
      Object? v;
      if (_isText(f)) {
        final s = _text[f.key]!.text.trim();
        if (s.isEmpty) {
          v = null;
        } else if (f.type == FieldType.integer) {
          v = int.tryParse(s);
          if (v == null) _clientErrors[f.key] = 'Número inteiro';
        } else if (f.type == FieldType.decimal) {
          v = parseDecimal(s);
          if (v == null) _clientErrors[f.key] = 'Número inválido';
        } else if (f.type == FieldType.date) {
          v = parseDate(s);
          if (v == null) _clientErrors[f.key] = 'Data inválida (dd/mm/aaaa)';
        } else if (f.type == FieldType.time) {
          v = parseTime(s);
          if (v == null) _clientErrors[f.key] = 'Hora inválida (hh:mm)';
        } else {
          v = s;
        }
      } else {
        v = _values[f.key];
      }
      if (f.required && v == null) _clientErrors[f.key] = 'Obrigatório';
      if (v is num && !_clientErrors.containsKey(f.key)) {
        if (f.positive && v <= 0) {
          _clientErrors[f.key] = 'Deve ser maior que zero';
        } else if (f.min != null && v < f.min!) {
          _clientErrors[f.key] = f.min == 0 ? 'Não pode ser negativo' : 'Mínimo ${fmt(f.min)}';
        } else if (f.max != null && v > f.max!) {
          _clientErrors[f.key] = 'Máximo ${fmt(f.max)}';
        }
      }
      body[f.key] = v;
    }
    return _clientErrors.isEmpty ? body : null;
  }

  Future<void> _save({bool again = false}) async {
    final body = _body();
    setState(() {
      _serverErrors = {};
      _message = body == null ? 'Verifique os campos destacados' : null;
    });
    if (body == null) return;
    setState(() => _busy = true);
    try {
      final result = await widget.onSubmit(body);
      if (mounted) Navigator.pop(context, {...(result ?? {...body, '_labels': Map<String, String>.of(_labels)}), if (again) '_again': true});
    } on ApiException catch (e) {
      setState(() {
        _serverErrors = e.fieldErrors.map((k, v) => MapEntry(k.isEmpty ? k : k[0].toLowerCase() + k.substring(1), v));
        _message = e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmStep(
      context,
      title: 'Excluir ${widget.title}?',
      message: widget.deleteMessage ?? 'O registro é apagado definitivamente. Não dá para desfazer.',
      confirmLabel: 'Excluir',
      icon: Icons.delete_outline,
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context, <String, dynamic>{'_deleted': true});
    } on ApiException catch (e) {
      setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate(FieldSpec f) async {
    final current = DateTime.tryParse(parseDate(_text[f.key]!.text) ?? '') ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: current, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) {
      setState(() {
        _text[f.key]!.text = fmtDay(isoDate(d));
        _syncLinked(f);
      });
    }
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  void _syncLinked(FieldSpec f) {
    final days = f.daysFor, date = f.dateFor;
    if (days != null) {
      final n = int.tryParse(_text[f.key]!.text.trim());
      if (n != null && _text.containsKey(days)) _text[days]!.text = fmtDay(isoDate(addWorkDays(_today, n)));
    } else if (date != null) {
      final d = DateTime.tryParse(parseDate(_text[f.key]!.text) ?? '');
      if (d != null && _text.containsKey(date)) _text[date]!.text = '${workDaysBetween(_today, d)}';
    }
  }

  String? _errorFor(String key) => _clientErrors[key] ?? _serverErrors[key]?.join('; ');

  /// What is typed so far, as numbers and ids where the field is one; read by [FieldSpec]-independent hints of the caller.
  Map<String, dynamic> _currentValues() {
    final out = <String, dynamic>{};
    for (final f in widget.fields) {
      final t = _text[f.key]?.text.trim();
      if (t != null) {
        out[f.key] = t.isEmpty ? null : (f.type == FieldType.decimal ? parseDecimal(t) : (f.type == FieldType.integer ? int.tryParse(t) : t));
      } else {
        out[f.key] = _values[f.key];
      }
    }
    return out;
  }

  bool _isLastShown(String key) => _shown.isEmpty || _shown.last == key;

  void _onEnter(FieldSpec f) {
    if (widget.readOnly) return;
    if (_isLastShown(f.key)) {
      unawaited(_save());
    } else {
      FocusScope.of(context).nextFocus();
    }
  }

  Future<void> _picked(FieldSpec f, int? id, Map<String, dynamic>? entity) async {
    final hook = widget.onPick;
    if (hook == null) return;
    final fill = await hook(f.key, id, entity);
    if (fill == null || !mounted) return;
    setState(() {
      fill.forEach((k, v) {
        final c = _text[k];
        if (c != null && c.text.trim().isEmpty && v != null) c.text = v is String ? v : fmt(v);
      });
    });
  }

  void _applyFill(LookupSpec spec, Map<String, dynamic>? entity) {
    if (entity == null) return;
    spec.fill.forEach((target, source) {
      final value = entity[source];
      if (value == null) return;
      if (_text.containsKey(target)) {
        _text[target]!.text = value is String ? value : fmt(value);
      } else if (_values.containsKey(target)) {
        _values[target] = value;
        _lookupKeys[target] = (_lookupKeys[target] ?? 0) + 1;
      }
    });
  }

  Widget _field(FieldSpec f) {
    final error = _errorFor(f.key);
    final label = f.required ? '${f.label} *' : f.label;
    switch (f.type) {
      case FieldType.text:
      case FieldType.integer:
      case FieldType.decimal:
      case FieldType.date:
      case FieldType.time:
        return TextField(
          key: ValueKey('field-${f.key}'),
          controller: _text[f.key],
          autofocus: !widget.readOnly && widget.initial == null && widget.fields.first.key == f.key && !widget.openFirstLookup,
          textInputAction: _isLastShown(f.key) ? TextInputAction.done : TextInputAction.next,
          readOnly: widget.readOnly || (f.lockWhenEditing && widget.initial?['id'] != null),
          obscureText: f.obscure,
          inputFormatters: f.uppercase
              ? [_UpperCase()]
              : (f.digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null),
          textCapitalization: f.uppercase ? TextCapitalization.characters : TextCapitalization.none,
          keyboardType: f.type == FieldType.text
              ? TextInputType.text
              : (f.type == FieldType.date || f.type == FieldType.time ? TextInputType.datetime : const TextInputType.numberWithOptions(decimal: true)),
          decoration: InputDecoration(
            labelText: label,
            helperText: widget.hintFor?.call(f.key, _currentValues()) ?? f.hint,
            helperMaxLines: 4,
            errorText: error,
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: f.type == FieldType.date ? 'dd/mm/aaaa' : (f.type == FieldType.time ? 'hh:mm' : null),
            suffixIcon: f.type == FieldType.date && !widget.readOnly
                ? IconButton(tooltip: 'Calendário', icon: const Icon(Icons.calendar_today, size: 18), onPressed: () => _pickDate(f))
                : null,
          ),
          onSubmitted: (_) => _onEnter(f),
          onChanged: (_) {
            if (widget.hintFor != null) setState(() {});
            if (f.daysFor != null || f.dateFor != null) {
              _syncLinked(f);
              _serverErrors.remove(f.daysFor ?? f.dateFor);
              _clientErrors.remove(f.daysFor ?? f.dateFor);
              setState(() {});
            }
            if (_serverErrors.containsKey(f.key) || _clientErrors.containsKey(f.key)) {
              setState(() {
                _serverErrors.remove(f.key);
                _clientErrors.remove(f.key);
              });
            }
          },
        );
      case FieldType.boolean:
        return InputDecorator(
          decoration: InputDecoration(errorText: error, border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
          child: CheckboxListTile(
            key: ValueKey('field-${f.key}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(f.label),
            value: _values[f.key] as bool,
            onChanged: widget.readOnly ? null : (v) => setState(() => _values[f.key] = v ?? false),
          ),
        );
      case FieldType.choice:
        return DropdownButtonFormField<String?>(
          key: ValueKey('field-${f.key}'),
          initialValue: _values[f.key] as String?,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            helperText: f.hint,
            helperMaxLines: 4,
            errorText: error,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            if (!f.required) const DropdownMenuItem<String?>(value: null, child: Text('—')),
            for (final e in f.choices.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
          ],
          onChanged: widget.readOnly ? null : (v) => setState(() => _values[f.key] = v),
        );
      case FieldType.lookup:
        return LookupField(
          key: ValueKey('field-${f.key}-${_lookupKeys[f.key] ?? 0}'),
          api: widget.api,
          spec: f.lookup!,
          label: label,
          hint: widget.hintFor?.call(f.key, _currentValues()) ?? f.hint,
          error: error,
          value: _values[f.key] as int?,
          enabled: !widget.readOnly,
          autoOpen: widget.openFirstLookup && !widget.readOnly && widget.fields.first.key == f.key && _values[f.key] == null,
          onChanged: (id, entity) {
            setState(() {
              _values[f.key] = id;
              if (entity == null) {
                _labels.remove(f.key);
              } else {
                _labels[f.key] = LookupSpec.display(entity);
              }
              _applyFill(f.lookup!, entity);
            });
            unawaited(_picked(f, id, entity));
          },
          initialDisplay: _labels[f.key],
        );
    }
  }

  /// A field that already holds something (typed, a default, an error) is never folded away.
  bool _hasValue(FieldSpec f) {
    final t = _text[f.key]?.text.trim() ?? '';
    final v = _values[f.key];
    return t.isNotEmpty || (v != null && '$v'.isNotEmpty && v != false) || _clientErrors.containsKey(f.key) || _serverErrors.containsKey(f.key);
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final form = LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth >= 560 ? (c.maxWidth - 12) / 2 : c.maxWidth;
        // Fields marked advanced stay folded until asked for, unless they already hold a value or an error.
        bool folded(FieldSpec f) => f.advanced && !_more && !_hasValue(f);
        final extra = [for (final f in widget.fields) if (folded(f)) f];
        _shown = [for (final f in widget.fields) if (!folded(f)) f.key];
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [
              for (final f in widget.fields)
                if (!folded(f)) SizedBox(width: w, child: _field(f)),
              if (extra.isNotEmpty)
                TextButton.icon(
                  key: const ValueKey('form-more'),
                  onPressed: () => setState(() => _more = true),
                  icon: const Icon(Icons.expand_more),
                  label: Text('Mais campos (${extra.length})'),
                ),
            ],
          ),
        );
      },
    );
    final actions = [
      if (widget.onDelete != null && !widget.readOnly)
        TextButton.icon(
          onPressed: _busy ? null : _delete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Excluir'),
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
        ),
      const Spacer(),
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(widget.readOnly ? 'Fechar' : 'Cancelar')),
      if (!widget.readOnly) ...[
        if (widget.saveAndNewLabel != null) ...[
          const SizedBox(width: 8),
          OutlinedButton(key: const ValueKey('form-save-new'), onPressed: _busy ? null : () => _save(again: true), child: Text(widget.saveAndNewLabel!)),
        ],
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.submitLabel),
        ),
      ],
    ];
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (_recovered)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.restore, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Rascunho recuperado: nada foi enviado ainda.', style: Theme.of(context).textTheme.bodySmall)),
              ],
            ),
          ),
        Flexible(child: form),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 12),
        Row(children: actions),
      ],
    );
    final dialog = narrow
        ? Dialog.fullscreen(
            child: SafeArea(
              child: Padding(padding: const EdgeInsets.all(16), child: content),
            ),
          )
        : Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
              child: Padding(padding: const EdgeInsets.all(20), child: content),
            ),
          );
    if (widget.readOnly) return dialog;
    // Ctrl+Enter saves from any field.
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _busy ? null : unawaited(_save())},
      child: DiscardGuard(isDirty: () => _signature() != _initial, child: dialog),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) => value.copyWith(text: value.text.toUpperCase());
}

/// Form field that picks a related record through a [LookupPicker] and shows its display name.
class LookupField extends StatefulWidget {
  const LookupField({
    super.key,
    required this.api,
    required this.spec,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.error,
    this.enabled = true,
    this.initialDisplay,
    this.onCustom,
    this.autoOpen = false,
  });

  /// Opens the picker as soon as the field appears (a new line starts by choosing its product).
  final bool autoOpen;

  final ApiClient api;
  final String? initialDisplay;
  final LookupSpec spec;
  final String label;
  final String? hint;
  final String? error;
  final int? value;
  final bool enabled;

  /// When set, the picker offers a free-text prazo that is kept only by the caller (not saved as a record).
  final ValueChanged<String>? onCustom;
  final void Function(int? id, Map<String, dynamic>? entity) onChanged;

  @override
  State<LookupField> createState() => _LookupFieldState();
}

class _LookupFieldState extends State<LookupField> {
  String? _display;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.autoOpen && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_pick());
      });
    }
  }

  Future<void> _load() async {
    if (widget.value == null) return;
    if (widget.initialDisplay != null) {
      _display = widget.initialDisplay;
      return;
    }
    if (!widget.spec.fetchById) {
      _display = '#${widget.value}';
      return;
    }
    try {
      final e = await widget.api.get('${widget.spec.path}/${widget.value}') as Map<String, dynamic>;
      if (mounted) setState(() => _display = LookupSpec.display(e));
    } catch (_) {
      if (mounted) setState(() => _display = '#${widget.value}');
    }
  }

  Future<void> _pick() async {
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => LookupPicker(
        api: widget.api,
        path: widget.spec.path,
        title: widget.label,
        query: widget.spec.query,
        selectedId: widget.value,
        create: widget.onCustom == null ? null : askCustomPrazo,
        createLabel: 'Prazo personalizado',
      ),
    );
    if (picked == null) return;
    final custom = picked['_custom'];
    if (custom is String) return widget.onCustom?.call(custom);
    setState(() => _display = LookupSpec.display(picked));
    widget.onChanged(picked['id'] as int, picked);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.enabled,
      child: InkWell(
        onTap: widget.enabled ? _pick : null,
        child: InputDecorator(
        isEmpty: widget.value == null,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.hint,
          helperMaxLines: 4,
          errorText: widget.error,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: widget.value != null && widget.enabled
              ? IconButton(
                  tooltip: 'Limpar',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() => _display = null);
                    widget.onChanged(null, null);
                  },
                )
              : const Icon(Icons.search),
        ),
        child: Text(widget.value == null ? '' : (_display ?? '…'), overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// Searchable dialog that lists records of [path] and returns the chosen one; [create] adds a "new" flow.
class LookupPicker extends StatefulWidget {
  const LookupPicker({
    super.key,
    required this.api,
    required this.path,
    required this.title,
    this.query = const {},
    this.selectedId,
    this.create,
    this.createLabel = 'Novo',
  });

  final ApiClient api;
  final Map<String, dynamic> query;
  final String path;
  final String title;
  final int? selectedId;

  /// Optional "create new" flow; the created record is returned as the picked item.
  final Future<Map<String, dynamic>?> Function(BuildContext context)? create;
  final String createLabel;

  @override
  State<LookupPicker> createState() => _LookupPickerState();
}

class _LookupPickerState extends State<LookupPicker> {
  /// The last records picked from each list, newest first, offered on top when nothing is typed.
  static final _recent = <String, List<Map<String, dynamic>>>{};

  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = true;
  bool _typing = false;
  int _request = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Waits for a pause in typing before asking the server.
  void _onType(String q) {
    _typing = q.trim().isNotEmpty;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(q));
  }

  void _pickItem(Map<String, dynamic> item) {
    if (item['id'] != null) {
      final list = _recent.putIfAbsent(widget.path, () => []);
      list.removeWhere((e) => e['id'] == item['id']);
      list.insert(0, item);
      if (list.length > 5) list.removeRange(5, list.length);
    }
    Navigator.pop(context, item);
  }

  Future<void> _search(String q) async {
    final r = ++_request;
    setState(() => _loading = true);
    try {
      final page = await widget.api.list(widget.path, q: q, take: 100, query: widget.query);
      if (r != _request || !mounted) return;
      setState(() {
        _items = page.items;
        _error = null;
      });
    } catch (e) {
      if (r == _request && mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (r == _request && mounted) setState(() => _loading = false);
    }
  }

  /// The list shown: the recently picked records above the rest while nothing is typed, otherwise the search result. Strings are headings.
  List<Object> _rows() {
    final recent = _typing ? const <Map<String, dynamic>>[] : (_recent[widget.path] ?? const <Map<String, dynamic>>[]);
    if (recent.isEmpty) return [..._items];
    final recentIds = {for (final r in recent) r['id']};
    return ['Usados recentemente', ...recent, 'Todos', ..._items.where((e) => !recentIds.contains(e['id']))];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = widget.title.replaceAll(' *', '');
    final rows = _rows();
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      title: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 520,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Buscar ${title.toLowerCase()}',
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              ),
              onChanged: _onType,
              // Enter takes the first result.
              onSubmitted: (_) {
                final first = _rows().whereType<Map<String, dynamic>>().firstOrNull;
                if (first != null) _pickItem(first);
              },
            ),
            const SizedBox(height: 8),
            SizedBox(height: 3, child: _loading ? const LinearProgressIndicator() : null),
            if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
            Expanded(
              child: !_loading && _error == null && _items.isEmpty
                  ? Center(
                      child: Text('Nenhum resultado', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (_, i) {
                        final row = rows[i];
                        if (row is String) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
                            child: Text(row, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                          );
                        }
                        final item = row as Map<String, dynamic>;
                        final selected = widget.selectedId != null && item['id'] == widget.selectedId;
                        return ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          selected: selected,
                          selectedTileColor: cs.secondaryContainer,
                          selectedColor: cs.onSecondaryContainer,
                          hoverColor: cs.onSurface.withValues(alpha: 0.06),
                          title: Text(LookupSpec.display(item), style: theme.textTheme.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: selected ? const Icon(Icons.check) : null,
                          onTap: () => _pickItem(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (widget.create != null)
          TextButton.icon(
            key: const ValueKey('picker-create'),
            icon: const Icon(Icons.add),
            label: Text(widget.createLabel),
            onPressed: () async {
              final r = await widget.create!(context);
              if (r != null && context.mounted) Navigator.pop(context, r);
            },
          )
        else
          const SizedBox.shrink(),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      ],
    );
  }
}

/// Asks for a free-text prazo that belongs to a single quote; returned as `{'_custom': text}`.
Future<Map<String, dynamic>?> askCustomPrazo(BuildContext context) async {
  final text = await showDialog<String>(context: context, builder: (_) => const _CustomPrazoDialog());
  return text == null ? null : {'_custom': text};
}

class _CustomPrazoDialog extends StatefulWidget {
  const _CustomPrazoDialog();

  @override
  State<_CustomPrazoDialog> createState() => _CustomPrazoDialogState();
}

class _CustomPrazoDialogState extends State<_CustomPrazoDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _ok() {
    final t = _text.text.trim();
    if (t.isEmpty) return setState(() => _error = 'Informe o prazo');
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Prazo personalizado'),
    content: SizedBox(
      width: 380,
      child: TextField(
        key: const ValueKey('prazo-custom'),
        controller: _text,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Prazo *',
          hintText: 'ex.: 45 dias, 20% entrada + 30/60',
          helperText: 'Vale só para este orçamento; não entra na lista de prazos.',
          helperMaxLines: 3,
          errorText: _error,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: (_) => _ok(),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: _ok, child: const Text('Usar neste orçamento')),
    ],
  );
}
