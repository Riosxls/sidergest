import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../api.dart';
import '../../labels.dart';
import '../../session.dart';
import '../../widgets/discard_guard.dart';
import 'settings_widgets.dart';

/// The agent on the server computer must have called in within this time, or the schedule is not being run.
const backupAgentStaleAfter = Duration(minutes: 15);

/// Live progress of a running backup (`progress` in `/api/admin/backup-settings`).
class BackupProgress {
  const BackupProgress({this.running = false, this.percent = 0, this.stage, this.startedAt});

  factory BackupProgress.fromJson(Map<String, dynamic> j) => BackupProgress(
    running: j['running'] == true,
    percent: ((j['percent'] as num?)?.toInt() ?? 0).clamp(0, 100),
    stage: j['stage'] as String?,
    startedAt: j['startedAt'] == null ? null : DateTime.tryParse('${j['startedAt']}')?.toLocal(),
  );

  final bool running;
  final int percent;
  final String? stage;
  final DateTime? startedAt;
}

/// Stage text the agent reports while it stops a run, and the message it leaves when the run was cancelled.
const backupCancellingStage = 'Cancelando...';
const backupCancelledMessage = 'Backup cancelado.';

/// Backup schedule as stored by the server (`/api/admin/backup-settings`).
class BackupSettings {
  BackupSettings({
    this.enabled = false,
    this.frequency = 'Daily',
    this.timeOfDay = '22:00',
    this.weekday = 0,
    this.destination,
    this.keep = 14,
    this.runRequestedAt,
    this.lastRunAt,
    this.lastRunOk,
    this.lastRunMessage,
    this.agentSeenAt,
    this.nextRunAt,
    this.progress,
    this.cancelRequestedAt,
  });

  factory BackupSettings.fromJson(Map<String, dynamic> j) {
    DateTime? when(String key) => j[key] == null ? null : DateTime.tryParse('${j[key]}')?.toLocal();
    final dest = (j['destination'] as String?)?.trim();
    return BackupSettings(
      enabled: j['enabled'] == true,
      frequency: (j['frequency'] as String?) ?? 'Daily',
      timeOfDay: (j['timeOfDay'] as String?) ?? '22:00',
      weekday: (j['weekday'] as num?)?.toInt() ?? 0,
      destination: dest == null || dest.isEmpty ? null : dest,
      keep: (j['keep'] as num?)?.toInt() ?? 14,
      runRequestedAt: when('runRequestedAt'),
      lastRunAt: when('lastRunAt'),
      lastRunOk: j['lastRunOk'] as bool?,
      lastRunMessage: j['lastRunMessage'] as String?,
      agentSeenAt: when('agentSeenAt'),
      nextRunAt: when('nextRunAt'),
      progress: j['progress'] is Map<String, dynamic> ? BackupProgress.fromJson(j['progress'] as Map<String, dynamic>) : null,
      cancelRequestedAt: when('cancelRequestedAt'),
    );
  }

  final bool enabled;
  final String frequency;
  final String timeOfDay;
  final int weekday;
  final String? destination;
  final int keep;
  final DateTime? runRequestedAt;
  final DateTime? lastRunAt;
  final bool? lastRunOk;
  final String? lastRunMessage;
  final DateTime? agentSeenAt;
  final DateTime? nextRunAt;
  final BackupProgress? progress;
  final DateTime? cancelRequestedAt;

  bool get running => progress?.running ?? false;

  /// A stop was asked for the current run and the agent has not finished stopping it.
  bool get cancelling {
    if (progress?.stage == backupCancellingStage) return true;
    final asked = cancelRequestedAt;
    if (asked == null) return false;
    final since = progress?.startedAt ?? runRequestedAt;
    return since == null || asked.isAfter(since);
  }

  /// The last run ended because someone interrupted it (not a failure).
  bool get cancelled => lastRunOk == false && lastRunMessage == backupCancelledMessage;

  /// A "backup now" request the host agent has not picked up yet.
  bool get waiting => runRequestedAt != null && (lastRunAt == null || runRequestedAt!.isAfter(lastRunAt!)) && !running;

  /// Body of the PUT: only what the admin edits.
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'frequency': frequency,
    'timeOfDay': timeOfDay,
    'weekday': weekday,
    'destination': destination,
    'keep': keep,
  };

  bool get agentMissing => agentSeenAt == null || DateTime.now().difference(agentSeenAt!) > backupAgentStaleAfter;

  /// The agent did not call in during the last 2 minutes (it polls every few seconds).
  bool get agentSilent => agentSeenAt == null || DateTime.now().difference(agentSeenAt!) > const Duration(minutes: 2);
}

