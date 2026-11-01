import 'package:flutter/material.dart';

import '../api.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/page_column.dart';

/// Read-only matrix of what each role can do; mirrors `Access.cs` on the server.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, required this.session});

  final Session session;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  late final Future<Map<String, dynamic>> _future = _fetch();

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
      if (snap.hasError) return Center(child: Text(friendlyError(snap.error!)));
      final d = snap.data;
      if (d == null) return const Center(child: CircularProgressIndicator());
      final policies = (d['policies'] as List).cast<String>();
      final matrix = {for (final e in (d['roles'] as Map<String, dynamic>).entries) e.key: (e.value as List).cast<String>().toSet()};
      final order = userRoles.keys.toList();
      int rank(String r) => order.contains(r) ? order.indexOf(r) : order.length;
      final roles = matrix.keys.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
      return PageColumn(
        maxWidth: _labelWidth + _colWidth * roles.length + 32,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('A matriz de permissões é definida no servidor e é somente leitura aqui.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: _labelWidth, child: _labelsColumn(context, policies)),
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

  // Fixed permission column on the left, role columns scroll sideways beside it; both panes use the same row heights so they stay aligned.
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

  Widget _labelsColumn(BuildContext context, List<String> policies) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        _cellBox(
          cs,
          0,
          _headHeight,
          Text('Permissão', style: theme.textTheme.titleSmall),
          width: _labelWidth,
          alignment: Alignment.centerLeft,
        ),
        for (final (i, p) in policies.indexed)
          _cellBox(
            cs,
            i + 2,
            _rowHeight,
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
            width: _labelWidth,
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
                _headHeight,
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
                  _rowHeight,
                  matrix[r]!.contains(p)
                      ? Icon(Icons.check, key: ValueKey('cell-$r-$p'), color: cs.primary, semanticLabel: '${userRoles[r] ?? r}: permitido')
                      : Text('—', style: TextStyle(color: cs.outlineVariant)),
                  width: _colWidth,
                ),
            ],
          ),
      ],
    );
  }
}
