import 'package:flutter/material.dart';

import '../api.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/page_column.dart';

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
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      const headHeight = 56.0, rowHeight = 60.0, colWidth = 104.0, labelWidth = 340.0;
      // Fixed permission column on the left, role columns scroll sideways beside it; both panes use the same row heights so they stay aligned.
      Color? band(int i) => i.isOdd ? cs.surfaceContainerHigh.withValues(alpha: 0.5) : null;
      Widget cellBox(int i, double height, Widget child, {double? width, AlignmentGeometry alignment = Alignment.center}) => Container(
        width: width,
        height: height,
        alignment: alignment,
        decoration: BoxDecoration(
          color: band(i - 1),
          border: Border(bottom: BorderSide(color: cs.outlineVariant)),
        ),
        child: child,
      );
      final labels = Column(
        children: [
          cellBox(
            0,
            headHeight,
            Text('Permissão', style: theme.textTheme.titleSmall),
            width: labelWidth,
            alignment: Alignment.centerLeft,
          ),
          for (final (i, p) in policies.indexed)
            cellBox(
              i + 2,
              rowHeight,
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
      final grid = Column(
        children: [
          Row(
            children: [
              for (final r in roles)
                cellBox(
                  0,
                  headHeight,
                  Text(userRoles[r] ?? r, textAlign: TextAlign.center, maxLines: 2, style: theme.textTheme.titleSmall),
                  width: colWidth,
                ),
            ],
          ),
          for (final (i, p) in policies.indexed)
            Row(
              children: [
                for (final r in roles)
                  cellBox(
                    i + 2,
                    rowHeight,
                    matrix[r]!.contains(p)
                        ? Icon(Icons.check, key: ValueKey('cell-$r-$p'), color: cs.primary, semanticLabel: '${userRoles[r] ?? r}: permitido')
                        : Text('—', style: TextStyle(color: cs.outlineVariant)),
                    width: colWidth,
                  ),
              ],
            ),
        ],
      );
      final scroll = _scroll;
      return PageColumn(
        maxWidth: labelWidth + colWidth * roles.length + 32,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('A matriz de permissões é definida no servidor e é somente leitura aqui.', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: labelWidth, child: labels),
                Expanded(
                  child: Scrollbar(
                    controller: scroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(controller: scroll, scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 12), child: grid),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
