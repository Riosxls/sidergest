import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/services.dart';

import '../session.dart';

/// How long before the idle sign-out the "Sua sessão vai expirar" warning appears.
const idleWarningLead = Duration(seconds: 60);

/// Signs the user out after [Session.idleLockMinutes] without moving the mouse, touching the screen or pressing a key (0 never).
/// [idleWarningLead] before that it asks whether to stay signed in, so unsaved work is not lost without notice.
class IdleGuard extends StatefulWidget {
  const IdleGuard({
    super.key,
    required this.session,
    required this.child,
    this.checkEvery = const Duration(seconds: 5),
    this.now = DateTime.now,
    this.navigatorKey,
  });

  final Session session;
  final Widget child;
  final Duration checkEvery;

  /// The clock; tests pass their own.
  final DateTime Function() now;

  /// The app navigator, when this widget sits above it (the dialog is pushed there). Without it the nearest navigator is used.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<IdleGuard> createState() => _IdleGuardState();
}

class _IdleGuardState extends State<IdleGuard> {
  late DateTime _last;
  Timer? _timer;
  Route<void>? _warning;
  final _secondsLeft = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _last = widget.now();
    HardwareKeyboard.instance.addHandler(_onKey);
    _startTimer(widget.checkEvery);
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _secondsLeft.dispose();
    super.dispose();
  }

  void _startTimer(Duration every) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => _check());
  }

  bool _onKey(KeyEvent _) {
    _touch();
    return false;
  }

  void _touch() {
    // While the warning is up only its own buttons count; moving the mouse must not hide the countdown.
    if (_warning != null) return;
    _last = widget.now();
    widget.session.reportActivity();
  }

  void _stayConnected() {
    _closeWarning();
    _touch();
  }

  void _closeWarning() {
    final route = _warning;
    if (route == null) return;
    _warning = null;
    _startTimer(widget.checkEvery);
    if (route.isActive) route.navigator?.removeRoute(route);
  }

  void _signOutNow() {
    _closeWarning();
    final s = widget.session;
    s.idleSignedOut = true;
    s.logout();
  }

  void _check() {
    final s = widget.session;
    if (!s.loggedIn) {
      _closeWarning();
      return;
    }
    if (s.idleLockMinutes <= 0) {
      _closeWarning();
      return _touch();
    }
    final left = Duration(minutes: s.idleLockMinutes) - widget.now().difference(_last);
    if (left <= Duration.zero) return _signOutNow();
    final secs = (left.inMilliseconds / 1000).ceil();
    _secondsLeft.value = secs;
    // Screen readers do not re-read a changing text, so the countdown is announced at fixed points.
    if (_warning != null && const {60, 30, 10}.contains(secs)) {
      unawaited(SemanticsService.sendAnnouncement(View.of(context), 'Sua sessão expira em $secs segundos.', Directionality.of(context)));
    }
    if (left <= idleWarningLead && _warning == null) _showWarning();
  }

  void _showWarning() {
    final nav = widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);
    if (nav == null) return;
    final route = DialogRoute<void>(
      context: nav.context,
      barrierDismissible: false,
      builder: (_) => _ExpiryDialog(secondsLeft: _secondsLeft, onStay: _stayConnected, onSignOut: _signOutNow),
    );
    _warning = route;
    _startTimer(const Duration(seconds: 1));
    nav.push(route);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _touch(),
    onPointerMove: (_) => _touch(),
    onPointerHover: (_) => _touch(),
    onPointerPanZoomUpdate: (_) => _touch(),
    onPointerSignal: (_) => _touch(),
    child: widget.child,
  );
}

class _ExpiryDialog extends StatelessWidget {
  const _ExpiryDialog({required this.secondsLeft, required this.onStay, required this.onSignOut});

  final ValueListenable<int> secondsLeft;
  final VoidCallback onStay;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) onStay();
    },
    child: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onStay},
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          key: const ValueKey('idle-warning'),
          title: const Text('Sua sessão vai expirar'),
          content: ValueListenableBuilder<int>(
            valueListenable: secondsLeft,
            builder: (_, s, _) => Text(
              'Por inatividade, você será desconectado em $s ${s == 1 ? 'segundo' : 'segundos'}. O rascunho dos formulários abertos será guardado; outras alterações não salvas serão perdidas.',
              key: const ValueKey('idle-countdown'),
            ),
          ),
          actions: [
            TextButton(key: const ValueKey('idle-sign-out'), onPressed: onSignOut, child: const Text('Sair agora')),
            FilledButton(key: const ValueKey('idle-stay'), autofocus: true, onPressed: onStay, child: const Text('Continuar conectado')),
          ],
        ),
      ),
    ),
  );
}
