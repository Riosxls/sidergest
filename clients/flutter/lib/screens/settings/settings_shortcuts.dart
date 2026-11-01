import 'package:flutter/material.dart';

import 'settings_widgets.dart';

/// Keys the app reacts to. Keep in step with the handlers in `shell.dart`, `dashboard.dart`, `modules.dart` and `command_palette.dart`.
const shortcutList = <(String keys, String what)>[
  ('Ctrl + K', 'Abre a busca rápida: telas, produtos, pedidos, ordens de fabricação e outros registros'),
  ('F5', 'Atualiza o Painel e as telas de módulo na hora'),
  ('↑  ↓', 'Move a seleção entre os resultados da busca rápida'),
  ('Enter', 'Abre o resultado selecionado na busca rápida'),
  ('Esc', 'Fecha a busca rápida, a janela aberta ou este painel'),
  ('Tab', 'Vai para o próximo campo; Shift + Tab volta ao anterior'),
];

class ShortcutsView extends StatelessWidget {
  const ShortcutsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsGroup(
      note: 'Estes atalhos funcionam no Windows e no navegador.',
      children: [
        for (final (keys, what) in shortcutList)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 112,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Text(keys, textAlign: TextAlign.center, style: theme.textTheme.labelLarge),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(what))),
              ],
            ),
          ),
      ],
    );
  }
}
