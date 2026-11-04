import 'package:flutter/material.dart';

/// One entry of the notification bell: a [count] of items for the screen [navId], optionally pre-filtered by [filter].
/// [module] is the notification key of the module the alert belongs to (see `alertModuleKey`); the user may silence it.
class AlertInfo {
  const AlertInfo(this.icon, this.label, this.count, this.navId, [this.filter, this.module]);

  final IconData icon;
  final String label;
  final int count;
  final String navId;
  final String? filter;
  final String? module;
}

/// Holds the current alerts; [total] is the sum of all counts shown on the bell. [value] is what the bell shows: alerts of a silenced
/// module are left out of it and counted in [silenced], so the bell can say so instead of dropping them without a trace.
class AlertCenter extends ValueNotifier<List<AlertInfo>> {
  AlertCenter() : super(const []);

  List<AlertInfo> _all = const [];
  Set<String> _mutedModules = const {};
  int _silenced = 0;

  int get total => value.fold(0, (n, a) => n + a.count);

  /// Alert lines left out of the bell because their module is silenced.
  int get silenced => _silenced;

  /// Replaces the alerts (every one, silenced or not) and/or the silenced modules, then refreshes what the bell shows.
  void update({List<AlertInfo>? all, Set<String>? muted}) {
    if (all != null) _all = all;
    if (muted != null) _mutedModules = muted;
    final shown = [
      for (final a in _all)
        if (a.module == null || !_mutedModules.contains(a.module)) a,
    ];
    _silenced = _all.length - shown.length;
    // The listeners must hear a change in [silenced] even when the visible list is identical.
    value = shown;
    notifyListeners();
  }

  /// Forgets every alert (sign-out).
  void clear() {
    _all = const [];
    _silenced = 0;
    value = const [];
  }
}

/// App bar bell that lists the alerts of [center] and calls [onNavigate] with the chosen screen and filter.
class AlertBell extends StatelessWidget {
  const AlertBell({super.key, required this.center, required this.onNavigate, this.onOpenPrefs});

  final AlertCenter center;
  final void Function(String id, [String? filter]) onNavigate;

  /// Opens the notification preferences; the "silenced alerts" line of the menu goes there.
  final VoidCallback? onOpenPrefs;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<AlertInfo>>(
    valueListenable: center,
    builder: (context, alerts, _) {
      final total = center.total;
      return PopupMenuButton<AlertInfo>(
        tooltip: total == 0 ? 'Notificações' : 'Notificações ($total)',
        offset: const Offset(0, 44),
        onSelected: (a) => onNavigate(a.navId, a.filter),
        itemBuilder: (_) => [
            if (alerts.isEmpty) const PopupMenuItem<AlertInfo>(enabled: false, child: Text('Nenhum alerta')),
            ...[
                for (final a in alerts)
                  PopupMenuItem<AlertInfo>(
                    value: a,
                    child: Row(
                      children: [
                        Icon(a.icon, size: 20, color: a.count > 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(child: Text(a.label)),
                        const SizedBox(width: 16),
                        Text('${a.count}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            if (center.silenced > 0)
              PopupMenuItem<AlertInfo>(
                key: const ValueKey('bell-silenced'),
                onTap: onOpenPrefs,
                child: Row(
                  children: [
                    Icon(Icons.notifications_off_outlined, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${center.silenced} ${center.silenced == 1 ? 'alerta silenciado' : 'alertas silenciados'}')),
                  ],
                ),
              ),
          ],
        child: Semantics(
          label: total == 0 ? 'Notificações, nenhum alerta' : 'Notificações, $total alertas',
          button: true,
          excludeSemantics: true,
          child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(child: Padding(
          padding: const EdgeInsets.all(8),
          child: Badge(
            isLabelVisible: total > 0,
            label: Text(total > 99 ? '99+' : '$total'),
            child: Icon(total > 0 ? Icons.notifications_active_outlined : Icons.notifications_none),
          ),
        ))),
        ),
      );
    },
  );
}
