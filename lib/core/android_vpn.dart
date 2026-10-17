import 'package:flutter/services.dart';

import 'async_timeout.dart';

class AndroidVpn {
  AndroidVpn({
    MethodChannel? channel,
    this.validationTimeout = const Duration(seconds: 20),
    this.startTimeout = const Duration(seconds: 40),
    this.stopTimeout = const Duration(seconds: 10),
  }) : _channel = channel ?? const MethodChannel('dev.crew.crew/vpn');

  final MethodChannel _channel;
  final Duration validationTimeout;
  final Duration startTimeout;
  final Duration stopTimeout;

  Future<void> prepare() async {
    await _channel.invokeMethod<bool>('prepareVpn');
  }

  Future<String?> validateConfig(String path) => awaitWithTimeout(
    _channel.invokeMethod<String>('validateConfig', {'path': path}),
    timeout: validationTimeout,
    description: 'Mihomo config validation',
  );

  Future<void> start(String configPath, {required String sessionId}) async {
    try {
      await awaitWithTimeout(
        _channel.invokeMethod<void>('startVpn', {
          'configPath': configPath,
          'sessionId': sessionId,
        }),
        timeout: startTimeout,
        description: 'Mihomo VPN service start',
      );
    } catch (startError) {
      try {
        await stop(sessionId: sessionId);
      } catch (cleanupError) {
        throw StateError('$startError; VPN cleanup failed: $cleanupError');
      }
      rethrow;
    }
  }

  Future<void> stop({required String sessionId}) => awaitWithTimeout(
    _channel.invokeMethod<void>('stopVpn', {'sessionId': sessionId}),
    timeout: stopTimeout,
    description: 'Mihomo VPN service stop',
  );
}
