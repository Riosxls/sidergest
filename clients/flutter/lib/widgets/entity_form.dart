import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';

Future<Map<String, dynamic>?> showEntityForm(
  BuildContext context, {
  required ApiClient api,
  required String title,
  required List<FieldSpec> fields,
  Map<String, dynamic>? initial,
  required Future<Map<String, dynamic>?> Function(Map<String, dynamic> body) onSubmit,
  Future<void> Function()? onDelete,
  bool readOnly = false,
}) => showDialog<Map<String, dynamic>>(
  context: context,
  barrierDismissible: false,
  builder: (_) => EntityFormDialog(api: api, title: title, fields: fields, initial: initial, onSubmit: onSubmit, onDelete: onDelete, readOnly: readOnly),
);

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
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Theme.of(context).colorScheme.error));
}

class EntityFormDialog extends StatefulWidget {
  const EntityFormDialog({
    super.key,
    required this.api,
    required this.title,
    required this.fields,
    this.initial,
    required this.onSubmit,
    this.onDelete,
    this.readOnly = false,
  });

  final ApiClient api;
  final String title;
  final List<FieldSpec> fields;
  final Map<String, dynamic>? initial;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic> body) onSubmit;
  final Future<void> Function()? onDelete;
  final bool readOnly;

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
  String? _message;
  bool _busy = false;

  bool _isText(FieldSpec f) =>
      f.type == FieldType.text || f.type == FieldType.integer || f.type == FieldType.decimal || f.type == FieldType.date || f.type == FieldType.time;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final v = widget.initial?[f.key] ?? (widget.initial == null ? f.defaultValue : null);
      if (_isText(f)) {
        _text[f.key] = TextEditingController(
          text: f.type == FieldType.text ? (v as String? ?? '') : (f.type == FieldType.date ? fmtDay(v) : (f.type == FieldType.time ? fmtTime(v) : fmt(v))),
        );
      } else {
        _values[f.key] = f.type == FieldType.boolean ? (v as bool? ?? false) : v;
      }
    }
    final labels = widget.initial?['_labels'];
    if (labels is Map) _labels.addAll(labels.cast<String, String>());
  }

  @override
  void dispose() {
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
      body[f.key] = v;
    }
    return _clientErrors.isEmpty ? body : null;
  }

  Future<void> _save() async {
    final body = _body();
    setState(() {
      _serverErrors = {};
      _message = body == null ? 'Verifique os campos destacados' : null;
    });
    if (body == null) return;
    setState(() => _busy = true);
    try {
      final result = await widget.onSubmit(body);
      if (mounted) Navigator.pop(context, result ?? {...body, '_labels': Map<String, String>.of(_labels)});
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
    if (!await confirm(context, 'Excluir este registro?')) return;
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
      if (n != null && _text.containsKey(days)) _text[days]!.text = fmtDay(isoDate(_today.add(Duration(days: n))));
    } else if (date != null) {
      final d = DateTime.tryParse(parseDate(_text[f.key]!.text) ?? '');
      if (d != null && _text.containsKey(date)) _text[date]!.text = '${DateTime(d.year, d.month, d.day).difference(_today).inDays}';
    }
  }

  String? _errorFor(String key) => _clientErrors[key] ?? _serverErrors[key]?.join('; ');

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
          readOnly: widget.readOnly,
          keyboardType: f.type == FieldType.text
              ? TextInputType.text
              : (f.type == FieldType.date || f.type == FieldType.time ? TextInputType.datetime : const TextInputType.numberWithOptions(decimal: true)),
          decoration: InputDecoration(
            labelText: label,
            helperText: f.hint,
            errorText: error,
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: f.type == FieldType.date ? 'dd/mm/aaaa' : (f.type == FieldType.time ? 'hh:mm' : null),
            suffixIcon: f.type == FieldType.date && !widget.readOnly
                ? IconButton(tooltip: 'Calendário', icon: const Icon(Icons.calendar_today, size: 18), onPressed: () => _pickDate(f))
                : null,
          ),
          onSubmitted: (_) => widget.readOnly ? null : _save(),
          onChanged: (_) {
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
          decoration: InputDecoration(labelText: label, helperText: f.hint, errorText: error, border: const OutlineInputBorder(), isDense: true),
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
          hint: f.hint,
          error: error,
          value: _values[f.key] as int?,
          enabled: !widget.readOnly,
          onChanged: (id, entity) => setState(() {
            _values[f.key] = id;
            if (entity == null) {
              _labels.remove(f.key);
            } else {
              _labels[f.key] = LookupSpec.display(entity);
            }
            _applyFill(f.lookup!, entity);
          }),
          initialDisplay: _labels[f.key],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final form = LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth >= 560 ? (c.maxWidth - 12) / 2 : c.maxWidth;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [for (final f in widget.fields) SizedBox(width: w, child: _field(f))],
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
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salvar'),
        ),
      ],
    ];
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
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
    if (narrow) {
      return Dialog.fullscreen(
        child: SafeArea(
          child: Padding(padding: const EdgeInsets.all(16), child: content),
        ),
      );
    }
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Padding(padding: const EdgeInsets.all(20), child: content),
      ),
    );
  }
}

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
  });

  final ApiClient api;
  final String? initialDisplay;
  final LookupSpec spec;
  final String label;
  final String? hint;
  final String? error;
  final int? value;
  final bool enabled;
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
      builder: (_) => LookupPicker(api: widget.api, path: widget.spec.path, title: widget.label, query: widget.spec.query, selectedId: widget.value, create: widget.spec.path == '/api/sales/payment-terms' ? (ctx) => _createPrazo(ctx, widget.api) : null, createLabel: 'Prazo personalizado'),
    );
    if (picked == null) return;
    setState(() => _display = LookupSpec.display(picked));
    widget.onChanged(picked['id'] as int, picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.enabled ? _pick : null,
      child: InputDecorator(
        isEmpty: widget.value == null,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.hint,
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
    );
  }
}

