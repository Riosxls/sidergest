import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../session.dart';
import '../../theme_tokens.dart';
import 'settings_backup.dart';
import 'settings_widgets.dart';

/// Poll interval while a restore runs, and how long the screen waits for the system to come back.
const restorePollInterval = Duration(seconds: 2);
const restoreGiveUpAfter = Duration(minutes: 15);

/// Word the admin types before the database is replaced; the server checks it too.
const restoreConfirmWord = 'RESTAURAR';

/// Word the admin types before a backup is deleted; the server checks it too.
const deleteConfirmWord = 'EXCLUIR';

/// The system keeps at most this many backups (server limit for the keep setting).
const maxBackupCopies = 5;

/// Poll interval while a deletion runs, and how long the screen waits for the host agent.
const deletePollInterval = Duration(seconds: 1);
const deleteGiveUpAfter = Duration(seconds: 30);

/// One backup file offered for restore (`items` in `GET /api/admin/backups`).
class RestoreItem {
  const RestoreItem({required this.name, required this.sizeBytes, required this.createdAt, required this.location, required this.hasChecksum});

  factory RestoreItem.fromJson(Map<String, dynamic> j) => RestoreItem(
    name: '${j['name']}',
    sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
    location: (j['location'] as String?) ?? 'local',
    hasChecksum: j['hasChecksum'] != false,
  );

  final String name;
  final int sizeBytes;
  final DateTime createdAt;
  final String location;
  final bool hasChecksum;

  String get sizeLabel => '${(sizeBytes / 1048576).toStringAsFixed(1)} MB';

  String get locationLabel => switch (location) {
    'destination' => 'Na pasta de destino',
    'both' => 'Nos dois',
    _ => 'Neste computador',
  };

  /// Where the file lives, as shown in the delete confirmation.
  String get placeLabel => switch (location) {
    'destination' => 'Na pasta de destino',
    'both' => 'Nos dois lugares',
    _ => 'Neste computador',
  };
}

/// How the last restore ended (`restore.result`).
class RestoreResult {
  const RestoreResult({required this.ok, this.message, this.file, this.safetyDump, this.finishedAt});

  factory RestoreResult.fromJson(Map<String, dynamic> j) => RestoreResult(
    ok: j['ok'] == true,
    message: j['message'] as String?,
    file: j['file'] as String?,
    safetyDump: j['safetyDump'] as String?,
    finishedAt: j['finishedAt'] == null ? null : DateTime.tryParse('${j['finishedAt']}')?.toLocal(),
  );

  final bool ok;
  final String? message;
  final String? file;
  final String? safetyDump;
  final DateTime? finishedAt;
}

/// The restore request and its result (`restore` in `GET /api/admin/backups`).
class RestoreInfo {
  const RestoreInfo({this.requestedAt, this.file, this.result});

  factory RestoreInfo.fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return const RestoreInfo();
    return RestoreInfo(
      requestedAt: j['requestedAt'] == null ? null : DateTime.tryParse('${j['requestedAt']}')?.toLocal(),
      file: j['file'] as String?,
      result: j['result'] is Map<String, dynamic> ? RestoreResult.fromJson(j['result'] as Map<String, dynamic>) : null,
    );
  }

  final DateTime? requestedAt;
  final String? file;
  final RestoreResult? result;

  /// The result belongs to the current request (or there is no request to compare with).
  bool get hasFreshResult {
    final f = result?.finishedAt;
    return f != null && (requestedAt == null || f.isAfter(requestedAt!));
  }

  /// A request was made and has no newer result: the restore is waiting or running.
  bool get pending => requestedAt != null && !hasFreshResult;
}

/// Answer of `/api/admin/backups` and of the restore POSTs.
class BackupCatalog {
  const BackupCatalog({this.items = const [], this.restore = const RestoreInfo(), this.delete = const RestoreInfo()});

  factory BackupCatalog.fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return const BackupCatalog();
    return BackupCatalog(
      items: [for (final e in (j['items'] as List?) ?? const []) RestoreItem.fromJson(e as Map<String, dynamic>)],
      restore: RestoreInfo.fromJson(j['restore']),
      delete: RestoreInfo.fromJson(j['delete']),
    );
  }

  final List<RestoreItem> items;
  final RestoreInfo restore;

  /// The deletion request and its result (same shape as [restore]).
  final RestoreInfo delete;
}

/// "Restaurar backup": list of available backups, confirmation and the waiting screen while the database is replaced.
class RestoreSection extends StatefulWidget {
  const RestoreSection({super.key, required this.session, required this.backupBusy, required this.reloadSignal, required this.onRestoringChanged});

  final Session session;

  /// A backup is requested or running: restoring waits.
  final bool backupBusy;

  /// Changes whenever a backup finishes, so the list reloads.
  final int reloadSignal;

