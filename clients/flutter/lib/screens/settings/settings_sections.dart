import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api.dart';
import '../../prefs.dart';
import '../../session.dart';
import '../../widgets/print_gate.dart';
import '../../widgets/user_settings.dart';
import '../quick_actions_editor.dart';
import '../shell.dart' show homeScreenChoices;
import 'settings_activity.dart';
import 'settings_devices.dart';
import 'settings_shortcuts.dart';
import 'settings_widgets.dart';

/// Settings section: theme, density and text size.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingsGroup(
        title: 'Tema e tamanho',
        children: [
          SettingRow(
            title: 'Tema',
            control: SegmentedButton<ThemeMode>(
              key: const ValueKey('settings-theme'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Sistema')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Claro')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Escuro')),
              ],
              selected: {session.themeMode},
              onSelectionChanged: (s) => session.setThemeMode(s.first),
            ),
          ),
          SettingRow(
            title: 'Densidade',
            subtitle: 'Compacto mostra mais linhas; confortável tem alvos de toque maiores.',
            control: SegmentedButton<bool>(
              key: const ValueKey('settings-density'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.density_small), label: Text('Compacto')),
                ButtonSegment(value: true, icon: Icon(Icons.density_medium), label: Text('Confortável')),
              ],
              selected: {session.comfortable},
              onSelectionChanged: (s) => session.setComfortable(s.first),
            ),
          ),
          SettingRow(
            title: 'Tamanho do texto',
            control: SegmentedButton<double>(
              key: const ValueKey('settings-text-size'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1.0, label: Text('Normal')),
                ButtonSegment(value: 1.15, label: Text('Grande')),
                ButtonSegment(value: 1.3, label: Text('Maior')),
                ButtonSegment(value: 1.5, label: Text('Enorme')),
              ],
              selected: {session.textScale},
              onSelectionChanged: (s) => session.setTextScale(s.first),
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Acessibilidade',
        children: [
          SwitchListTile(
            key: const ValueKey('settings-contrast'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Alto contraste'),
            subtitle: const Text('Cores mais fortes para separar texto, botões e fundos.'),
            value: session.highContrast,
            onChanged: session.setHighContrast,
          ),
          SwitchListTile(
            key: const ValueKey('settings-motion'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Reduzir animações'),
            subtitle: const Text('Troca de tela e janelas aparecem sem transição.'),
            value: session.reduceMotion,
            onChanged: session.setReduceMotion,
          ),
        ],
      ),
    ],
  );
}

/// General settings section.
class GeneralSection extends StatelessWidget {
  const GeneralSection({super.key, required this.session, required this.open});

  final Session session;
  final OpenSubView open;

