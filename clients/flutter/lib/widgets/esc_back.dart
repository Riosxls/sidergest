import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tracks the route stack of a [Navigator] so [EscBack] knows what is on top.
class EscRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  /// The topmost route, or null when nothing was pushed yet.
  Route<dynamic>? get top => _stack.isEmpty ? null : _stack.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _stack[i] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
  }
}

/// Makes Esc go back: pops the top pushed full-screen page (through `maybePop`, so
/// `PopScope` and `DiscardGuard` still ask first). Popups and dialogs keep Flutter's
/// default Esc behavior; the shell and the settings dialog handle their own.
class EscBack extends StatefulWidget {
  const EscBack({super.key, required this.navigatorKey, required this.observer, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final EscRouteObserver observer;
  final Widget child;

  @override
  State<EscBack> createState() => _EscBackState();
}

class _EscBackState extends State<EscBack> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) return false;
    final k = HardwareKeyboard.instance;
    if (k.isControlPressed || k.isAltPressed || k.isShiftPressed || k.isMetaPressed) return false;
    if (widget.observer.top is! PageRoute) return false;
    final nav = widget.navigatorKey.currentState;
    if (nav == null || !nav.canPop()) return false;
    nav.maybePop();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
