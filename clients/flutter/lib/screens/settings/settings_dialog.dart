import 'package:flutter/material.dart';

import '../../session.dart';
import '../../widgets/discard_guard.dart';
import 'settings_activity.dart';
import 'settings_admin.dart';
import 'settings_notifications.dart';
import 'settings_sections.dart';
import 'settings_widgets.dart';

/// Personal preferences of the signed-in user on this device (not the system parameters under Parâmetros).
/// [section] opens a specific section, for example `'account'`.
Future<void> showUserSettings(BuildContext context, Session session, {String? section}) => showDialog<void>(
  context: context,
  builder: (_) => SettingsDialog(session: session, section: section),
);

class _Section {
  const _Section(this.id, this.icon, this.label, this.build);

  final String id;
  final IconData icon;
  final String label;
  final Widget Function(BuildContext context, Session session, OpenSubView open, VoidCallback signOut) build;
}

final _sections = <_Section>[
  _Section('appearance', Icons.palette_outlined, 'Aparência', (c, s, open, out) => AppearanceSection(session: s)),
  _Section('general', Icons.tune, 'Geral', (c, s, open, out) => GeneralSection(session: s, open: open)),
  _Section('print', Icons.print_outlined, 'Impressão', (c, s, open, out) => PrintSection(session: s)),
  _Section('notifications', Icons.notifications_outlined, 'Notificações', (c, s, open, out) => NotificationsSection(session: s)),
  _Section('account', Icons.person_outline, 'Conta e acesso', (c, s, open, out) => AccountSection(session: s, open: open, onSignOut: out)),
  _Section('activity', Icons.history, 'Minha atividade', (c, s, open, out) => ActivityView(session: s)),
  _Section('data', Icons.storage_outlined, 'Dados e servidor', (c, s, open, out) => DataSection(session: s)),
  _Section('about', Icons.info_outline, 'Sobre', (c, s, open, out) => AboutSection(session: s)),
  _Section('admin', Icons.admin_panel_settings_outlined, 'Administração', (c, s, open, out) => AdminSection(session: s, open: open)),
];

class _SubView {
  const _SubView(this.title, this.builder);

  final String title;
  final WidgetBuilder builder;
}

/// Large two-pane settings window: sections on the left, the chosen section on the right. A button inside a section can open a
/// sub-view in the right pane (with a back arrow) so long tools do not pile up in one scroll.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.session, this.section});

  final Session session;
  final String? section;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  static const _wideFrom = 640.0;

  String? _selected;
  final _subs = <_SubView>[];

  /// Views inside the window (the backup form) register their unsaved-edit check here; every way out goes through [_guard].
  final _dirty = DirtyRegistry();

  List<_Section> get _visible => [
    for (final s in _sections)
      if (s.id != 'admin' || widget.session.isAdmin) s,
  ];

  @override
  void initState() {
    super.initState();
    _selected = _visible.any((s) => s.id == widget.section) ? widget.section : null;
  }

  Future<void> _guard(VoidCallback action) => _dirty.guard(context, () {
    if (mounted) action();
  });

  void _select(String id) => _guard(() {
    setState(() {
      _selected = id;
      _subs.clear();
    });
  });

  void _subBack() => _guard(() => setState(_subs.removeLast));

  void _close() => _guard(() => Navigator.pop(context));

  void _open(String title, WidgetBuilder builder) => setState(() => _subs.add(_SubView(title, builder)));

  void _signOut() {
    Navigator.pop(context);
    widget.session.logout();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 48).clamp(280.0, 1040.0);
    final height = (screen.height - 48).clamp(320.0, 760.0);
    final wide = width >= _wideFrom;
    final selected = wide ? (_selected ?? 'appearance') : _selected;
    return DirtyScope(
      registry: _dirty,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _guard(() {
            if (_subs.isNotEmpty) {
              setState(_subs.removeLast);
            } else if (!wide && _selected != null) {
              setState(() => _selected = null);
            } else {
              Navigator.pop(context);
            }
          });
        },
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: height,
            child: ListenableBuilder(
              listenable: widget.session,
              builder: (context, _) => Column(
                children: [
                  _header(context, wide, selected),
                  const Divider(height: 1),
                  Expanded(
                    child: wide
                        ? Row(
                            children: [
                              SizedBox(width: 220, child: _nav(selected)),
                              const VerticalDivider(width: 1),
                              Expanded(child: _content(context, selected)),
                            ],
                          )
                        : (selected == null ? _nav(null) : _content(context, selected)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, bool wide, String? selected) {
    final theme = Theme.of(context);
    final canGoBack = !wide && selected != null && _subs.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          if (canGoBack)
            IconButton(
              key: const ValueKey('settings-back-to-menu'),
              tooltip: 'Voltar às configurações',
              onPressed: () => _guard(() => setState(() => _selected = null)),
              icon: const Icon(Icons.arrow_back),
            ),
          Expanded(child: Text('Configurações', style: theme.textTheme.titleLarge)),
          IconButton(key: const ValueKey('settings-close'), tooltip: 'Fechar', onPressed: _close, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }

  Widget _nav(String? selected) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
    children: [
      for (final s in _visible)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: ListTile(
            key: ValueKey('settings-nav-${s.id}'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            selected: s.id == selected,
            selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
            selectedColor: Theme.of(context).colorScheme.onSecondaryContainer,
            leading: Icon(s.icon),
            title: Text(s.label),
            onTap: () => _select(s.id),
          ),
        ),
    ],
  );

  Widget _content(BuildContext context, String? selected) {
    final theme = Theme.of(context);
    final section = _visible.firstWhere((s) => s.id == selected, orElse: () => _visible.first);
    final sub = _subs.isEmpty ? null : _subs.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 24, 0),
          child: Row(
            children: [
              if (sub != null)
                IconButton(key: const ValueKey('settings-sub-back'), tooltip: 'Voltar', onPressed: _subBack, icon: const Icon(Icons.arrow_back))
              else
                const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sub == null ? section.label : sub.title,
                  key: const ValueKey('settings-title'),
                  style: theme.textTheme.headlineSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: KeyedSubtree(
                  key: ValueKey('${section.id}/${_subs.length}'),
                  child: sub == null ? section.build(context, widget.session, _open, _signOut) : sub.builder(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