/// Admin view to configure the automatic database backup.
class BackupSettingsView extends StatelessWidget {
  const BackupSettingsView({super.key, required this.session, this.pickFolder, this.canBrowse});

  final Session session;

  /// Opens the folder dialog at the given folder (when known); a null result means cancelled. Defaults to the system dialog (injectable for tests).
  final Future<String?> Function(String? initialDirectory)? pickFolder;

  /// Whether the "Procurar" button shows. Defaults to Windows desktop only: on web and Android the chosen path
  /// would not be a path on the server computer.
  final bool? canBrowse;

  @override
  Widget build(BuildContext context) => LoadView<BackupSettings>(
    load: () async => BackupSettings.fromJson(await session.api.get('/api/admin/backup-settings') as Map<String, dynamic>),
    builder: (context, data, reload) => _BackupForm(session: session, initial: data, pickFolder: pickFolder, canBrowse: canBrowse),
  );
}

class _BackupForm extends StatefulWidget {
  const _BackupForm({required this.session, required this.initial, this.pickFolder, this.canBrowse});

  final Session session;
  final BackupSettings initial;
  final Future<String?> Function(String? initialDirectory)? pickFolder;
  final bool? canBrowse;

  @override
  State<_BackupForm> createState() => _BackupFormState();
}

class _BackupFormState extends State<_BackupForm> {
  /// Last saved values: the baseline for unsaved-edit detection.
  late BackupSettings _saved = widget.initial;

  /// Latest server answer, for the status block.
  late BackupSettings _status = widget.initial;
  late bool _enabled = _saved.enabled;
  late String _frequency = _saved.frequency;
  late String _time = _saved.timeOfDay;
  late int _weekday = _saved.weekday;
  late final _destination = TextEditingController(text: _saved.destination ?? '');
  late final _keep = TextEditingController(text: '${_saved.keep}');
  bool _busy = false;

  Timer? _poll;

  /// Slow refresh while nothing is running, so a view left open notices the agent and finished backups.
  Timer? _idle;
  bool _reloading = false;
  int _ticks = 0;
  int _waitTicks = 0;
  bool _polling = false;

  bool get _active => _status.waiting || _status.running;

