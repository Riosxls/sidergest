import 'package:flutter/material.dart';

import '../../api.dart';
import '../../labels.dart';
import '../../session.dart';
import '../../widgets/discard_guard.dart';
import 'settings_widgets.dart';

/// The agent on the server computer must have called in within this time, or the schedule is not being run.
const backupAgentStaleAfter = Duration(minutes: 15);

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

  /// Body of the PUT: only what the admin edits.
  Map<String, dynamic> toJson() => {'enabled': enabled, 'frequency': frequency, 'timeOfDay': timeOfDay, 'weekday': weekday, 'destination': destination, 'keep': keep};

  bool get agentMissing => agentSeenAt == null || DateTime.now().difference(agentSeenAt!) > backupAgentStaleAfter;
}

/// Admin view to configure the automatic database backup.
class BackupSettingsView extends StatelessWidget {
  const BackupSettingsView({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) => LoadView<BackupSettings>(
    load: () async => BackupSettings.fromJson(await session.api.get('/api/admin/backup-settings') as Map<String, dynamic>),
    builder: (context, data, reload) => _BackupForm(session: session, initial: data),
  );
}

class _BackupForm extends StatefulWidget {
  const _BackupForm({required this.session, required this.initial});

  final Session session;
  final BackupSettings initial;

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

  @override
  void dispose() {
    _destination.dispose();
    _keep.dispose();
    super.dispose();
  }

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

  Future<void> _call(Future<dynamic> Function() send, String done, {bool isSave = false}) async {
    setState(() => _busy = true);
    try {
      final res = BackupSettings.fromJson(await send() as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _status = res;
        if (isSave) _saved = res;
      });
      _tell(done);
    } catch (e) {
      if (mounted) _tell(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() {
    final keep = int.tryParse(_keep.text.trim());
    if (keep == null || keep < 1 || keep > 365) {
      _tell('Informe de 1 a 365 cópias para guardar.');
      return Future.value();
    }
    return _call(() => widget.session.api.put('/api/admin/backup-settings', _edited().toJson()), 'Configuração salva', isSave: true);
  }

  Future<void> _runNow() => _call(() => widget.session.api.post('/api/admin/backup-settings/run-now', <String, dynamic>{}), 'Pedido enviado. O backup começa em até 5 minutos.');

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
        if (_status.agentMissing) const _AgentWarning(),
        _BackupStatusBlock(settings: _status),
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
          decoration: const InputDecoration(
            labelText: 'Pasta ou unidade de destino da cópia',
            helperText: 'Ex.: D:\\backups\\metagest ou \\\\servidor\\backups. Vazio = só guarda no computador do servidor.',
            helperMaxLines: 3,
            border: OutlineInputBorder(),
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
            FilledButton.icon(key: const ValueKey('backup-save'), onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('Salvar')),
            OutlinedButton.icon(key: const ValueKey('backup-run-now'), onPressed: _busy ? null : _runNow, icon: const Icon(Icons.backup_outlined), label: const Text('Fazer backup agora')),
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
  const _BackupStatusBlock({required this.settings});

  final BackupSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = settings;
    final (IconData icon, Color color, String headline) = s.lastRunAt == null
        ? (Icons.info_outline, theme.colorScheme.onSurfaceVariant, 'Nenhum backup automático executado ainda')
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
              ],
            ),
            if (s.lastRunMessage != null && s.lastRunMessage!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.lastRunMessage!)),
            const SizedBox(height: 6),
            Text(s.enabled && s.nextRunAt != null ? 'Próximo: ${formatMoment(s.nextRunAt!)}' : 'Próximo: nenhum agendado', style: theme.textTheme.bodySmall),
            if (s.runRequestedAt != null) Text('Pedido de backup agora aguardando: ${formatMoment(s.runRequestedAt!)}', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}