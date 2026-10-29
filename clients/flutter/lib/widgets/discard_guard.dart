import 'package:flutter/material.dart';

/// Asks before leaving (back arrow, system back, Esc, tapping outside a dialog) when [isDirty] says there are unsaved edits.
/// Explicit `Navigator.pop` calls, such as saving, are not intercepted.
class DiscardGuard extends StatelessWidget {
  const DiscardGuard({super.key, required this.isDirty, required this.child});

  final bool Function() isDirty;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final navigator = Navigator.of(context);
      if (!isDirty() || await confirmDiscard(context)) navigator.pop();
    },
    child: child,
  );
}

Future<bool> confirmDiscard(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text('Você preencheu informações que ainda não foram salvas. Se sair agora, elas serão perdidas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuar editando')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Descartar')),
        ],
      ),
    ) ??
    false;
