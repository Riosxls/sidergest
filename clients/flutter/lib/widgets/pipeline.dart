import 'package:flutter/material.dart';

import '../entities.dart';

enum Tone { neutral, info, progress, success, warning, danger }

(Color, Color) toneColors(BuildContext context, Tone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final cs = Theme.of(context).colorScheme;
  Color c(int light, int darkBg) => Color(dark ? darkBg : light);
  return switch (tone) {
    Tone.neutral => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    Tone.info => (c(0xFFDCEBFB, 0xFF1D3A5C), c(0xFF0B4A8B, 0xFFB9D8FA)),
    Tone.progress => (c(0xFFEDE3FB, 0xFF3A2A56), c(0xFF5B2BA0, 0xFFDCC8FA)),
    Tone.success => (c(0xFFDDF3E4, 0xFF1C4A2B), c(0xFF1E6B3A, 0xFFB8E6C6)),
    Tone.warning => (c(0xFFFFF0D1, 0xFF54400F), c(0xFF8A5A00, 0xFFFFDB92)),
    Tone.danger => (c(0xFFFDE2E1, 0xFF5C1E1C), c(0xFFA3221D, 0xFFFFC4C0)),
  };
}

Color toneAccent(BuildContext context, Tone tone) => switch (tone) {
  Tone.neutral => Theme.of(context).colorScheme.outline,
  Tone.info => const Color(0xFF1F6FBF),
  Tone.progress => const Color(0xFF7A4CC2),
  Tone.success => const Color(0xFF2E8B4F),
  Tone.warning => const Color(0xFFD08A00),
  Tone.danger => const Color(0xFFC62828),
};

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = Tone.neutral, this.icon});

  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class PathStep {
  const PathStep(this.label, {this.icon});

  final String label;
  final IconData? icon;
}

class StagePath extends StatelessWidget {
  const StagePath({super.key, required this.steps, required this.current, this.failedLabel});

  final List<PathStep> steps;
  final int current;
  final String? failedLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = toneAccent(context, Tone.success);
    final failed = failedLabel != null;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 640;
        final roomy = box.maxWidth / steps.length >= 150;
        return Row(
          children: [
            for (final (i, s) in steps.indexed)
              Expanded(
                child: Tooltip(
                  message: s.label,
                  child: ClipPath(
                    clipper: _Chevron(first: i == 0, last: i == steps.length - 1),
                    child: Container(
                      key: ValueKey('path-$i'),
                      height: 44,
                      margin: const EdgeInsets.only(right: 2),
                      padding: EdgeInsets.only(left: i == 0 ? 8 : 16, right: 8),
                      color: i < current
                          ? done
                          : i == current
                          ? (failed ? toneAccent(context, Tone.danger) : cs.primary)
                          : cs.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (i < current)
                            const Icon(Icons.check, size: 16, color: Colors.white)
                          else if (s.icon != null)
                            Icon(s.icon, size: 16, color: i == current ? Colors.white : cs.onSurfaceVariant),
                          if (!compact || i == current) ...[
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                i == current && failed ? failedLabel! : s.label,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  fontSize: roomy ? null : 11.5,
                                  height: 1.1,
                                  color: i <= current ? Colors.white : cs.onSurfaceVariant,
                                  fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Chevron extends CustomClipper<Path> {
  _Chevron({required this.first, required this.last});

  final bool first;
  final bool last;

  @override
  Path getClip(Size s) {
    const d = 10.0;
    final p = Path()..moveTo(0, 0);
    p.lineTo(last ? s.width : s.width - d, 0);
    if (!last) p.lineTo(s.width, s.height / 2);
    p.lineTo(last ? s.width : s.width - d, s.height);
    p.lineTo(0, s.height);
    if (!first) p.lineTo(d, s.height / 2);
    return p..close();
  }

  @override
  bool shouldReclip(_Chevron old) => old.first != first || old.last != last;
}

class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.caption, this.icon, this.tone = Tone.info, this.onTap});

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = toneColors(context, tone);
    return SizedBox(
      width: 210,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (icon != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: fg, size: 22),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      if (caption != null) Text(caption!, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProgressMeter extends StatelessWidget {
  const ProgressMeter(this.value, {super.key, this.label});

  final num value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0, 1).toDouble();
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 6,
              color: toneAccent(context, v >= 1 ? Tone.success : Tone.progress),
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(label ?? '${(v * 100).round()}%', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class TimelineEntry {
  const TimelineEntry({required this.title, required this.at, this.subtitle, this.user, this.tone = Tone.neutral, this.icon = Icons.circle});

  final String title;
  final String? subtitle;
  final String? user;
  final Object? at;
  final Tone tone;
  final IconData icon;
}

class TimelineView extends StatelessWidget {
  const TimelineView({super.key, required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Sem histórico'));
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final (i, e) in entries.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 32,
                  child: Column(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(color: toneColors(context, e.tone).$1, shape: BoxShape.circle),
                        child: Icon(e.icon, size: 14, color: toneColors(context, e.tone).$2),
                      ),
                      if (i < entries.length - 1) Expanded(child: Container(width: 2, color: theme.dividerColor)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14, top: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        if (e.subtitle != null && e.subtitle!.isNotEmpty) Text(e.subtitle!, style: theme.textTheme.bodySmall),
                        Text(
                          [fmtDate(e.at), if (e.user != null) e.user!].join(' · '),
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class NextStepCard extends StatelessWidget {
  const NextStepCard({super.key, required this.title, required this.message, this.actions = const [], this.tone = Tone.info});

  final String title;
  final String message;
  final List<Widget> actions;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(context, tone);
    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg)),
                ],
              ),
            ),
            if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}

class RecordHeader extends StatelessWidget {
  const RecordHeader({super.key, required this.icon, required this.kind, required this.title, required this.badge, this.fields = const [], this.amount});

  final IconData icon;
  final String kind;
  final String title;
  final Widget badge;
  final List<(String, String)> fields;
  final String? amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kind, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 10),
                          badge,
                        ],
                      ),
                    ],
                  ),
                ),
                if (amount != null) Text(amount!, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            if (fields.isNotEmpty) ...[
              const Divider(height: 24),
              Wrap(
                spacing: 28,
                runSpacing: 8,
                children: [
                  for (final (k, v) in fields.where((f) => f.$2.isNotEmpty))
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(k, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        Text(v, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmStep(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  IconData icon = Icons.help_outline,
  bool danger = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(icon, color: danger ? toneAccent(c, Tone.danger) : null),
        title: Text(title),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Text(message)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(
            key: const ValueKey('confirm-step'),
            style: danger ? FilledButton.styleFrom(backgroundColor: toneAccent(c, Tone.danger)) : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;
