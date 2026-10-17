import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'config_builder.dart';

class MihomoApi {
  MihomoApi({required this.port, required this.secret});

  final int port;
  final String secret;
  final http.Client _client = http.Client();
  static const MethodChannel _native = MethodChannel('dev.crew.crew/vpn');
  bool get _useNativeBridge => Platform.isAndroid;

  Future<dynamic> _androidAction(String method, [String? data]) async {
    final result = await _native.invokeMethod<dynamic>('mihomoAction', {
      'method': method,
      if (data != null) 'data': data,
    });
    return result;
  }

  Uri _uri(String path, [Map<String, String>? query]) => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: port,
    path: path,
    queryParameters: query,
  );

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $secret',
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final res = await _client
        .get(_uri(path, query), headers: _headers)
        .timeout(timeout);
    if (res.statusCode >= 400) {
      throw MihomoApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<String> version() async {
    if (_useNativeBridge) {
      final initialized = await _androidAction('getIsInit');
      if (initialized != true) {
        throw StateError('Встроенное ядро Mihomo ещё не инициализировано.');
      }
      return 'embedded-mihomo';
    }
    final j = await _getJson('/version', timeout: const Duration(seconds: 1));
    return j['version']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> proxies() async {
    if (_useNativeBridge) {
      final raw = await _androidAction('getProxies');
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      return (decoded['proxies'] as Map).cast<String, dynamic>();
    }
    final j = await _getJson('/proxies');
    return (j['proxies'] as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> connections() async {
    if (_useNativeBridge) {
      final raw = await _androidAction('getConnections');
      final list = jsonDecode(raw as String) as List;
      return [
        for (final item in list)
          if (item is Map) item.cast<String, dynamic>(),
      ];
    }
    final j = await _getJson('/connections');
    final connections = j['connections'];
    if (connections is! List) {
      throw const FormatException('Mihomo /connections response is invalid.');
    }
    return [
      for (final connection in connections)
        if (connection is Map) connection.cast<String, dynamic>(),
    ];
  }

  Future<void> select(String group, String name) async {
    if (_useNativeBridge) {
      await _androidAction(
        'changeProxy',
        jsonEncode({'group-name': group, 'proxy-name': name}),
      );
      return;
    }
    final res = await _client.put(
      _uri('/proxies/${Uri.encodeComponent(group)}'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode >= 400) {
      throw MihomoApiException(res.statusCode, res.body);
    }
  }

  /// Returns delay in ms, or -1 when every test endpoint fails.
  /// A blocked test URL must not make a working proxy look offline.
  Future<int> delay(String name, {int timeoutMs = 5000}) async {
    const testUrls = [
      kTestUrl,
      'https://www.gstatic.com/generate_204',
      'https://connectivitycheck.gstatic.com/generate_204',
      'https://www.google.com/generate_204',
    ];
    // Some networks block individual connectivity-check hosts even when the
    // proxy itself is healthy. Try independent endpoints with bounded timeouts.
    final perAttempt = timeoutMs < 2000 ? timeoutMs : 2000;
    for (final url in testUrls) {
      try {
        if (_useNativeBridge) {
          final result = await _androidAction(
            'testDelay',
            jsonEncode({
              'proxyName': name,
              'testUrl': url,
              'timeout': perAttempt,
            }),
          );
          final delay = (result as num?)?.toInt() ?? -1;
          if (delay > 0) return delay;
        } else {
          final j = await _getJson(
            '/proxies/${Uri.encodeComponent(name)}/delay',
            query: {'url': url, 'timeout': '$perAttempt'},
            timeout: Duration(milliseconds: perAttempt + 1500),
          );
          final delay = (j['delay'] as num?)?.toInt() ?? -1;
          if (delay > 0) return delay;
        }
      } catch (_) {
        // Try the alternate endpoint before declaring the delay unknown.
      }
    }
    return -1;
  }

  Future<Map<String, int>> groupDelay(
    String group, {
    int timeoutMs = 5000,
  }) async {
    try {
      if (_useNativeBridge) {
        final all = await proxies();
        final groupData = all[group];
        final names = groupData is Map && groupData['all'] is List
            ? (groupData['all'] as List).whereType<String>().toList()
            : <String>[];
        final values = await Future.wait(
          names.map((name) async => MapEntry(name, await delay(name, timeoutMs: timeoutMs))),
        );
        return Map.fromEntries(values);
      }
      try {
        final j = await _getJson(
          '/group/${Uri.encodeComponent(group)}/delay',
          query: {'url': kTestUrl, 'timeout': '$timeoutMs'},
          timeout: Duration(milliseconds: timeoutMs + 5000),
        );
        final values = j.map((k, v) => MapEntry(k, (v as num).toInt()));
        if (values.values.any((value) => value > 0)) return values;
      } catch (_) {
        // Retry individual nodes against the alternate test URL below.
      }

      final all = await proxies();
      final groupData = all[group];
      final names = groupData is Map && groupData['all'] is List
          ? (groupData['all'] as List).whereType<String>().where((name) {
              if (name == 'DIRECT' || name == 'REJECT') return false;
              final item = all[name];
              final type = item is Map ? item['type']?.toString() : null;
              return !const {
                'Selector',
                'URLTest',
                'Fallback',
                'LoadBalance',
                'Relay',
              }.contains(type);
            }).toList()
          : <String>[];
      final values = await Future.wait(
        names.map((name) async =>
            MapEntry(name, await delay(name, timeoutMs: timeoutMs))),
      );
      return Map.fromEntries(values);
    } catch (_) {
      return {};
    }
  }

  Future<void> patchConfig(Map<String, dynamic> patch) async {
    if (_useNativeBridge) {
      await _androidAction('updateConfig', jsonEncode(patch));
      return;
    }
    final res = await _client.patch(
      _uri('/configs'),
      headers: _headers,
      body: jsonEncode(patch),
    );
    if (res.statusCode >= 400) {
      throw MihomoApiException(res.statusCode, res.body);
    }
  }

  Future<void> closeConnections() async {
    if (_useNativeBridge) {
      await _androidAction('closeAllConnections');
      return;
    }
    await _client.delete(_uri('/connections'), headers: _headers);
  }

  /// Android uses the embedded JNI bridge because libmihomo-android applies
  /// Mihomo config without starting its standalone HTTP external controller.
  Stream<Map<String, dynamic>> stream(
    String path, [
    Map<String, String>? query,
  ]) async* {
    if (_useNativeBridge) {
      if (path != '/traffic') return;
      while (true) {
        final raw = await _androidAction('getTraffic');
        final value = jsonDecode(raw as String);
        if (value is Map<String, dynamic>) yield value;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    final client = http.Client();
    try {
      final req = http.Request('GET', _uri(path, query))
        ..headers.addAll(_headers);
      final res = await client.send(req);
      yield* res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, dynamic>);
    } finally {
      client.close();
    }
  }

  void close() => _client.close();
}

class MihomoApiException implements Exception {
  MihomoApiException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'mihomo API $status: $body';
}

Future<void> waitForMihomoApi(
  Future<String> Function() version, {
  Duration timeout = const Duration(seconds: 15),
  Duration retryInterval = const Duration(milliseconds: 150),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      await version();
      return;
    } catch (error) {
      lastError = error;
      await Future<void>.delayed(retryInterval);
    }
  }
  throw StateError(
    'Встроенное ядро Mihomo не инициализировалось за ${timeout.inSeconds} секунд'
    '${lastError == null ? '' : ': $lastError'}',
  );
}
