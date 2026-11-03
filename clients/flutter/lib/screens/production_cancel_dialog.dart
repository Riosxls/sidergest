import 'package:flutter/material.dart';

/// Asks why an OF is cancelled; the technical kind is for a planning reason (duplicate, wrong product...) and is not counted as a loss.
class CancelOrderDialog extends StatefulWidget {
  const CancelOrderDialog({super.key, required this.reference});

  final String reference;

  @override
  State<CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<CancelOrderDialog> {
  final _reason = TextEditingController();
  bool _technical = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Cancelar ${widget.reference}'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('cancel-reason'),
            controller: _reason,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Motivo'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const ValueKey('cancel-technical'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Cancelamento técnico'),
            subtitle: const Text('Por motivo de planejamento (duplicada, produto errado...): não conta como perda do cliente'),
            value: _technical,
            onChanged: (v) => setState(() => _technical = v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
      FilledButton(
        key: const ValueKey('cancel-confirm'),
        onPressed: _reason.text.trim().isEmpty ? null : () => Navigator.pop(context, (reason: _reason.text.trim(), technical: _technical)),
        child: const Text('Cancelar OF'),
      ),
    ],
  );
}