  /// True while a restore is requested or running (the parent hides the schedule form).
  final ValueChanged<bool> onRestoringChanged;

  @override
  State<RestoreSection> createState() => _RestoreSectionState();
}

class _RestoreSectionState extends State<RestoreSection> {
  List<RestoreItem> _items = const [];
  bool _loading = true;
  String? _error;
  String? _selected;

  bool _running = false;
  bool _apiDown = false;
  bool _sawDown = false;
  bool _timedOut = false;
  bool _finishing = false;
  bool _cancelling = false;
  int _ticks = 0;
  BackupProgress? _progress;
  Timer? _timer;
  bool _polling = false;

  bool _deleting = false;
  bool _deleteServerPending = false;
  int _deleteTicks = 0;
  bool _deletePolling = false;
  Timer? _deleteTimer;
  String? _deletingFile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RestoreSection old) {
    super.didUpdateWidget(old);
    if (old.reloadSignal != widget.reloadSignal && !_running) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _deleteTimer?.cancel();
    super.dispose();
  }

  Future<BackupCatalog> _fetch() async => BackupCatalog.fromJson(await widget.session.api.get('/api/admin/backups'));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await _fetch();
      if (!mounted) return;
      setState(() {
        _items = c.items;
        if (_selected != null && !c.items.any((i) => i.name == _selected)) _selected = null;
        _deleteServerPending = c.delete.pending;
      });
      if (c.restore.pending) _enterRunning();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _enterRunning() {
    if (_running) return;
    setState(() {
      _running = true;
      _apiDown = false;
      _sawDown = false;
      _timedOut = false;
      _ticks = 0;
      _progress = null;
    });
    widget.onRestoringChanged(true);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(restorePollInterval, (_) => _tick());
  }

  void _exitRunning() {
    _timer?.cancel();
    _timer = null;
    if (!mounted) return;
    setState(() {
      _running = false;
      _finishing = false;
      _apiDown = false;
    });
    widget.onRestoringChanged(false);
  }

  Future<void> _tick() async {
    if (_polling || _finishing || !_running) return;
    _polling = true;
    try {
      if (++_ticks * restorePollInterval.inSeconds > restoreGiveUpAfter.inSeconds) {
        _timer?.cancel();
        if (mounted) setState(() => _timedOut = true);
        return;
      }
      final catalog = await _fetch();
      final settings = BackupSettings.fromJson(await widget.session.api.get('/api/admin/backup-settings') as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _apiDown = false;
        _items = catalog.items;
        _progress = settings.progress;
      });
      if (catalog.restore.hasFreshResult) {
        await _finish(catalog.restore.result);
      } else if (catalog.restore.requestedAt == null) {
        // The database came back without a request: replaced by the restored one, or the request was dropped.
        if (_sawDown) {
          await _finish(null);
        } else {
          _exitRunning();
          await _load();
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 401) {
        await _finish(null);
      } else if (e.status == 0) {
        setState(() {
          _apiDown = true;
          _sawDown = true;
        });
      } else {
        debugPrint('restore poll failed: $e');
      }
    } catch (e) {
      debugPrint('restore poll failed: $e');
    } finally {
      _polling = false;
    }
  }

  /// The restore ended. [result] null means the API came back with a new database and no verdict (treated as success).
  Future<void> _finish(RestoreResult? result) async {
    if (_finishing || !mounted) return;
    _finishing = true;
    _timer?.cancel();
    final ok = result == null || result.ok;
    final safety = result?.safetyDump;
    final text = ok
        ? 'Backup restaurado. Entre de novo.${safety != null ? '\n\nAntes de restaurar foi guardada uma cópia de segurança: $safety.' : ''}'
        : 'A restauração falhou: ${result.message ?? 'erro desconhecido'}. Os dados atuais foram mantidos.';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        key: ValueKey(ok ? 'restore-done' : 'restore-failed'),
        title: Text(ok ? 'Restauração concluída' : 'Restauração falhou'),
        content: Text(text),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    if (ok) {
      await widget.session.logout();
      if (mounted) _exitRunning();
    } else {
      _exitRunning();
      if (mounted) await _load();
    }
  }

  Future<void> _start() async {
    final item = _items.where((i) => i.name == _selected).firstOrNull;
    if (item == null) return;
    final started = await showDialog<RestoreInfo>(context: context, builder: (_) => _RestoreDialog(session: widget.session, item: item));
    if (started == null || !mounted) return;
    _enterRunning();
  }

  void _toast(String text, {bool error = false}) {
    final m = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? Theme.of(context).colorScheme.error : null));
  }

  Future<void> _askDelete(RestoreItem item) async {
    final latest = _items.every((i) => !i.createdAt.isAfter(item.createdAt));
    final started = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(session: widget.session, item: item, only: _items.length == 1, latest: latest),
    );
    if (started != true || !mounted) return;
    _toast('Excluindo o backup...');
    setState(() {
      _deleting = true;
      _deletingFile = item.name;
      _deleteTicks = 0;
    });
    _deleteTimer?.cancel();
    _deleteTimer = Timer.periodic(deletePollInterval, (_) => _deleteTick());
  }

  void _endDelete() {
    _deleteTimer?.cancel();
    _deleteTimer = null;
    if (mounted) {
      setState(() {
        _deleting = false;
        _deletingFile = null;
      });
    }
  }

  Future<void> _deleteTick() async {
    if (_deletePolling || !_deleting) return;
    _deletePolling = true;
    try {
      if (++_deleteTicks * deletePollInterval.inSeconds > deleteGiveUpAfter.inSeconds) {
        _endDelete();
        if (mounted) _toast('Não foi possível confirmar a exclusão. Atualize a lista.', error: true);
        return;
      }
      final c = await _fetch();
      if (!mounted) return;
      final file = _deletingFile;
      final gone = !c.items.any((i) => i.name == file);
      final fresh = c.delete.hasFreshResult && c.delete.requestedAt != null;
      if (fresh && !(c.delete.result?.ok ?? false)) {
        _endDelete();
        setState(() => _items = c.items);
        _toast(c.delete.result?.message ?? 'Não foi possível excluir o backup.', error: true);
      } else if (fresh || gone) {
        _endDelete();
        setState(() {
          _items = c.items;
          if (_selected == file || (_selected != null && !c.items.any((i) => i.name == _selected))) _selected = null;
          _deleteServerPending = false;
        });
        _toast('Backup excluído.');
      }
    } catch (e) {
      debugPrint('delete poll failed: $e');
    } finally {
      _deletePolling = false;
    }
  }

  Future<void> _cancelRequest() async {
    setState(() => _cancelling = true);
    try {
      await widget.session.api.post('/api/admin/backups/restore/cancel', <String, dynamic>{});
      if (!mounted) return;
      _exitRunning();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) => _running ? _runningView(context) : _listView(context);

  Widget _listView(BuildContext context) {
    final theme = Theme.of(context);
    final canStart = _selected != null && !widget.backupBusy && !_loading && !_deleting;
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('Restaurar backup', style: theme.textTheme.titleMedium)),
              if (!_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('${_items.length} de $maxBackupCopies backups guardados', key: const ValueKey('restore-count'), style: theme.textTheme.bodySmall),
                ),
              IconButton(key: const ValueKey('restore-refresh'), tooltip: 'Atualizar lista', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
            ],
          ),
          Text('Volta o sistema para o estado de um backup. Os dados feitos depois dele são perdidos.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          if (_loading && _items.isEmpty)
            const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
          else if (_error != null)
            Text(_error!, key: const ValueKey('restore-error'), style: TextStyle(color: theme.colorScheme.error))
          else if (_items.isEmpty)
            const Text('Nenhum backup encontrado. Faça um backup primeiro.', key: ValueKey('restore-empty'))
          else
            Card(
              key: const ValueKey('restore-list'),
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(children: [for (final i in _items) _row(i)]),
            ),
          const SizedBox(height: 12),
          Tooltip(
            message: widget.backupBusy ? 'Há um backup em andamento' : '',
            child: FilledButton.icon(
              key: const ValueKey('restore-start'),
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
              onPressed: canStart ? _start : null,
              icon: const Icon(Icons.restore),
              label: const Text('Restaurar este backup…'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(RestoreItem i) {
    final theme = Theme.of(context);
    final on = _selected == i.name;
    return ListTile(
      key: ValueKey('restore-item-${i.name}'),
      selected: on,
      leading: Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked),
      title: Text('${formatMoment(i.createdAt)}  ·  ${i.sizeLabel}'),
      subtitle: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(i.name, style: theme.textTheme.bodySmall),
          if (!i.hasChecksum) Text('Sem verificação', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Chip(label: Text(i.locationLabel), visualDensity: VisualDensity.compact),
          IconButton(
            key: ValueKey('delete-${i.name}'),
            tooltip: 'Excluir este backup',
            icon: const Icon(Icons.delete_outline),
            onPressed: widget.backupBusy || _deleting || _deleteServerPending ? null : () => _askDelete(i),
          ),
        ],
      ),
      onTap: () => setState(() => _selected = i.name),
    );
  }

  Widget _runningView(BuildContext context) {
    final theme = Theme.of(context);
    final p = _progress;
    final live = !_apiDown && p != null && p.running;
    final elapsed = Duration(seconds: _ticks * restorePollInterval.inSeconds);
    String two(int n) => n.toString().padLeft(2, '0');
    final clock = '${two(elapsed.inMinutes)}:${two(elapsed.inSeconds % 60)}';
    final canCancel = !_apiDown && !_sawDown && !live && !_timedOut;
    final String detail;
    if (_timedOut) {
      detail = 'A restauração está demorando mais do que o esperado. Confira o computador do servidor.';
    } else if (_apiDown) {
      detail = 'O sistema está reiniciando…';
    } else if (live && (p.stage?.isNotEmpty ?? false)) {
      detail = p.stage!;
    } else {
      detail = 'Aguardando o programa de backup iniciar a restauração…';
    }
    return Card(
      key: const ValueKey('restore-running'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Restaurando…', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (!_timedOut) LinearProgressIndicator(key: const ValueKey('restore-progress'), value: live ? p.percent / 100 : null),
            const SizedBox(height: 8),
            Text(detail, key: const ValueKey('restore-stage')),
            if (!_timedOut) Text('Tempo decorrido: $clock', key: const ValueKey('restore-elapsed'), style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text('Não desligue o computador do servidor. Esta tela volta ao normal sozinha quando terminar.', style: theme.textTheme.bodySmall),
            if (canCancel || _timedOut) const SizedBox(height: 12),
            if (canCancel)
              OutlinedButton(key: const ValueKey('restore-cancel'), onPressed: _cancelling ? null : _cancelRequest, child: const Text('Cancelar pedido')),
            if (_timedOut)
              OutlinedButton(
                key: const ValueKey('restore-recheck'),
                onPressed: () {
                  setState(() {
                    _timedOut = false;
                    _ticks = 0;
                  });
                  _startTimer();
                },
                child: const Text('Verificar de novo'),
              ),
          ],
        ),
      ),
    );
  }
}

