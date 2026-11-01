import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../session.dart';

/// Signs the user out after [Session.idleLockMinutes] without a click, scroll or key press (0 never).
class IdleGuard extends StatefulWidget {
  const IdleGuard({super.key, required this.session, required this.child, this.checkEvery = const Duration(seconds: 20), this.now = DateTime.now});

  final Session session;
  final Widget child;
  final Duration checkEvery;

  /// The clock; tests pass their own.
  final DateTime Function() now;

  @override
  State<IdleGuard> createState() => _IdleGuardState();
}

class _IdleGuardState extends State<IdleGuard> {
  late DateTime _last = widget.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _timer = Timer.periodic(widget.checkEvery, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent _) {
    _touch();
    return false;
  }

  void _touch() => _last = widget.now();

  void _check() {
    final s = widget.session;
    if (!s.loggedIn || s.idleLockMinutes <= 0) return _touch();
    if (widget.now().difference(_last) >= Duration(minutes: s.idleLockMinutes)) {
      _touch();
      s.idleSignedOut = true;
      s.logout();
    }
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