  bool get _canBrowse => widget.canBrowse ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);

  Future<void> _browse() async {
    try {
      final typed = _destination.text.trim();
      final start = typed.isNotEmpty ? typed : _saved.destination;
      final picked = await (widget.pickFolder ?? (d) => FilePicker.getDirectoryPath(dialogTitle: 'Escolha a pasta de destino do backup', initialDirectory: d))(
        start,
      );
      if (picked == null || picked.trim().isEmpty || !mounted) return;
      final wasDirty = _dirty();
      setState(() => _destination.text = picked.trim());
      // A lone folder pick is saved at once, so it is not lost when the user goes straight to "Fazer backup agora".
      if (!wasDirty) await _save(done: 'Pasta de destino salva.');
    } catch (e) {
      if (mounted) _tell(friendlyError(e));
    }
  }

  @override
  void initState() {
    super.initState();
    _syncPolling();
    _startIdle();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _idle?.cancel();
    _destination.dispose();
    _keep.dispose();
    super.dispose();
  }

  void _syncPolling() {
    if (_active && _poll == null) {
      _ticks = 0;
      _waitTicks = 0;
      _idle?.cancel();
      _idle = null;
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
    _startIdle();
  }

  void _startIdle() {
    if (_poll != null || _idle != null) return;
    _idle = Timer.periodic(const Duration(seconds: 10), (_) => _reload());
  }

  /// Silent reload: refreshes the status and, when the form has no unsaved edits, the editable fields too.
  /// Errors are only logged; the last known state stays.
  Future<void> _reload() async {
    if (_reloading || _busy || _poll != null) return;
    _reloading = true;
    try {
      final res = BackupSettings.fromJson(await widget.session.api.get('/api/admin/backup-settings') as Map<String, dynamic>);
      if (!mounted || _busy) return;
      final clean = !_dirty();
      final wasActive = _active;
      setState(() {
        _status = res;
        if (clean) {
          _saved = res;
          _enabled = res.enabled;
          _frequency = res.frequency;
          _time = res.timeOfDay;
          _weekday = res.weekday;
          _destination.text = res.destination ?? '';
          _keep.text = '${res.keep}';
        }
      });
      // Fast polling only starts on a transition: after it gave up on a stuck request it stays on the slow refresh.
      if (!wasActive) _syncPolling();
    } catch (e) {
      debugPrint('backup reload failed: $e');
    } finally {
      _reloading = false;
    }
  }

  Future<void> _tick() async {
    if (_polling) return;
    _polling = true;
    try {
      if (++_ticks > 600) {
        _stopPolling();
        if (mounted) setState(() {});
        return;
      }
      final res = BackupSettings.fromJson(await widget.session.api.get('/api/admin/backup-settings') as Map<String, dynamic>);
      if (!mounted) return;
      final wasActive = _active;
      setState(() {
        _status = res;
        _waitTicks = res.waiting ? _waitTicks + 1 : 0;
      });
      if (wasActive && !_active) {
        _stopPolling();
        _tellResult(res);
      }
    } catch (e) {
      debugPrint('backup poll failed: $e');
    } finally {
      _polling = false;
    }
  }

  void _tellResult(BackupSettings res) {
    if (res.cancelled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup interrompido.')));
      return;
    }
    final ok = res.lastRunOk != false;
    final text = (res.lastRunMessage?.isNotEmpty ?? false) ? res.lastRunMessage! : (ok ? 'Backup concluído' : 'Backup falhou');
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: ok ? null : TextStyle(color: scheme.onError)),
        backgroundColor: ok ? null : scheme.error,
      ),
    );
  }

  /// The agent had over a minute to react and has not called in lately.
  bool get _agentLate => _status.agentMissing || (_waitTicks > 60 && _status.agentSilent);

  BackupSettings _edited() => BackupSettings(
    enabled: _enabled,
    frequency: _frequency,
    timeOfDay: _time,
    weekday: _weekday,
    destination: _destination.text.trim().isEmpty ? null : _destination.text.trim(),
    keep: int.tryParse(_keep.text.trim()) ?? 0,
  );

  bool _dirty() {
    final e = _edited();
    return e.enabled != _saved.enabled ||
        e.frequency != _saved.frequency ||
        e.timeOfDay != _saved.timeOfDay ||
        e.weekday != _saved.weekday ||
        e.destination != _saved.destination ||
        e.keep != _saved.keep;
  }

  void _tell(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<bool> _call(Future<dynamic> Function() send, String done, {bool isSave = false}) async {
    var ok = false;
    setState(() => _busy = true);
    try {
      final res = BackupSettings.fromJson(await send() as Map<String, dynamic>);
      if (!mounted) return false;
      setState(() {
        _status = res;
        if (isSave) _saved = res;
      });
      _syncPolling();
      if (done.isNotEmpty) _tell(done);
      ok = true;
    } catch (e) {
      if (mounted) _tell(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return ok;
  }

  Future<bool> _save({String done = 'Configuração salva'}) {
    final keep = int.tryParse(_keep.text.trim());
    if (keep == null || keep < 1 || keep > 365) {
      _tell('Informe de 1 a 365 cópias para guardar.');
      return Future.value(false);
    }
    return _call(() => widget.session.api.put('/api/admin/backup-settings', _edited().toJson()), done, isSave: true);
  }

  /// Saves pending edits first (the run uses the stored plan), then asks for the backup.
  Future<void> _runNow() async {
    final savedFirst = _dirty();
    if (savedFirst && !await _save(done: '')) return;
    if (!mounted) return;
    await _call(
      () => widget.session.api.post('/api/admin/backup-settings/run-now', <String, dynamic>{}),
      '${savedFirst ? 'Alterações salvas. ' : ''}Pedido enviado. O backup começa em instantes.',
    );
  }

  Future<void> _cancel() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Interromper o backup?'),
        content: const Text('O backup em andamento será cancelado e o arquivo parcial descartado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Continuar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Interromper')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final ok = await _call(() => widget.session.api.post('/api/admin/backup-settings/cancel', <String, dynamic>{}), 'Interrompendo o backup...');
    // A request that had not started is dropped at once: nothing is left to poll for.
    if (ok && mounted && !_active && _poll != null) _stopPolling();
  }

  Future<void> _pickTime() async {
    final parts = _time.split(':');
    final initial = TimeOfDay(hour: int.tryParse(parts.first) ?? 22, minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null) return;
    setState(() => _time = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) => DiscardGuard(
    isDirty: _dirty,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_agentLate) const _AgentWarning(),
        _BackupStatusBlock(settings: _status, onRefresh: _reload),
        if (_active) _BackupProgressBar(settings: _status),
        const SizedBox(height: 16),
        SwitchListTile(
          key: const ValueKey('backup-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Backup automático'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const SizedBox(height: 8),
        _scheduleFields(),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('backup-destination'),
          controller: _destination,
          decoration: InputDecoration(
            labelText: 'Pasta ou unidade de destino da cópia',
            helperText:
                'Ex.: D:\\backups\\metagest ou \\\\servidor\\backups. Vazio = só guarda no computador do servidor.'
                '${_canBrowse ? ' A pasta vale para este computador; ela precisa existir no computador do servidor.' : ''}',
            helperMaxLines: 4,
            border: const OutlineInputBorder(),
            suffixIcon: _canBrowse
                ? IconButton(
                    key: const ValueKey('backup-pick-folder'),
                    tooltip: 'Procurar pasta',
                    icon: const Icon(Icons.folder_open),
                    onPressed: _busy ? null : _browse,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('backup-keep'),
          controller: _keep,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Quantas cópias guardar', helperText: 'De 1 a 365', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('backup-save'),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar'),
            ),
            Tooltip(
              message: _active ? 'Backup em andamento' : '',
              child: OutlinedButton.icon(
                key: const ValueKey('backup-run-now'),
                onPressed: _busy || _active ? null : _runNow,
                icon: const Icon(Icons.backup_outlined),
                label: Text(_active ? 'Backup em andamento' : 'Fazer backup agora'),
              ),
            ),
            if (_active)
              OutlinedButton.icon(
                key: const ValueKey('backup-cancel'),
                onPressed: _busy || _status.cancelling ? null : _cancel,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(_status.cancelling ? 'Interrompendo...' : 'Interromper'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _scheduleFields() => Wrap(
    spacing: 16,
    runSpacing: 16,
    children: [
      SizedBox(
        width: 240,
        child: DropdownButtonFormField<String>(
          key: const ValueKey('backup-frequency'),
          initialValue: _frequency,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Frequência', border: OutlineInputBorder()),
          items: [for (final e in backupFrequencyLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _frequency = v ?? _frequency),
        ),
      ),
      if (_frequency == 'Weekly')
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<int>(
            key: const ValueKey('backup-weekday'),
            initialValue: _weekday,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Dia da semana', border: OutlineInputBorder()),
            items: [for (var i = 0; i < weekdayNames.length; i++) DropdownMenuItem(value: i, child: Text(weekdayNames[i]))],
            onChanged: (v) => setState(() => _weekday = v ?? _weekday),
          ),
        ),
      if (_frequency == 'Daily' || _frequency == 'Weekly')
        SizedBox(
          width: 160,
          child: InkWell(
            key: const ValueKey('backup-time'),
            onTap: _pickTime,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Horário', border: OutlineInputBorder(), suffixIcon: Icon(Icons.schedule)),
              child: Text(_time),
            ),
          ),
        ),
    ],
  );
}

class _BackupProgressBar extends StatelessWidget {
  const _BackupProgressBar({required this.settings});

  final BackupSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = settings.progress;
    final running = settings.running && p != null;
    return Semantics(
      label: 'Progresso do backup',
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(key: const ValueKey('backup-progress'), value: running ? p.percent / 100 : null),
                ),
                if (running) ...[
                  const SizedBox(width: 12),
                  Text(
                    '${p.percent}%',
                    key: const ValueKey('backup-progress-percent'),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            if (!running)
              Text('Aguardando o programa de backup…', style: theme.textTheme.bodySmall)
            else if (p.stage != null && p.stage!.isNotEmpty)
              Text(p.stage!, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _AgentWarning extends StatelessWidget {
  const _AgentWarning();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('backup-agent-warning'),
      color: theme.colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'O programa que executa os backups no computador não está ativo. Rode scripts\\install-backup-agent.ps1 uma vez.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupStatusBlock extends StatelessWidget {
  const _BackupStatusBlock({required this.settings, required this.onRefresh});

  final BackupSettings settings;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = settings;
    final (IconData icon, Color color, String headline) = s.lastRunAt == null
        ? (Icons.info_outline, theme.colorScheme.onSurfaceVariant, 'Nenhum backup automático executado ainda')
        : s.cancelled
        ? (Icons.info_outline, theme.colorScheme.onSurfaceVariant, 'Interrompido em ${formatMoment(s.lastRunAt!)}')
        : s.lastRunOk == false
        ? (Icons.error_outline, theme.colorScheme.error, 'Último backup falhou em ${formatMoment(s.lastRunAt!)}')
        : (Icons.check_circle_outline, theme.colorScheme.primary, 'Último backup deu certo em ${formatMoment(s.lastRunAt!)}');
    return Card(
      key: const ValueKey('backup-status-block'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(child: Text(headline, style: theme.textTheme.titleSmall)),
                IconButton(key: const ValueKey('backup-refresh'), tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: onRefresh),
              ],
            ),
            if (s.lastRunMessage != null && s.lastRunMessage!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.lastRunMessage!)),
            const SizedBox(height: 6),
            Text(s.enabled && s.nextRunAt != null ? 'Próximo: ${formatMoment(s.nextRunAt!)}' : 'Próximo: nenhum agendado', style: theme.textTheme.bodySmall),
            if (s.waiting) Text('Pedido de backup agora aguardando: ${formatMoment(s.runRequestedAt!)}', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
