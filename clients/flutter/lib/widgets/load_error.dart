import 'package:flutter/material.dart';

import '../api.dart' show friendlyError;
import 'record_skeleton.dart';

/// Shown in place of a page whose data could not be loaded: says why and offers to try again or go back.
class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              if (onRetry != null) FilledButton.tonal(onPressed: onRetry, child: const Text('Tentar novamente')),
              if (Navigator.canPop(context)) TextButton(onPressed: () => Navigator.maybePop(context), child: const Text('Voltar')),
            ],
          ),
        ],
      ),
    ),
  );
}

/// A record page that only knows the id (a web address, a restored place, a search hit): loads the record, then builds the page.
class RecordLoader extends StatefulWidget {
  const RecordLoader({super.key, required this.title, required this.load, required this.builder});

  final String title;
  final Future<Object?> Function() load;
  final Widget Function(Map<String, dynamic> data) builder;

  @override
  State<RecordLoader> createState() => _RecordLoaderState();
}

class _RecordLoaderState extends State<RecordLoader> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _error = null);
    try {
      final d = await widget.load();
      if (mounted) setState(() => _data = d as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d != null) return widget.builder(d);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _error != null ? LoadError(message: _error!, onRetry: _fetch) : const RecordSkeleton(),
    );
  }
}

/// One entry of a [RelatedMenu].
class RelatedLink {
  const RelatedLink(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// App bar button listing the records a page points to (its customer, supplier, product...), so no name is a dead end.
class RelatedMenu extends StatelessWidget {
  const RelatedMenu({super.key, required this.links});

  final List<RelatedLink?> links;

  @override
  Widget build(BuildContext context) {
    final items = links.whereType<RelatedLink>().toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<RelatedLink>(
      key: const ValueKey('related-menu'),
      tooltip: 'Relacionados',
      icon: const Icon(Icons.link),
      onSelected: (l) => l.onTap(),
      itemBuilder: (_) => [
        for (final l in items)
          PopupMenuItem<RelatedLink>(
            value: l,
            child: Row(
              children: [
                Icon(l.icon, size: 20),
                const SizedBox(width: 12),
                Flexible(child: Text(l.label, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
    );
  }
}