class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog({required this.session, required this.item});

  final Session session;
  final RestoreItem item;

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  final _confirm = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _confirm.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = BackupCatalog.fromJson(await widget.session.api.post('/api/admin/backups/restore', {'file': widget.item.name, 'confirm': _confirm.text.trim(), 'password': _password.text}));
      if (mounted) Navigator.pop(context, c.restore);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = _confirm.text.trim() == restoreConfirmWord && _password.text.isNotEmpty && !_busy;
    return AlertDialog(
      key: const ValueKey('restore-dialog'),
      title: const Text('Restaurar backup'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                key: const ValueKey('restore-warning'),
                color: cs.errorContainer,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Isto substitui TODOS os dados atuais pelos do backup de ${formatMoment(widget.item.createdAt)}. '
                          'Tudo o que foi feito depois dessa data será perdido. '
                          'O sistema ficará indisponível por alguns minutos e todos precisarão entrar de novo. '
                          'Um backup de segurança é feito antes.',
                          style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('restore-confirm'),
                controller: _confirm,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Digite $restoreConfirmWord para confirmar', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('restore-password'),
                controller: _password,
                obscureText: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Sua senha de administrador', border: OutlineInputBorder(), isDense: true),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, key: const ValueKey('restore-dialog-error'), style: TextStyle(color: cs.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const ValueKey('restore-confirm-run'),
          style: dangerButtonStyle(context),
          onPressed: ok ? _run : null,
          child: const Text('Restaurar agora'),
        ),
      ],
    );
  }
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.session, required this.item, required this.only, required this.latest});

  final Session session;
  final RestoreItem item;
  final bool only;
  final bool latest;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _confirm = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _confirm.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.post('/api/admin/backups/delete', {'file': widget.item.name, 'confirm': _confirm.text, 'password': _password.text});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = _confirm.text == deleteConfirmWord && _password.text.isNotEmpty && !_busy;
    final warn = TextStyle(color: cs.error, fontWeight: FontWeight.w600);
    return AlertDialog(
      key: const ValueKey('delete-dialog'),
      title: const Text('Excluir backup?'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('O backup de ${formatMoment(widget.item.createdAt)} será apagado de forma permanente (${widget.item.placeLabel}). Isto não pode ser desfeito.'),
              if (widget.only) ...[const SizedBox(height: 8), Text('É o único backup guardado. Depois disso você não terá nenhum.', key: const ValueKey('delete-warn-only'), style: warn)],
              if (widget.latest && !widget.only) ...[const SizedBox(height: 8), Text('É o backup mais recente.', key: const ValueKey('delete-warn-latest'), style: warn)],
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('delete-confirm'),
                controller: _confirm,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Digite $deleteConfirmWord para confirmar', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('delete-password'),
                controller: _password,
                obscureText: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Sua senha de administrador', border: OutlineInputBorder(), isDense: true),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, key: const ValueKey('delete-dialog-error'), style: TextStyle(color: cs.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const ValueKey('delete-confirm-run'),
          style: dangerButtonStyle(context),
          onPressed: ok ? _run : null,
          child: const Text('Excluir'),
        ),
      ],
    );
  }
}
