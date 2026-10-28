import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import 'entity_form.dart';
import 'record_list.dart';

Future<T?> runAction<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  try {
    final r = await action();
    if (success != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    return r;
  } catch (e) {
    if (context.mounted) showError(context, e is ApiException ? describeError(e) : e);
    return null;
  }
}

String describeError(ApiException e) {
  if (e.fieldErrors.isEmpty) return e.message;
  return e.fieldErrors.entries.map((x) => '${fieldLabel(x.key)}: ${x.value.join('; ')}').join('\n');
}

String fieldLabel(String key) {
  final m = RegExp(r'^[Ll]ines\[(\d+)\]\.?(.*)$').firstMatch(key);
  if (m != null) return 'Linha ${int.parse(m[1]!) + 1}${m[2]!.isEmpty ? '' : ' · ${m[2]}'}';
  return key;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  bool required = false,
  String initial = '',
  String confirmLabel = 'Confirmar',
}) => showDialog<String>(
  context: context,
  builder: (_) => _PromptDialog(title: title, label: label, required: required, initial: initial, confirmLabel: confirmLabel),
);

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.label, required this.required, required this.initial, required this.confirmLabel});

  final String title;
  final String label;
  final bool required;
  final String initial;
  final String confirmLabel;

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
      FilledButton(onPressed: _ok, child: Text(widget.confirmLabel)),
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

class LinesEditor extends StatelessWidget {
  const LinesEditor({
    super.key,
    required this.api,
    required this.title,
    required this.fields,
    required this.columns,
    required this.lines,
    required this.onChanged,
    this.enabled = true,
    this.newTitle = 'Nova linha',
    this.editTitle,
  });

  final ApiClient api;
  final String title;
  final List<FieldSpec> fields;
  final List<ColumnSpec> columns;
  final List<Map<String, dynamic>> lines;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;
  final String newTitle;
  final String? editTitle;

  Future<void> _edit(BuildContext context, [int? index]) async {
    final r = await showEntityForm(
      context,
      api: api,
      title: index == null ? newTitle : (editTitle ?? 'Linha ${index + 1}'),
      fields: fields,
      initial: index == null ? null : lines[index],
      onSubmit: (_) async => null,
    );
    if (r == null) return;
    final next = [...lines];
    if (index == null) {
      next.add(r);
    } else {
      next[index] = r;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final (i, l) in lines.indexed) {...l, '_n': i + 1},
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('$title (${lines.length})', style: Theme.of(context).textTheme.titleMedium)),
                if (enabled)
                  FilledButton.tonalIcon(
                    key: const ValueKey('add-line'),
                    onPressed: () => _edit(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar linha'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SimpleTable(
              columns: [ColumnSpec('#', (e) => '${e['_n']}'), ...columns],
              rows: rows,
              actions: enabled
                  ? (e) => [
                      IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _edit(context, (e['_n'] as int) - 1)),
                      IconButton(
                        tooltip: 'Remover',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => onChanged([...lines]..removeAt((e['_n'] as int) - 1)),
                      ),
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