  @override
  Widget build(BuildContext context) {
    final homes = homeScreenChoices(session);
    final home = homes.any((h) => h.id == session.homeScreen) ? session.homeScreen : 'dashboard';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          title: 'Ao entrar',
          children: [
            SettingRow(
              title: 'Tela inicial',
              subtitle: 'A tela que abre depois do login. O botão de voltar ainda leva ao Painel.',
              control: DropdownMenu<String>(
                key: const ValueKey('settings-home'),
                width: 360,
                menuHeight: 360,
                enableFilter: true,
                requestFocusOnTap: true,
                initialSelection: home,
                dropdownMenuEntries: [for (final h in homes) DropdownMenuEntry(value: h.id, label: h.label)],
                onSelected: (v) {
                  if (v != null) session.setHomeScreen(v);
                },
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Listas e Painel',
          children: [
            SettingRow(
              title: 'Atualização automática do Painel',
              subtitle: 'F5 atualiza na hora, em qualquer opção.',
              control: SegmentedButton<int>(
                key: const ValueKey('settings-refresh'),
                showSelectedIcon: false,
                segments: [for (final m in Session.dashboardRefreshChoices) ButtonSegment(value: m, label: Text(m == 0 ? 'Desligada' : '$m min'))],
                selected: {session.dashboardRefreshMinutes},
                onSelectionChanged: (s) => session.setDashboardRefreshMinutes(s.first),
              ),
            ),
            SettingRow(
              title: 'Linhas por página',
              subtitle: 'Vale para as listas que paginam. Mais linhas pedem mais do servidor.',
              control: SegmentedButton<int>(
                key: const ValueKey('settings-rows'),
                showSelectedIcon: false,
                segments: [for (final r in AppPrefs.rowsPerPageChoices) ButtonSegment(value: r, label: Text('$r'))],
                selected: {session.rowsPerPage},
                onSelectionChanged: (s) => session.setRowsPerPage(s.first),
              ),
            ),
            SettingsLink(
              icon: Icons.bolt_outlined,
              title: 'Atalhos do Painel',
              subtitle: 'Escolha até ${Session.maxQuickActions} atalhos de criação e a ordem deles',
              onTap: () => showQuickActionsEditor(context, session),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Teclado',
          children: [SettingsLink(icon: Icons.keyboard_outlined, title: 'Atalhos de teclado', subtitle: 'Busca rápida, atualizar e navegação', onTap: () => open('Atalhos de teclado', (_) => const ShortcutsView()))],
        ),
      ],
    );
  }
}

/// Settings section: print preferences.
class PrintSection extends StatefulWidget {
  const PrintSection({super.key, required this.session});

  final Session session;

  @override
  State<PrintSection> createState() => _PrintSectionState();
}

class _PrintSectionState extends State<PrintSection> {
  late Future<int> _count = PrintLog.count();

  Future<void> _forget() async {
    await PrintLog.clear();
    if (!mounted) return;
    final count = PrintLog.count();
    setState(() {
      _count = count;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Histórico de impressão esquecido')));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          title: 'Papéis do pedido',
          note:
              'Ao passar de uma etapa, o sistema oferece imprimir ou baixar o papel que ela gerou: pedido de compra do cliente, pedido interno, ordens de fabricação, certificados.',
          children: [
            SwitchListTile(
              key: const ValueKey('settings-print-prompts'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Perguntar antes de seguir sem imprimir'),
              subtitle: Text(s.printPrompts ? 'A pergunta aparece uma vez por papel, neste computador' : 'O fluxo segue direto; imprima pelo painel "Documentos para imprimir"'),
              value: s.printPrompts,
              onChanged: s.setPrintPrompts,
            ),
          ],
        ),
        SettingsGroup(
          title: 'Histórico neste computador',
          children: [
            FutureBuilder<int>(
              future: _count,
              builder: (_, snap) => Text(
                snap.hasData ? (snap.data == 0 ? 'Nenhum papel registrado ainda.' : '${snap.data} papéis já impressos, baixados ou ignorados.') : 'Contando...',
                key: const ValueKey('settings-print-count'),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Esquecer o histórico faz o sistema perguntar de novo, para cada papel, na próxima vez que o pedido passar pela etapa.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(key: const ValueKey('settings-print-forget'), onPressed: _forget, icon: const Icon(Icons.history_toggle_off), label: const Text('Esquecer histórico de impressão')),
          ],
        ),
      ],
    );
  }
}

/// Settings section: profile, password and devices.
class AccountSection extends StatefulWidget {
  const AccountSection({super.key, required this.session, required this.open, required this.onSignOut});

  final Session session;
  final OpenSubView open;
  final VoidCallback onSignOut;

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  late final _name = TextEditingController(text: widget.session.displayName ?? '');
  late final _email = TextEditingController(text: widget.session.email ?? '');
  bool _busy = false;
  String? _error;

  Future<void> _setIdle(int minutes) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final effective = await widget.session.setIdleLockMinutes(minutes);
      if (effective != minutes) {
        final cap = widget.session.maxIdleMinutes;
        messenger.showSnackBar(SnackBar(content: Text(cap > 0 ? 'O administrador limita o bloqueio a $cap minutos.' : 'O servidor aplicou $effective minutos.')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _dirty => _name.text.trim() != (widget.session.displayName ?? '') || _email.text.trim() != (widget.session.email ?? '');

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.saveProfile(displayName: _name.text.trim(), email: _email.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perfil salvo')));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          title: 'Perfil',
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Usuário ${s.username ?? ''}  ·  perfil de acesso ${s.role ?? ''}',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('settings-profile-name'),
                    controller: _name,
                    maxLength: 120,
                    onChanged: (_) => setState(() => _error = null),
                    decoration: const InputDecoration(labelText: 'Nome de exibição', helperText: 'Aparece no menu da conta no lugar do usuário', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('settings-profile-email'),
                    controller: _email,
                    maxLength: 200,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() => _error = null),
                    decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder(), isDense: true),
                  ),
                ],
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
            FilledButton(key: const ValueKey('settings-profile-save'), onPressed: _busy || !_dirty ? null : _save, child: const Text('Salvar perfil')),
          ],
        ),
        SettingsGroup(
          title: 'Acesso',
          children: [
            SwitchListTile(
              key: const ValueKey('settings-remember'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Manter conectado neste dispositivo'),
              subtitle: Text(s.remember ? 'Você continua conectado ao reabrir o aplicativo' : 'A sessão termina ao fechar o aplicativo'),
              value: s.remember,
              onChanged: s.setRemember,
            ),
            const SizedBox(height: 8),
            SettingRow(
              title: 'Desconectar por inatividade',
              subtitle: 'Sem usar o mouse nem o teclado pelo tempo escolhido, a sessão é encerrada (um aviso aparece 1 minuto antes).',
              control: SegmentedButton<int>(
                key: const ValueKey('settings-idle'),
                showSelectedIcon: false,
                segments: [
                  for (final m in s.idleChoices)
                    ButtonSegment(value: m, label: Text(m == 0 ? 'Nunca' : (Session.idleLockChoices.contains(m) ? '$m min' : '$m minutos (limite do administrador)'))),
                ],
                selected: {s.idleLockMinutes},
                onSelectionChanged: (v) => _setIdle(v.first),
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('settings-change-password'),
                  onPressed: () => showChangePassword(context, s),
                  icon: const Icon(Icons.password_outlined),
                  label: const Text('Alterar minha senha…'),
                ),
                OutlinedButton.icon(onPressed: widget.onSignOut, icon: const Icon(Icons.logout), label: const Text('Sair deste dispositivo')),
              ],
            ),
          ],
        ),
        SettingsGroup(
          title: 'Dispositivos',
          children: [
            SettingsLink(
              key: const ValueKey('settings-open-devices'),
              icon: Icons.devices_outlined,
              title: 'Dispositivos conectados',
              subtitle: 'Veja onde você está conectado e desconecte os outros',
              onTap: () => widget.open('Dispositivos conectados', (_) => DevicesView(session: s)),
            ),
            SettingsLink(
              key: const ValueKey('settings-open-activity'),
              icon: Icons.history,
              title: 'Minha atividade',
              subtitle: 'Seus últimos acessos e as alterações feitas com o seu usuário',
              onTap: () => widget.open('Minha atividade', (_) => ActivityView(session: s)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Settings section: data reset (admin).
class DataSection extends StatelessWidget {
  const DataSection({super.key, required this.session});

  final Session session;

  Future<void> _clearCache(BuildContext context) async {
    await clearLocalCache(session);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache do aplicativo limpo')));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingsGroup(
        title: 'Dados do aplicativo',
        note: 'Limpa os nomes e as buscas recentes guardados neste dispositivo. Seus dados no servidor e o login não mudam.',
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('settings-clear-cache'),
              onPressed: () => _clearCache(context),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Limpar cache do aplicativo'),
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Servidor',
        children: [
          SelectableText(session.baseUrl, key: const ValueKey('settings-server')),
          const SizedBox(height: 8),
          const Text('Para trocar de servidor, saia e use "Servidor" na tela de login.'),
        ],
      ),
    ],
  );
}

/// What the server tells about itself; null fields are left out.
class ServerAbout {
  ServerAbout(Map<String, dynamic> j)
    : version = j['version'] as String?,
      runtime = j['runtime'] as String?,
      environment = j['environment'] as String?,
      serverTime = DateTime.tryParse('${j['serverTime'] ?? ''}'),
      timeZone = j['timeZone'] as String?,
      lastMigration = j['lastMigration'] as String?,
      databaseOk = j['databaseOk'] as bool?;

  final String? version, runtime, environment, timeZone, lastMigration;
  final DateTime? serverTime;
  final bool? databaseOk;
}

/// Settings section: app and server version.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key, required this.session});

  final Session session;

  static String diagnostics(Session s, ServerAbout? a) => [
    'MetaGest $appVersion (${Session.deviceLabel})',
    'Servidor: ${s.baseUrl}',
    'Usuário: ${s.username ?? '-'} (${s.role ?? '-'})',
    if (a != null) ...[
      'API: ${a.version ?? '-'} em ${a.runtime ?? '-'} (${a.environment ?? '-'})',
      'Banco: ${a.databaseOk == null ? '-' : (a.databaseOk! ? 'conectado' : 'sem conexão')}, última migração ${a.lastMigration ?? '-'}',
      'Hora do servidor: ${a.serverTime?.toIso8601String() ?? '-'} (${a.timeZone ?? '-'})',
    ] else
      'API: sem resposta',
    'Gerado em ${DateTime.now().toIso8601String()}',
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget line(String label, String? value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          Expanded(child: SelectableText(value ?? '-')),
        ],
      ),
    );
    return LoadView<ServerAbout?>(
      load: () async {
        try {
          return ServerAbout(await session.api.get('/api/system/about') as Map<String, dynamic>);
        } catch (e) {
          debugPrint('settings_sections: lookup failed, using fallback: $e');
          return null;
        }
      },
      builder: (context, about, reload) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsGroup(
            title: 'Aplicativo',
            children: [line('Versão', appVersion), line('Plataforma', Session.deviceLabel), line('Servidor', session.baseUrl)],
          ),
          SettingsGroup(
            title: 'Servidor',
            children: about == null
                ? [const Text('O servidor não respondeu. Confira a conexão e tente de novo.', key: ValueKey('settings-about-offline'))]
                : [
                    line('Versão da API', about.version),
                    line('Ambiente', about.environment),
                    line('Execução', about.runtime),
                    line('Banco de dados', about.databaseOk == null ? null : (about.databaseOk! ? 'Conectado' : 'Sem conexão')),
                    line('Última migração', about.lastMigration),
                    line('Hora do servidor', about.serverTime == null ? null : '${formatMoment(about.serverTime!)}  ${about.timeZone ?? ''}'.trim()),
                  ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('settings-copy-diagnostics'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: diagnostics(session, about)));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diagnóstico copiado')));
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copiar diagnóstico'),
              ),
              OutlinedButton.icon(onPressed: reload, icon: const Icon(Icons.refresh), label: const Text('Atualizar')),
            ],
          ),
          const SizedBox(height: 8),
          Text('Cole o diagnóstico ao relatar um problema; ele não traz senhas nem dados de clientes.', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
