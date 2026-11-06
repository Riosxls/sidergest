import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart' show fmtNum;
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/responsive.dart';
import 'price_simulator.dart' show monthYear;

/// How the import button asks for the CSV of old process sheets; tests replace it (the system file dialog does not run there).
Future<({String name, Uint8List bytes})?> Function() processTemplateFilePicker = pickProcessTemplateFile;

/// Lets the admin choose the CSV exported from the old process spreadsheets.
Future<({String name, Uint8List bytes})?> pickProcessTemplateFile() async {
  final files = await FilePicker.pickFiles(dialogTitle: 'Importar modelos de processo', type: FileType.custom, allowedExtensions: const ['csv', 'txt']);
  if (files.isEmpty) return null;
  final f = files.first;
  return (name: f.name, bytes: await f.readAsBytes());
}

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
  Map<String, dynamic>? _completePreview;
  Map<String, dynamic>? _templates;
  bool _templatesLoaded = false;
  String? _message;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    try {
      final s = await widget.session.api.get('/api/production/process-templates/summary');
      if (mounted) setState(() => _templates = s is Map<String, dynamic> ? s : null);
    } catch (_) {
      if (mounted) setState(() => _templates = null);
    } finally {
      if (mounted) setState(() => _templatesLoaded = true);
    }
  }

  Future<void> _previewComplete() => _call('/api/production/orders/bulk/complete-requirements', {'apply': false}, (r) => setState(() => _completePreview = r));

  Future<void> _applyComplete() async {
    final n = _completePreview?['matched'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Completar tolerâncias e máquinas?'),
        content: Text('$n ordens de fabricação ainda não liberadas terão só os campos vazios preenchidos. O que já está escrito não muda.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(key: const ValueKey('confirm-complete-requirements'), onPressed: () => Navigator.pop(c, true), child: const Text('Completar')),
        ],
      ),
    );
    if (ok != true) return;
    await _call('/api/production/orders/bulk/complete-requirements', {'apply': true}, (r) {
      final skipped = (r['skipped'] as num?) ?? 0;
      setState(() {
        _completePreview = null;
        _message = '${r['done']} OFs completadas (${r['operationsFilled'] ?? 0} operações preenchidas)${skipped > 0 ? ' · $skipped puladas' : ''}.';
      });
    });
  }

  Future<void> _importTemplates() async {
    if (_busy) return;
    final file = await processTemplateFilePicker();
    if (file == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final r = await widget.session.api.upload('/api/production/process-templates/import', 'file', file.name, file.bytes);
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(context: context, builder: (_) => _TemplateImportResult(file.name, r is Map<String, dynamic> ? r : const {}));
      await _loadTemplates();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _templatesText() {
    final s = _templates;
    final n = (s?['templates'] as num?)?.toInt() ?? 0;
    if (s == null || n == 0) return 'Nenhum modelo importado ainda. Importe o CSV exportado das planilhas de processo antigas para que a sugestão use o histórico de cada peça.';
    final from = monthYear(s['firstDate']), to = monthYear(s['lastDate']);
    return '${fmtNum(n, 0)} modelos, ${fmtNum((s['operations'] as num?) ?? 0, 0)} operações${from.isEmpty ? '' : ', de $from a $to'}';
  }

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
    final cp = _completePreview;
    return AlertDialog(
      title: const Text('Limpeza do legado'),
      content: SizedBox(
        width: dialogWidth(context, 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
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
                      decoration: InputDecoration(
                        labelText: 'Vencidas há (dias)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        // The limit is shown from the start, not only after a button turns out to be disabled.
                        helperText: _daysValue < 30 ? null : 'Mínimo 30 dias',
                        errorText: _daysValue < 30 ? 'Mínimo 30 dias' : null,
                      ),
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
                  if (sp != null)
                    if ((sp['matched'] as num) == 0)
                      const Text('Nenhuma OF atende ao critério.')
                    else
                      FilledButton(
                        key: const ValueKey('legacy-stale-apply'),
                        style: dangerButtonStyle(context),
                        onPressed: _busy || _reason.text.trim().isEmpty ? null : _applyStale,
                        child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text('Cancelar ${sp['matched']} OFs'),
                      ),
                ],
              ),
              if (sp != null && (sp['matched'] as num) > 0 && (sp['sample'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Exemplos: ${(sp['sample'] as List).take(8).join(', ')}…', style: theme.textTheme.bodySmall),
                ),
              title('3. Completar tolerâncias e máquinas'),
              const Text('Preenche só os campos vazios de tolerância e máquina nas OFs ainda não liberadas, a partir do histórico da peça, e corrige o "Visual/Dimensional" que ficou na coluna de tolerância da inspeção.'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(key: const ValueKey('legacy-complete-preview'), onPressed: _busy ? null : _previewComplete, child: const Text('Ver quantas')),
                  if (cp != null)
                    if ((cp['matched'] as num?) == 0)
                      const Text('Nenhuma OF precisa de complemento.')
                    else
                      FilledButton(key: const ValueKey('legacy-complete-apply'), onPressed: _busy ? null : _applyComplete, child: Text('Completar ${cp['matched']} OFs')),
                ],
              ),
              if (cp != null && (cp['matched'] as num? ?? 0) > 0) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${cp['operationsFilled'] ?? 0} operações a preencher.', key: const ValueKey('legacy-complete-ops'), style: theme.textTheme.bodySmall),
                ),
                if ((cp['sample'] as List? ?? const []).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Exemplos: ${(cp['sample'] as List).take(8).join(', ')}…', style: theme.textTheme.bodySmall),
                  ),
              ],
              title('4. Modelos de processo (planilhas antigas)'),
              const Text('Os processos das planilhas antigas viram modelos por peça e cliente; a sugestão de requisitos e máquinas usa esse histórico.'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_templatesLoaded) Text(_templatesText(), key: const ValueKey('legacy-templates-summary')),
                  OutlinedButton.icon(
                    key: const ValueKey('legacy-templates-import'),
                    onPressed: _busy ? null : _importTemplates,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Importar modelos (CSV)'),
                  ),
                ],
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

/// Result of the import of process templates: the counts and why rows were left out.
class _TemplateImportResult extends StatelessWidget {
  const _TemplateImportResult(this.fileName, this.r);

  final String fileName;
  final Map<String, dynamic> r;

  /// "Motivos: 3 sem medidas válidas, 1 com data inválida", from the server's counts by reason.
  static String skippedText(Object? reasons) {
    if (reasons is! Map) return '';
    const names = {'medidas': 'sem medidas válidas', 'operação': 'sem operação válida', 'data': 'com data inválida'};
    final parts = <String>[];
    for (final e in reasons.entries) {
      final n = e.value is num ? (e.value as num).toInt() : 0;
      if (n > 0) parts.add('${fmtNum(n, 0)} ${names['${e.key}'] ?? 'por ${e.key}'}');
    }
    return parts.isEmpty ? '' : 'Motivos: ${parts.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    final from = monthYear(r['firstDate']), to = monthYear(r['lastDate']);
    final why = skippedText(r['skippedReasons']);
    return AlertDialog(
      title: const Text('Modelos importados'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fileName, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          Text('Linhas lidas: ${fmtNum(n('read'), 0)}'),
          Text('Modelos novos: ${fmtNum(n('templates'), 0)}'),
          Text('Atualizados: ${fmtNum(n('updated'), 0)}'),
          Text('Operações: ${fmtNum(n('operations'), 0)}'),
          Text('Ignoradas: ${fmtNum(n('skipped'), 0)}'),
          if (why.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: Text(why, key: const ValueKey('template-skipped-reasons')),
            ),
          if (from.isNotEmpty) Text('Período: $from a $to'),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
