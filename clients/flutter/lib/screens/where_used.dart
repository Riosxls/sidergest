import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/load_error.dart';
import 'product_detail.dart';

/// Shows where an item is used in BOMs.
class WhereUsedView extends StatefulWidget {
  const WhereUsedView({super.key, required this.session, required this.path});

  final Session session;
  final String path;

  @override
  State<WhereUsedView> createState() => _WhereUsedViewState();
}

class _WhereUsedViewState extends State<WhereUsedView> {
  late Future<List<Map<String, dynamic>>> _future = _fetch();

  Future<List<Map<String, dynamic>>> _fetch() async => ((await widget.session.api.get(widget.path)) as List).cast<Map<String, dynamic>>();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return LoadError(
            message: friendlyError(snap.error!),
            onRetry: () => setState(() {
              _future = _fetch();
            }),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_tree_outlined, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Este item não aparece em nenhuma estrutura de produto', textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = rows[i];
            return ListTile(
              leading: const Icon(Icons.precision_manufacturing_outlined),
              title: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${r['productCode']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: '  ${r['productName']}'),
                  ],
                ),
              ),
              subtitle: Text('Operação ${r['operationSequence']}'),
              // The quantity is the answer to "how much of it goes in", so it sits where the eye ends the row.
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${fmt(r['quantity'])} ${r['unit']}', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () async {
                await openProduct(context, widget.session, r['productId'] as int);
                if (!mounted) return;
                setState(() {
                  _future = _fetch();
                });
              },
            );
          },
        );
      },
    );
  }
}

/// Screen wrapper around [WhereUsedView].
class WhereUsedScreen extends StatelessWidget {
  const WhereUsedScreen({super.key, required this.session, required this.path, required this.title});

  final Session session;
  final String path;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: WhereUsedView(session: session, path: path),
  );
}
