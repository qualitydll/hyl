import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

/// Debug switch for isolating animation cost: BREW_NO_ANIM=aurora,orb,chart|all
class Motion {
  static final _off = (Platform.environment['BREW_NO_ANIM'] ?? '')
      .split(',')
      .map((e) => e.trim())
      .toSet();

  static bool suspended = false;

  static bool disabled(String name) =>
      _off.contains('all') || _off.contains(name);

  /// Stop periodic UI work while the desktop window is hidden or minimized.
  static void setSuspended(bool value) {
    if (suspended == value) return;
    suspended = value;
    Ambient.instance.setSuspended(value);
  }
}

/// Shared low-rate clock for idle "ambient" motion (background drift, idle orb).
/// Stops while hidden/minimized and when nobody listens.
class Ambient extends ChangeNotifier with WidgetsBindingObserver {
  Ambient._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final instance = Ambient._();

  static const fps = 30;
  static const unfocusedFps = 8;

  AppLifecycleState _life = AppLifecycleState.resumed;
  final _watch = Stopwatch()..start();
  Duration _last = Duration.zero;
  Timer? _timer;
  int _rate = 0;
  int _users = 0;
  bool _suspended = false;

  /// Seconds since previous tick (clamped).
  double dt = 0;

  void retain() {
    _users++;
    _sync();
  }

  void release() {
    if (_users > 0) _users--;
    _sync();
  }

  void setSuspended(bool value) {
    if (_suspended == value) return;
    _suspended = value;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _life = state;
    _sync();
  }

  void _sync() {
    final rate = _suspended || _users <= 0
        ? 0
        : switch (_life) {
            AppLifecycleState.resumed => fps,
            AppLifecycleState.inactive => unfocusedFps,
            _ => 0,
          };
    if (rate == _rate) return;
    _rate = rate;
    _timer?.cancel();
    _timer = null;
    if (rate == 0) return;
    _last = _watch.elapsed;
    _timer = Timer.periodic(Duration(microseconds: 1000000 ~/ rate), (_) {
      final now = _watch.elapsed;
      dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.15);
      _last = now;
      notifyListeners();
    });
  }
}
