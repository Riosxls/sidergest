import 'package:flutter/material.dart';

import '../quick_actions.dart';
import 'widgets.dart';

class QuickActionsCard extends StatelessWidget {
  const QuickActionsCard(this.actions, {super.key});

  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        key: const ValueKey('quick-actions'),
        margin: EdgeInsets.zero,
        shape: dashCardShape(context),
        color: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ações rápidas', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final a in actions) FilledButton.tonalIcon(onPressed: () => a.run(context), icon: Icon(a.icon), label: Text(a.label))],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef OnboardingStep = (String label, String id, bool done, String navId);

class OnboardingCard extends StatelessWidget {
  const OnboardingCard({super.key, required this.steps, required this.onDismiss, required this.onOpen});

  final List<OnboardingStep> steps;
  final VoidCallback onDismiss;
  final void Function()? Function(String navId) onOpen;

  @override
  Widget build(BuildContext context) {
    final done = steps.where((s) => s.$3).length;
    if (done == steps.length) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        margin: EdgeInsets.zero,
        shape: dashCardShape(context),
        color: cs.surfaceContainerHigh,
        child: ExpansionTile(
          key: const ValueKey('onboarding'),
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: Icon(Icons.rocket_launch_outlined, color: cs.primary),
          title: Text('Primeiros passos', style: theme.textTheme.titleMedium),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(value: done / steps.length),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$done de ${steps.length}', style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more),
              IconButton(key: const ValueKey('tutorial-dismiss'), tooltip: 'Dispensar', onPressed: onDismiss, icon: const Icon(Icons.close)),
            ],
          ),
          children: [
            for (final s in steps)
              ListTile(
                key: ValueKey('step-${s.$2}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(s.$3 ? Icons.check_circle : Icons.radio_button_unchecked, color: s.$3 ? cs.primary : cs.onSurfaceVariant),
                title: Text(
                  s.$1,
                  style: s.$3 ? TextStyle(decoration: TextDecoration.lineThrough, color: cs.onSurfaceVariant) : null,
                ),
                trailing: s.$3 || onOpen(s.$4) == null ? null : FilledButton.tonal(onPressed: onOpen(s.$4), child: const Text('Abrir')),
              ),
          ],
        ),
      ),
    );
  }
}
