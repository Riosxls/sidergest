import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../theme_tokens.dart';
import 'entity_form.dart';
import 'record_list.dart';

export '../api.dart' show describeError, fieldLabel, friendlyError;

/// Screens (by their build context) that have an action in flight. A second tap or click on the same screen is ignored until the first answers,
/// so a double-click cannot confirm, ship or cancel twice.
final _running = <int>{};

Future<T?> runAction<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  final key = identityHashCode(context);
  if (!_running.add(key)) return null;
  try {
    final r = await action();
    if (success != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    return r;
  } catch (e) {
    if (context.mounted) showError(context, friendlyError(e));
    return null;
  } finally {
    _running.remove(key);
  }
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  bool required = false,
  String initial = '',
  String confirmLabel = 'Confirmar',
  bool danger = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PromptDialog(title: title, label: label, required: required, initial: initial, confirmLabel: confirmLabel, danger: danger),
);

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.label, required this.required, required this.initial, required this.confirmLabel, this.danger = false});

  final String title;
  final String label;
  final bool required;
  final String initial;
  final String confirmLabel;
  final bool danger;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _c = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    if (widget.required && _c.text.trim().isEmpty) return setState(() => _error = 'Obrigatório');
    Navigator.pop(context, _c.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: TextField(
        key: const ValueKey('prompt-text'),
        controller: _c,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(labelText: widget.required ? '${widget.label} *' : widget.label, errorText: _error, border: const OutlineInputBorder()),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
      FilledButton(style: widget.danger ? dangerButtonStyle(context) : null, onPressed: _ok, child: Text(widget.confirmLabel)),
    ],
  );
}

Future<Map<String, dynamic>?> submitForm(
  BuildContext context, {
  required ApiClient api,
  required String title,
  required List<FieldSpec> fields,
  Map<String, dynamic>? initial,
  required Future<dynamic> Function(Map<String, dynamic> body) submit,
}) => showEntityForm(
  context,
  api: api,
  title: title,
  fields: fields,
  initial: initial,
  onSubmit: (body) async {
    final r = await submit(body);
    return r is Map<String, dynamic> ? r : body;
  },
);

/// Lets the screen around a [LinesEditor] open its "add" form (a keyboard shortcut).
class LinesEditorController {
  VoidCallback? _add;

  /// Opens the form of a new line; does nothing while adding is not allowed.
  void add() => _add?.call();
}

/// Editable table of child lines (items of an order, operations...) with add, edit and remove through an [EntityFormDialog].
class LinesEditor extends StatelessWidget {
  const LinesEditor({
    super.key,
    this.controller,
    required this.api,
    required this.title,
    required this.fields,
    required this.columns,
    required this.lines,
    required this.onChanged,
    this.enabled = true,
    this.newTitle = 'Nova linha',
    this.editTitle,
    this.addLabel = 'Adicionar linha',
    this.addEnabled = true,
    this.disabledHint,
    this.submitLabel = 'Salvar',
    this.addAnotherLabel,
    this.carryKeys = const [],
    this.duplicateKey,
    this.staleOnChange = const {},
    this.onPick,
    this.hintFor,
    this.rowColor,
  });

  final LinesEditorController? controller;
  final ApiClient api;
  final String title;
  final List<FieldSpec> fields;
  final List<ColumnSpec> columns;
  final List<Map<String, dynamic>> lines;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;
  final String newTitle;
  final String? editTitle;
  final String addLabel;
  final bool addEnabled;
  final String? disabledHint;

  /// Text of the form's main button.
  final String submitLabel;

  /// When set, the new-line form has a second button that adds the line and opens the form for the next one.
  final String? addAnotherLabel;

  /// Values the next line starts with after "add and new" (the lead time typed on the last one).
  final List<String> carryKeys;

  /// Field that should be unique among the lines (the product); a repeat is allowed but pointed out.
  final String? duplicateKey;

  /// Values of a line that belong to one of its fields and must go when that field changes: `{'productId': ['ipiPercent', 'icmsPercent', 'description']}`.
  final Map<String, List<String>> staleOnChange;
  final PickHook? onPick;
  final HintHook? hintFor;
  final Color? Function(Map<String, dynamic> line)? rowColor;

