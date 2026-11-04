import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/load_error.dart';
import '../widgets/page_column.dart';
import '../widgets/responsive.dart';

/// Read-only matrix of what each role can do; mirrors `Access.cs` on the server.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, required this.session});

  final Session session;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  late Future<Map<String, dynamic>> _future = _fetch();

  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetch() async => await widget.session.api.get('/api/access/matrix') as Map<String, dynamic>;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, snap) {
      if (snap.hasError) return LoadError(message: friendlyError(snap.error!), onRetry: () => setState(() => _future = _fetch()));
      final d = snap.data;
      if (d == null) return const Center(child: CircularProgressIndicator());
      final policies = (d['policies'] as List).cast<String>();
      final matrix = {for (final e in (d['roles'] as Map<String, dynamic>).entries) e.key: (e.value as List).cast<String>().toSet()};
      final order = userRoles.keys.toList();
      int rank(String r) => order.contains(r) ? order.indexOf(r) : order.length;
      final roles = matrix.keys.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
      return LayoutBuilder(
        builder: (context, box) {
          // Narrow window: one expandable section per role instead of a sideways-scrolling grid.
          if (box.maxWidth < 720) return _accordion(context, roles, policies, matrix);
          final labelWidth = math.min(_labelWidth, box.maxWidth * 0.4);
          return PageColumn(
            maxWidth: labelWidth + _colWidth * roles.length + 32,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('A matriz de permissões é definida no servidor e é somente leitura aqui.', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: labelWidth, child: _labelsColumn(context, policies, labelWidth)),
                    Expanded(
                      child: Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _gridColumn(context, roles, policies, matrix),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );

  Widget _accordion(BuildContext context, List<String> roles, List<String> policies, Map<String, Set<String>> matrix) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('A matriz de permissões é definida no servidor e é somente leitura aqui.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        for (final r in roles)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: ValueKey('role-$r'),
              title: Text(userRoles[r] ?? r),
              subtitle: Text('${matrix[r]!.length} de ${policies.length} permissões'),
              children: [
                for (final p in policies)
                  ListTile(
                    dense: true,
                    leading: matrix[r]!.contains(p)
                        ? Icon(Icons.check, key: ValueKey('cell-$r-$p'), color: cs.primary, semanticLabel: '${userRoles[r] ?? r}: permitido')
                        : Icon(Icons.remove, color: cs.onSurfaceVariant, semanticLabel: '${userRoles[r] ?? r}: não permitido'),
                    title: Text(policyDescriptions[p] ?? p, style: matrix[r]!.contains(p) ? null : TextStyle(color: cs.onSurfaceVariant)),
                    subtitle: Text(p),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // Fixed permission column on the left, role columns scroll sideways beside it; both panes use the same (text-scaled) row heights so they stay aligned.
  static const _headHeight = 56.0, _rowHeight = 60.0, _colWidth = 104.0, _labelWidth = 340.0;

  Widget _cellBox(ColorScheme cs, int i, double height, Widget child, {double? width, AlignmentGeometry alignment = Alignment.center}) => Container(
    width: width,
    height: height,
    alignment: alignment,
    decoration: BoxDecoration(
      color: (i - 1).isOdd ? cs.surfaceContainerHigh.withValues(alpha: 0.5) : null,
      border: Border(bottom: BorderSide(color: cs.outlineVariant)),
    ),
    child: child,
  );

  Widget _labelsColumn(BuildContext context, List<String> policies, double labelWidth) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        _cellBox(
          cs,
          0,
          scaledHeight(context, _headHeight),
          Text('Permissão', style: theme.textTheme.titleSmall),
          width: labelWidth,
          alignment: Alignment.centerLeft,
        ),
        for (final (i, p) in policies.indexed)
          _cellBox(
            cs,
            i + 2,
            scaledHeight(context, _rowHeight),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  policyDescriptions[p] ?? p,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(p, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
            width: labelWidth,
            alignment: Alignment.centerLeft,
          ),
      ],
    );
  }

  Widget _gridColumn(BuildContext context, List<String> roles, List<String> policies, Map<String, Set<String>> matrix) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        Row(
          children: [
            for (final r in roles)
              _cellBox(
                cs,
                0,
                scaledHeight(context, _headHeight),
                Text(userRoles[r] ?? r, textAlign: TextAlign.center, maxLines: 2, style: theme.textTheme.titleSmall),
                width: _colWidth,
              ),
          ],
        ),
        for (final (i, p) in policies.indexed)
          Row(
            children: [
              for (final r in roles)
                _cellBox(
                  cs,
                  i + 2,
                  scaledHeight(context, _rowHeight),
                  matrix[r]!.contains(p)
                      ? Icon(Icons.check, key: ValueKey('cell-$r-$p'), color: cs.primary, semanticLabel: '${userRoles[r] ?? r}: permitido')
                      : Semantics(label: '${userRoles[r] ?? r}: não permitido', excludeSemantics: true, child: Text('—', style: TextStyle(color: cs.onSurfaceVariant))),
                  width: _colWidth,
                ),
            ],
          ),
      ],
    );
  }
}
