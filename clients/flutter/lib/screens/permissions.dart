import 'package:flutter/material.dart';

import '../api.dart';
import '../labels.dart';
import '../session.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, required this.session});

  final Session session;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  late final Future<Map<String, dynamic>> _future = _fetch();

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
      final cs = Theme.of(context).colorScheme;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('A matriz de permissões é definida no servidor e é somente leitura aqui.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 52,
              columns: [
                const DataColumn(label: Text('Permissão')),
                for (final r in roles) DataColumn(label: Text(userRoles[r] ?? r)),
              ],
              rows: [
                for (final p in policies)
                  DataRow(
                    cells: [
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (policyDescriptions[p] != null) Text(policyDescriptions[p]!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      for (final r in roles) DataCell(matrix[r]!.contains(p) ? Icon(Icons.check, key: ValueKey('cell-$r-$p'), color: cs.primary) : const SizedBox.shrink()),
                    ],
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
