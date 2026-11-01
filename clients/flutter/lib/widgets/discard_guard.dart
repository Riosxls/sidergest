import 'dart:async';

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

/// Lets a view inside a host (the settings window) tell the host it has unsaved edits, so every way out of the host
/// asks first. A view with no host around it keeps using its own [DiscardGuard].
class DirtyRegistry {
  bool Function()? _isDirty;

  bool get dirty => _isDirty?.call() ?? false;

  void register(bool Function() isDirty) => _isDirty = isDirty;

  void unregister(bool Function() isDirty) {
    if (_isDirty == isDirty) _isDirty = null;
  }

  /// Runs [action] right away when nothing is dirty, otherwise after the user agrees to discard.
  Future<void> guard(BuildContext context, FutureOr<void> Function() action) async {
    if (!dirty || await confirmDiscard(context)) await action();
  }
}

class DirtyScope extends InheritedWidget {
  const DirtyScope({super.key, required this.registry, required super.child});

  final DirtyRegistry registry;

  static DirtyRegistry? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<DirtyScope>()?.registry;

  @override
  bool updateShouldNotify(DirtyScope old) => registry != old.registry;
}

/// Puts [child] under the nearest [DirtyScope] when there is one; otherwise wraps it in a [DiscardGuard].
class DirtyReporter extends StatefulWidget {
  const DirtyReporter({super.key, required this.isDirty, required this.child});

  final bool Function() isDirty;
  final Widget child;

  @override
  State<DirtyReporter> createState() => _DirtyReporterState();
}

class _DirtyReporterState extends State<DirtyReporter> {
  DirtyRegistry? _registry;
  bool _fn() => widget.isDirty();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = DirtyScope.maybeOf(context);
    if (!identical(r, _registry)) {
      _registry?.unregister(_fn);
      _registry = r?..register(_fn);
    }
  }

  @override
  void dispose() {
    _registry?.unregister(_fn);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _registry != null ? widget.child : DiscardGuard(isDirty: widget.isDirty, child: widget.child);
}
