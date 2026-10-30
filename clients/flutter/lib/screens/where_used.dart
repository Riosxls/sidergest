import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import 'product_detail.dart';

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
        if (snap.hasError) return Center(child: Text(friendlyError(snap.error!)));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const Center(child: Text('Não é usado em nenhuma estrutura'));
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = rows[i];
            return ListTile(
              leading: const Icon(Icons.precision_manufacturing_outlined),
              title: Text('${r['productCode']}  ${r['productName']}'),
              subtitle: Text('Operação ${r['operationSequence']} · ${fmt(r['quantity'])} ${r['unit']}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProductDetailScreen(session: widget.session, productId: r['productId'] as int),
                  ),
                );
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
