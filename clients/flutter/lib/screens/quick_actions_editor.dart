import 'package:flutter/material.dart';

import '../session.dart';
import '../widgets/responsive.dart';
import 'quick_actions.dart';

/// Lets the user choose and order the Painel shortcuts (at most [Session.maxQuickActions]). Saves on "Salvar"; "Restaurar padrão" goes back to the default set.
Future<void> showQuickActionsEditor(BuildContext context, Session session) => showDialog<void>(context: context, builder: (_) => QuickActionsEditor(session: session));

class QuickActionsEditor extends StatefulWidget {
  const QuickActionsEditor({super.key, required this.session});

  final Session session;

  @override
  State<QuickActionsEditor> createState() => _QuickActionsEditorState();
}

class _QuickActionsEditorState extends State<QuickActionsEditor> {
  late final Map<String, QuickAction> _catalog;
  late List<String> _picked;

  @override
  void initState() {
    super.initState();
    // The catalog is only used for names and icons here, so a no-op "go" keeps the screen-visit shortcuts in the list.
    _catalog = {for (final a in quickActionCatalog(widget.session, go: (_) {})) a.id: a};
    _picked = [for (final a in quickActionsFor(widget.session, go: (_) {})) a.id];
  }

  bool get _full => _picked.length >= Session.maxQuickActions;

  Future<void> _save() async {
    final isDefault = _picked.length == defaultQuickActionIds.length && Iterable<int>.generate(_picked.length).every((i) => _picked[i] == defaultQuickActionIds[i]);
    await widget.session.setQuickActionIds(isDefault ? null : _picked);
    if (mounted) Navigator.pop(context);
  }

  void _restore() => setState(() => _picked = [for (final id in defaultQuickActionIds) if (_catalog.containsKey(id)) id]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final others = [for (final a in _catalog.values) if (!_picked.contains(a.id)) a];
    return AlertDialog(
      title: const Text('Atalhos do Painel'),
      content: SizedBox(
        width: dialogWidth(context, 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Escolha até ${Session.maxQuickActions} atalhos e arraste para mudar a ordem. ${_picked.length} de ${Session.maxQuickActions} em uso.',
                key: const ValueKey('quick-actions-count'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              if (_picked.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Nenhum atalho escolhido: o Painel mostra os atalhos padrão.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                )
              else
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: true,
                  onReorderItem: (from, to) => setState(() {
                    _picked.insert(to, _picked.removeAt(from));
                  }),
                  children: [
                    for (final id in _picked)
                      ListTile(
                        key: ValueKey('picked-$id'),
                        dense: true,
                        leading: Icon(_catalog[id]!.icon),
                        title: Text(_catalog[id]!.label),
                        trailing: Padding(
                          padding: const EdgeInsets.only(right: 32),
                          child: IconButton(
                            key: ValueKey('remove-$id'),
                            tooltip: 'Tirar do Painel',
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => setState(() => _picked.remove(id)),
                          ),
                        ),
                      ),
                  ],
                ),
              if (others.isNotEmpty) ...[
                const Divider(height: 24),
                Text('Disponíveis', style: theme.textTheme.titleSmall),
                if (_full) Text('Limite de ${Session.maxQuickActions} atalhos: tire um para adicionar outro.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                for (final a in others)
                  ListTile(
                    key: ValueKey('other-${a.id}'),
                    dense: true,
                    enabled: !_full,
                    leading: Icon(a.icon),
                    title: Text(a.label),
                    trailing: IconButton(
                      key: ValueKey('add-${a.id}'),
                      tooltip: _full ? 'Limite de ${Session.maxQuickActions} atalhos' : 'Colocar no Painel',
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _full ? null : () => setState(() => _picked.add(a.id)),
                    ),
                    onTap: _full ? null : () => setState(() => _picked.add(a.id)),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(key: const ValueKey('quick-actions-restore'), onPressed: _restore, child: const Text('Restaurar padrão')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(key: const ValueKey('quick-actions-save'), onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}