class LookupPicker extends StatefulWidget {
  const LookupPicker({super.key, required this.api, required this.path, required this.title, this.query = const {}, this.selectedId, this.create, this.createLabel = 'Novo'});

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
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _search('');
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
      if (r == _request && mounted) setState(() => _error = '$e');
    } finally {
      if (r == _request && mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = widget.title.replaceAll(' *', '');
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
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            SizedBox(height: 3, child: _loading ? const LinearProgressIndicator() : null),
            if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
            Expanded(
              child: !_loading && _error == null && _items.isEmpty
                  ? Center(child: Text('Nenhum resultado', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)))
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (_, i) {
                        final item = _items[i];
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
                          onTap: () => Navigator.pop(context, item),
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

/// Asks for a custom prazo, saves it as a new payment term and returns it.
Future<Map<String, dynamic>?> _createPrazo(BuildContext context, ApiClient api) {
  final days = TextEditingController();
  final name = TextEditingController();
  String? error;
  var busy = false;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> save() async {
          final parts = days.text.split(RegExp(r'[/\s,]+')).where((p) => p.isNotEmpty).toList();
          if (parts.isEmpty || parts.any((p) => int.tryParse(p) == null)) {
            return setState(() => error = 'Informe os dias, ex.: 45 ou 30/45/60');
          }
          final label = name.text.trim().isEmpty ? '${parts.join(' / ')} dias' : name.text.trim();
          setState(() {
            busy = true;
            error = null;
          });
          try {
            final r = await api.post('/api/sales/payment-terms', {
              'code': 'P${DateTime.now().millisecondsSinceEpoch % 100000000}',
              'name': label,
              'days': parts.join('/'),
              'active': true,
            });
            if (ctx.mounted) Navigator.pop(ctx, r as Map<String, dynamic>);
          } on ApiException catch (e) {
            if (ctx.mounted) {
              setState(() {
                busy = false;
                error = e.message;
              });
            }
          }
        }

        return AlertDialog(
          title: const Text('Prazo personalizado'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('prazo-days'),
                  controller: days,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Dias *', hintText: 'ex.: 45 ou 30/45/60', border: OutlineInputBorder(), isDense: true),
                  onSubmitted: (_) => save(),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('prazo-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nome', hintText: 'Vazio = automático, ex.: 45 dias', border: OutlineInputBorder(), isDense: true),
                  onSubmitted: (_) => save(),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: busy ? null : save, child: const Text('Criar e usar')),
          ],
        );
      },
    ),
  );
}