  /// [current] is the list the screen has now when this runs again after "add and new": this widget still holds the list it was built with.
  Future<void> _edit(BuildContext context, [int? index, Map<String, dynamic>? seed, List<Map<String, dynamic>>? current]) async {
    final lines = current ?? this.lines;
    final adding = index == null;
    final r = await showEntityForm(
      context,
      api: api,
      title: adding ? newTitle : (editTitle ?? 'Linha ${index + 1}'),
      fields: fields,
      initial: adding ? seed : lines[index],
      draftId: adding ? 'new' : 'line-${index + 1}',
      submitLabel: adding ? submitLabel : (submitLabel == 'Salvar' ? 'Salvar' : 'Concluir'),
      saveAndNewLabel: adding ? addAnotherLabel : null,
      openFirstLookup: adding && addAnotherLabel != null && fields.isNotEmpty && fields.first.type == FieldType.lookup,
      onPick: onPick,
      hintFor: hintFor,
      onSubmit: (_) async => null,
    );
    if (r == null) return;
    final again = r.remove('_again') == true;
    final next = [...lines];
    if (adding) {
      next.add(r);
    } else {
      final base = {...lines[index]};
      final form = {...r};
      // A changed field takes its dependent values along (the taxes and description of the old product).
      staleOnChange.forEach((key, stale) {
        if ('${base[key]}' == '${form[key]}') return;
        for (final k in stale) {
          base.remove(k);
          if ('${form[k]}' == '${lines[index][k]}') form.remove(k);
        }
      });
      next[index] = {...base, ...form}; // keeps values the form does not show (taxes from the price table, line spec)
    }
    onChanged(next);
    final line = adding ? next.last : next[index];
    if (duplicateKey != null && line[duplicateKey] != null && context.mounted) {
      final at = next.indexWhere((l) => !identical(l, line) && l[duplicateKey] == line[duplicateKey]);
      if (at >= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Este produto já está na linha ${at + 1}. Confira se não é repetido.')));
      }
    }
    if (again && context.mounted) {
      await _edit(context, null, {
        for (final k in carryKeys)
          if (r[k] != null) k: r[k],
      }, next);
    }
  }

  void _remove(BuildContext context, int index) {
    final before = [...lines];
    onChanged([...lines]..removeAt(index));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Linha ${index + 1} removida'),
          persist: false,
          action: SnackBarAction(label: 'Desfazer', onPressed: () => onChanged(before)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final (i, l) in lines.indexed) {...l, '_n': i + 1},
    ];
    controller?._add = enabled && addEnabled ? () => unawaited(_edit(context)) : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('$title (${lines.length})', style: Theme.of(context).textTheme.titleMedium)),
                if (enabled && !addEnabled && disabledHint != null)
                  Flexible(child: Padding(padding: const EdgeInsets.only(right: 8), child: Text(disabledHint!, textAlign: TextAlign.end, style: Theme.of(context).textTheme.bodySmall))),
                if (enabled)
                  FilledButton.tonalIcon(
                    key: const ValueKey('add-line'),
                    onPressed: addEnabled ? () => _edit(context) : null,
                    icon: const Icon(Icons.add),
                    label: Text(addLabel),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SimpleTable(
              columns: [ColumnSpec('#', (e) => '${e['_n']}'), ...columns],
              rows: rows,
              rowColor: rowColor == null ? null : (e) => rowColor!(lines[(e['_n'] as int) - 1]),
              actions: enabled
                  ? (e) => [
                      IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _edit(context, (e['_n'] as int) - 1)),
                      if (addEnabled)
                        IconButton(
                          tooltip: 'Duplicar',
                          icon: const Icon(Icons.copy_outlined, size: 20),
                          onPressed: () {
                            final i = (e['_n'] as int) - 1;
                            onChanged([...lines]..insert(i + 1, {...lines[i]}));
                          },
                        ),
                      IconButton(tooltip: 'Remover', icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _remove(context, (e['_n'] as int) - 1)),
                    ]
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

String lbl(Map<String, dynamic> e, String key) {
  final labels = e['_labels'];
  if (labels is Map && labels[key] != null) return '${labels[key]}';
  return e[key] == null ? '' : '#${e[key]}';
}

Map<String, dynamic> stripLocal(Map<String, dynamic> e) => Map.of(e)..removeWhere((k, _) => k.startsWith('_'));
