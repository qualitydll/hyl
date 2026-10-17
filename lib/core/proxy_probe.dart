import 'dart:async';
import 'dart:io';

import 'link_parser.dart';

class ProxyEndpoint {
  const ProxyEndpoint({
    required this.name,
    required this.host,
    required this.port,
  });

  final String name;
  final String host;
  final int port;
}

class ProxyReachability {
  const ProxyReachability({
    required this.endpoint,
    required this.isReachable,
  });

  final ProxyEndpoint endpoint;
  final bool isReachable;
}

List<ProxyEndpoint> proxyEndpoints(ParsedSubscription subscription) {
  final raw = subscription.clashConfig?['proxies'];
  final proxies = raw is List
      ? raw.whereType<Map>().map((proxy) => proxy.cast<String, dynamic>())
      : subscription.proxies;
  return proxies.map(_endpoint).whereType<ProxyEndpoint>().toList();
}

ProxyEndpoint? _endpoint(Map<String, dynamic> proxy) {
  final host = proxy['server']?.toString().trim() ?? '';
  final portValue = proxy['port'];
  final port = portValue is num
      ? portValue.toInt()
      : int.tryParse(portValue?.toString() ?? '');
  if (host.isEmpty || port == null || port < 1 || port > 65535) return null;
  return ProxyEndpoint(
    name: proxy['name']?.toString().trim().isNotEmpty == true
        ? proxy['name'].toString()
        : '$host:$port',
    host: host,
    port: port,
  );
}

Future<bool> probeProxyEndpoint(
  ProxyEndpoint endpoint, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  Socket? socket;
  try {
    socket = await Socket.connect(
      endpoint.host,
      endpoint.port,
      timeout: timeout,
    );
    return true;
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  } finally {
    socket?.destroy();
  }
}

Future<List<ProxyReachability>> probeProxyEndpoints(
  List<ProxyEndpoint> endpoints, {
  int concurrency = 8,
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (concurrency < 1) throw ArgumentError.value(concurrency, 'concurrency');
  final results = <ProxyReachability>[];
  for (var start = 0; start < endpoints.length; start += concurrency) {
    final batch = endpoints.skip(start).take(concurrency);
    results.addAll(
      await Future.wait([
        for (final endpoint in batch)
          probeProxyEndpoint(endpoint, timeout: timeout).then(
            (reachable) => ProxyReachability(
              endpoint: endpoint,
              isReachable: reachable,
            ),
          ),
      ]),
    );
  }
  return results;
}
