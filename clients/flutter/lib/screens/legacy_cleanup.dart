import 'package:flutter/material.dart';

import '../api.dart';
import '../session.dart';

/// Admin tool for the orders imported from the old system: fills empty processes and cancels stale OFs, always after a preview.
Future<void> showLegacyCleanupDialog(BuildContext context, Session session) => showDialog<void>(context: context, builder: (_) => _LegacyCleanup(session: session));

class _LegacyCleanup extends StatefulWidget {
  const _LegacyCleanup({required this.session});

  final Session session;

  @override
  State<_LegacyCleanup> createState() => _LegacyCleanupState();
}

class _LegacyCleanupState extends State<_LegacyCleanup> {
  final _days = TextEditingController(text: '90');
  final _reason = TextEditingController(text: 'Legado sem andamento (limpeza)');
  Map<String, dynamic>? _processPreview;
  Map<String, dynamic>? _stalePreview;
  String? _message;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _days.dispose();
    _reason.dispose();
    super.dispose();
  }

  int get _daysValue => int.tryParse(_days.text.trim()) ?? 0;

  Future<void> _call(String path, Map<String, dynamic> body, void Function(Map<String, dynamic>) done) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      done(await widget.session.api.post(path, body) as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewProcess() => _call('/api/production/orders/bulk/suggest-process', {'apply': false}, (r) => setState(() => _processPreview = r));

  Future<void> _applyProcess() => _call('/api/production/orders/bulk/suggest-process', {'apply': true}, (r) {
    setState(() {
      _processPreview = null;
      _message = 'Processo sugerido escrito em ${r['done']} OFs.';
    });
  });

  Future<void> _previewStale() => _call('/api/production/orders/bulk/cancel-stale', {'olderThanDays': _daysValue, 'reason': _reason.text.trim(), 'apply': false}, (r) => setState(() => _stalePreview = r));

  Future<void> _applyStale() async {
    final n = _stalePreview?['matched'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancelar OFs antigas?'),
        content: Text('$n ordens de fabricação ainda não liberadas e sem movimento serão canceladas. Pedidos de venda e estoque não mudam.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(key: const ValueKey('confirm-cancel-stale'), onPressed: () => Navigator.pop(c, true), child: const Text('Cancelar OFs')),
        ],
      ),
    );
    if (ok != true) return;
    await _call('/api/production/orders/bulk/cancel-stale', {'olderThanDays': _daysValue, 'reason': _reason.text.trim(), 'apply': true}, (r) {
      setState(() {
        _stalePreview = null;
        _message = '${r['done']} OFs canceladas${(r['skipped'] as num) > 0 ? ' · ${r['skipped']} puladas (têm OF filha aberta ou movimento)' : ''}.';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget title(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Text(t, style: theme.textTheme.titleSmall));
    final pp = _processPreview;
    final sp = _stalePreview;
    return AlertDialog(
      title: const Text('Limpeza do legado'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Ordens de fabricação vindas do sistema antigo distorcem o Painel, o PCP e os avisos. Cada ação mostra uma prévia antes de mudar algo.'),
              title('1. Processo nas OFs sem processo'),
              const Text('Escreve o processo sugerido (perfilar, trefilar, endireitar e cortar, inspeção) nas OFs ainda não liberadas que estão sem processo.'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(key: const ValueKey('legacy-process-preview'), onPressed: _busy ? null : _previewProcess, child: const Text('Ver quantas')),
                  if (pp != null)
                    if ((pp['matched'] as num) == 0)
                      const Text('Nenhuma OF sem processo.')
                    else
                      FilledButton(key: const ValueKey('legacy-process-apply'), onPressed: _busy ? null : _applyProcess, child: Text('Gerar em ${pp['matched']} OFs')),
                ],
              ),
              title('2. Cancelar OFs antigas sem andamento'),
              const Text('Cancela OFs criadas e nunca liberadas, sem movimento de estoque nem apontamento, com entrega vencida há mais dias que o limite.'),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: TextField(
                      key: const ValueKey('legacy-days'),
                      controller: _days,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Vencidas há (dias)', border: OutlineInputBorder(), isDense: true),
                      onChanged: (_) => setState(() => _stalePreview = null),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('legacy-reason'),
                      controller: _reason,
                      decoration: const InputDecoration(labelText: 'Motivo', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(key: const ValueKey('legacy-stale-preview'), onPressed: _busy || _daysValue < 30 ? null : _previewStale, child: const Text('Ver prévia')),
                  if (_daysValue < 30) Text('Mínimo 30 dias', style: theme.textTheme.bodySmall),
                  if (sp != null)
                    if ((sp['matched'] as num) == 0)
                      const Text('Nenhuma OF atende ao critério.')
                    else
                      FilledButton(
                        key: const ValueKey('legacy-stale-apply'),
                        style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                        onPressed: _busy || _reason.text.trim().isEmpty ? null : _applyStale,
                        child: Text('Cancelar ${sp['matched']} OFs'),
                      ),
                ],
              ),
              if (sp != null && (sp['matched'] as num) > 0 && (sp['sample'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Exemplos: ${(sp['sample'] as List).take(8).join(', ')}…', style: theme.textTheme.bodySmall),
                ),
              if (_message != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_message!, key: const ValueKey('legacy-message'), style: TextStyle(color: theme.colorScheme.primary))),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
