import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Result of parsing subscription content.
class ParsedSubscription {
  ParsedSubscription({this.clashConfig, this.proxies = const []});

  /// Full Clash/mihomo config if the subscription was YAML.
  final Map<String, dynamic>? clashConfig;

  /// Proxies parsed from share links (vless://, vmess://, ...).
  final List<Map<String, dynamic>> proxies;

  bool get isEmpty => clashConfig == null && proxies.isEmpty;

  int get proxyCount => clashConfig != null
      ? ((clashConfig!['proxies'] as List?)?.length ?? 0)
      : proxies.length;
}

dynamic yamlToPlain(dynamic node) {
  if (node is YamlMap || node is Map) {
    return <String, dynamic>{
      for (final e in (node as Map).entries)
        e.key.toString(): yamlToPlain(e.value),
    };
  }
  if (node is YamlList || node is List) {
    return [for (final v in node as List) yamlToPlain(v)];
  }
  return node;
}

String? tryDecodeBase64(String input) {
  var s = input
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll('-', '+')
      .replaceAll('_', '/');
  if (s.isEmpty) return null;
  final pad = s.length % 4;
  if (pad == 1) return null;
  if (pad > 0) s += '=' * (4 - pad);
  try {
    return utf8.decode(base64.decode(s), allowMalformed: false);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _tryParseClashConfig(String text) {
  try {
    final doc = yamlToPlain(loadYaml(text));
    // A valid Clash/Mihomo profile may define only groups/rules/providers
    // (for example when every outbound is supplied by proxy-providers). Do not
    // require an inline `proxies` list to recognize a complete profile.
    const configKeys = {
      'proxies',
      'proxy-providers',
      'proxy-groups',
      'rule-providers',
      'rules',
      'mixed-port',
      'port',
      'socks-port',
      'tun',
      'dns',
      'listeners',
      'external-controller',
    };
    if (doc is Map<String, dynamic> &&
        doc.keys.any(configKeys.contains)) {
      return doc;
    }
  } catch (_) {}
  return null;
}

ParsedSubscription parseSubscription(String content) {
  // Some subscription endpoints prepend a UTF-8 BOM. It is harmless for
  // browsers but can prevent YAML/base64 parsing in the app.
  final text = content.replaceFirst('\uFEFF', '').trim();
  if (text.isEmpty) return ParsedSubscription();

  // Try YAML/JSON first because full Mihomo profiles often contain URLs and
  // their rules/providers must survive unchanged.
  final config = _tryParseClashConfig(text);
  if (config != null) return ParsedSubscription(clashConfig: config);

  final directLinks = parseLinks(text);
  if (directLinks.isNotEmpty) {
    return ParsedSubscription(proxies: directLinks);
  }

  // Subscription services commonly return base64-encoded share links. Try
  // decoding after direct parsing too, so harmless wrappers/extra text don't
  // cause an otherwise valid subscription to be rejected.
  final decoded = tryDecodeBase64(text);
  if (decoded != null && decoded.trim().isNotEmpty) {
    final decodedText = decoded.replaceFirst('\uFEFF', '').trim();
    final decodedConfig = _tryParseClashConfig(decodedText);
    if (decodedConfig != null) {
      return ParsedSubscription(clashConfig: decodedConfig);
    }
    final decodedLinks = parseLinks(decodedText);
    if (decodedLinks.isNotEmpty) {
      return ParsedSubscription(proxies: decodedLinks);
    }
  }
  return ParsedSubscription();
}

List<Map<String, dynamic>> parseLinks(String text) {
  final result = <Map<String, dynamic>>[];
  final used = <String>{};
  for (final raw in text.split(RegExp(r'[\r\n\s]+'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    Map<String, dynamic>? proxy;
    try {
      proxy = parseLink(line);
    } catch (_) {
      proxy = null;
    }
    if (proxy == null) continue;
    var name = (proxy['name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      name = '${proxy['type']} ${proxy['server']}';
    }
    var unique = name;
    var i = 2;
    while (used.contains(unique)) {
      unique = '$name ($i)';
      i++;
    }
    used.add(unique);
    proxy['name'] = unique;
    result.add(proxy);
  }
  return result;
}

Map<String, dynamic>? parseLink(String link) {
  final scheme = link.split('://').first.toLowerCase();
  switch (scheme) {
    case 'vmess':
      return _parseVmess(link);
    case 'vless':
      return _parseVless(link);
    case 'trojan':
      return _parseTrojan(link);
    case 'ss':
      return _parseShadowsocks(link);
    case 'hysteria2':
    case 'hy2':
      return _parseHysteria2(link);
    case 'tuic':
      return _parseTuic(link);
    case 'anytls':
      return _parseAnyTls(link);
    case 'shadowquic':
      return _parseShadowQuic(link);
  }
  return null;
}

String _fragment(Uri uri) {
  try {
    return Uri.decodeComponent(uri.fragment);
  } catch (_) {
    return uri.fragment;
  }
}

bool _truthy(String? v) => v == '1' || v == 'true';

List<String>? _alpn(String? v) {
  if (v == null || v.isEmpty) return null;
  return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

void _putNonEmpty(Map<String, dynamic> m, String key, Object? value) {
  if (value == null) return;
  if (value is String && value.isEmpty) return;
  if (value is List && value.isEmpty) return;
  m[key] = value;
}

/// Applies transport options (ws / grpc / h2 / http / xhttp) in mihomo format.
void _applyTransport(
  Map<String, dynamic> p, {
  required String? network,
  String? path,
  String? host,
  String? serviceName,
  String? headerType,
  String? mode,
}) {
  final net = (network == null || network.isEmpty) ? 'tcp' : network;
  switch (net) {
    case 'ws':
    case 'httpupgrade':
      p['network'] = 'ws';
      final opts = <String, dynamic>{
        'path': (path == null || path.isEmpty) ? '/' : path,
      };
      if (host != null && host.isNotEmpty) opts['headers'] = {'Host': host};
      if (net == 'httpupgrade') opts['v2ray-http-upgrade'] = true;
      p['ws-opts'] = opts;
    case 'grpc':
      p['network'] = 'grpc';
      p['grpc-opts'] = {'grpc-service-name': serviceName ?? path ?? ''};
    case 'h2':
      p['network'] = 'h2';
      p['h2-opts'] = {
        'path': (path == null || path.isEmpty) ? '/' : path,
        if (host != null && host.isNotEmpty) 'host': host.split(','),
      };
    case 'xhttp':
      p['network'] = 'xhttp';
      p['xhttp-opts'] = {
        'path': (path == null || path.isEmpty) ? '/' : path,
        if (host != null && host.isNotEmpty) 'host': host,
        if (mode != null && mode.isNotEmpty) 'mode': mode,
      };
    case 'tcp':
      if (headerType == 'http') {
        p['network'] = 'http';
        p['http-opts'] = {
          'path': [(path == null || path.isEmpty) ? '/' : path],
          if (host != null && host.isNotEmpty)
            'headers': {
              'Host': [host],
            },
        };
      } else {
        p['network'] = 'tcp';
      }
    default:
      p['network'] = net;
  }
}

Map<String, dynamic>? _parseVmess(String link) {
  final body = link.substring('vmess://'.length).split('#').first;
  final decoded = tryDecodeBase64(body);
  if (decoded == null) return null;
  final j = jsonDecode(decoded) as Map<String, dynamic>;
  String? s(String k) => j[k]?.toString();
  final p = <String, dynamic>{
    'name': s('ps') ?? '',
    'type': 'vmess',
    'server': s('add'),
    'port': int.tryParse(s('port') ?? '') ?? 443,
    'uuid': s('id'),
    'alterId': int.tryParse(s('aid') ?? '0') ?? 0,
    'cipher': (s('scy') == null || s('scy')!.isEmpty) ? 'auto' : s('scy'),
    'udp': true,
  };
  final tls = s('tls');
  if (tls == 'tls' || tls == 'reality') {
    p['tls'] = true;
    _putNonEmpty(p, 'servername', s('sni') ?? s('host'));
    _putNonEmpty(p, 'alpn', _alpn(s('alpn')));
    _putNonEmpty(p, 'client-fingerprint', s('fp'));
    if (_truthy(s('allowInsecure'))) p['skip-cert-verify'] = true;
  }
  _applyTransport(
    p,
    network: s('net'),
    path: s('path'),
    host: s('host'),
    serviceName: s('path'),
    headerType: s('type'),
  );
  return p;
}

Map<String, dynamic> _parseVless(String link) {
  final uri = Uri.parse(link);
  final q = uri.queryParameters;
  final p = <String, dynamic>{
    'name': _fragment(uri),
    'type': 'vless',
    'server': uri.host,
    'port': uri.hasPort ? uri.port : 443,
    'uuid': Uri.decodeComponent(uri.userInfo),
    'udp': true,
  };
  _putNonEmpty(p, 'flow', q['flow']);
  final security = q['security'];
  if (security == 'tls' || security == 'reality') {
    p['tls'] = true;
    _putNonEmpty(p, 'servername', q['sni'] ?? q['peer']);
    _putNonEmpty(p, 'alpn', _alpn(q['alpn']));
    _putNonEmpty(
      p,
      'client-fingerprint',
      q['fp'] ?? (security == 'reality' ? 'chrome' : null),
    );
    if (_truthy(q['allowInsecure']) || _truthy(q['insecure'])) {
      p['skip-cert-verify'] = true;
    }
    if (security == 'reality') {
      final publicKey = q['pbk'];
      final shortId = q['sid'];
      p['reality-opts'] = {
        if (publicKey != null && publicKey.isNotEmpty) 'public-key': publicKey,
        if (shortId != null && shortId.isNotEmpty) 'short-id': shortId,
      };
    }
  }
  // These are independent VLESS fields, not TLS-only options.
  // Mihomo's encryption value carries the ML-KEM-768/X25519 PQ handshake
  // configuration verbatim.
  _putNonEmpty(p, 'encryption', q['encryption']);
  _putNonEmpty(
    p,
    'packet-encoding',
    q['packet-encoding'] ?? q['packetEncoding'],
  );
  _applyTransport(
    p,
    network: q['type'],
    path: q['path'],
    host: q['host'],
    serviceName: q['serviceName'],
    headerType: q['headerType'],
    mode: q['mode'],
  );
  return p;
}

Map<String, dynamic> _parseTrojan(String link) {
  final uri = Uri.parse(link);
  final q = uri.queryParameters;
  final p = <String, dynamic>{
    'name': _fragment(uri),
    'type': 'trojan',
    'server': uri.host,
    'port': uri.hasPort ? uri.port : 443,
    'password': Uri.decodeComponent(uri.userInfo),
    'udp': true,
  };
  _putNonEmpty(p, 'sni', q['sni'] ?? q['peer']);
  _putNonEmpty(p, 'alpn', _alpn(q['alpn']));
  _putNonEmpty(p, 'client-fingerprint', q['fp']);
  if (_truthy(q['allowInsecure']) || _truthy(q['insecure'])) {
    p['skip-cert-verify'] = true;
  }
  if (q['security'] == 'reality') {
    p['reality-opts'] = {
      'public-key': q['pbk'] ?? '',
      if ((q['sid'] ?? '').isNotEmpty) 'short-id': q['sid'],
    };
  }
  if (q['type'] != null && q['type'] != 'tcp') {
    _applyTransport(
      p,
      network: q['type'],
      path: q['path'],
      host: q['host'],
      serviceName: q['serviceName'],
    );
  }
  return p;
}

Map<String, dynamic>? _parseShadowsocks(String link) {
  var body = link.substring('ss://'.length);
  var name = '';
  final hashIdx = body.indexOf('#');
  if (hashIdx >= 0) {
    try {
      name = Uri.decodeComponent(body.substring(hashIdx + 1));
    } catch (_) {
      name = body.substring(hashIdx + 1);
    }
    body = body.substring(0, hashIdx);
  }
  String query = '';
  final qIdx = body.indexOf('?');
  if (qIdx >= 0) {
    query = body.substring(qIdx + 1);
    body = body.substring(0, qIdx);
  }
  body = body.replaceAll(RegExp(r'/$'), '');

  String userInfo;
  String hostPort;
  if (body.contains('@')) {
    final at = body.lastIndexOf('@');
    userInfo = body.substring(0, at);
    hostPort = body.substring(at + 1);
    final decoded = tryDecodeBase64(Uri.decodeComponent(userInfo));
    if (decoded != null && decoded.contains(':')) userInfo = decoded;
    userInfo = Uri.decodeComponent(userInfo);
  } else {
    final decoded = tryDecodeBase64(body);
    if (decoded == null || !decoded.contains('@')) return null;
    final at = decoded.lastIndexOf('@');
    userInfo = decoded.substring(0, at);
    hostPort = decoded.substring(at + 1);
  }
  final colon = userInfo.indexOf(':');
  if (colon < 0) return null;
  final hp = Uri.parse('ss://$hostPort');
  final p = <String, dynamic>{
    'name': name,
    'type': 'ss',
    'server': hp.host,
    'port': hp.port,
    'cipher': userInfo.substring(0, colon),
    'password': userInfo.substring(colon + 1),
    'udp': true,
  };
  if (query.isNotEmpty) {
    final plugin = Uri.splitQueryString(query)['plugin'];
    if (plugin != null && plugin.isNotEmpty) {
      final parts = plugin.split(';');
      final opts = <String, String>{};
      for (final part in parts.skip(1)) {
        final kv = part.split('=');
        if (kv.length == 2) opts[kv[0]] = kv[1];
      }
      if (parts.first.contains('obfs')) {
        p['plugin'] = 'obfs';
        p['plugin-opts'] = {
          'mode': opts['obfs'] ?? 'http',
          if (opts['obfs-host'] != null) 'host': opts['obfs-host'],
        };
      } else if (parts.first.contains('v2ray')) {
        p['plugin'] = 'v2ray-plugin';
        p['plugin-opts'] = {
          'mode': 'websocket',
          if (opts.containsKey('tls')) 'tls': true,
          if (opts['host'] != null) 'host': opts['host'],
          if (opts['path'] != null) 'path': opts['path'],
        };
      }
    }
  }
  return p;
}

Map<String, dynamic> _parseHysteria2(String link) {
  final uri = Uri.parse(link.replaceFirst(RegExp(r'^hy2://'), 'hysteria2://'));
  final q = uri.queryParameters;
  final p = <String, dynamic>{
    'name': _fragment(uri),
    'type': 'hysteria2',
    'server': uri.host,
    'port': uri.hasPort ? uri.port : 443,
    'password': Uri.decodeComponent(uri.userInfo),
    'udp': true,
  };
  _putNonEmpty(p, 'sni', q['sni']);
  _putNonEmpty(p, 'obfs', q['obfs']);
  _putNonEmpty(p, 'obfs-password', q['obfs-password']);
  _putNonEmpty(p, 'alpn', _alpn(q['alpn']));
  _putNonEmpty(p, 'ports', q['mport']);
  if (_truthy(q['insecure'])) p['skip-cert-verify'] = true;
  return p;
}

Map<String, dynamic> _parseTuic(String link) {
  final uri = Uri.parse(link);
  final q = uri.queryParameters;
  final info = Uri.decodeComponent(uri.userInfo);
  final colon = info.indexOf(':');
  final p = <String, dynamic>{
    'name': _fragment(uri),
    'type': 'tuic',
    'server': uri.host,
    'port': uri.hasPort ? uri.port : 443,
    'uuid': colon >= 0 ? info.substring(0, colon) : info,
    'password': colon >= 0 ? info.substring(colon + 1) : '',
    'udp': true,
  };
  _putNonEmpty(p, 'sni', q['sni']);
  _putNonEmpty(p, 'alpn', _alpn(q['alpn']) ?? ['h3']);
  _putNonEmpty(p, 'congestion-controller', q['congestion_control']);
  _putNonEmpty(p, 'udp-relay-mode', q['udp_relay_mode']);
  if (_truthy(q['allow_insecure']) || _truthy(q['insecure'])) {
    p['skip-cert-verify'] = true;
  }
  return p;
}



/// Parses a ShadowQUIC share URI into Mihomo's outbound schema.
/// Full Mihomo YAML subscriptions already preserve ShadowQUIC nodes as-is.
Map<String, dynamic>? _parseShadowQuic(String link) {
  final uri = Uri.parse(link);
  if (uri.host.isEmpty || !uri.hasPort || uri.userInfo.isEmpty) return null;
  final q = uri.queryParameters;
  final credentials = Uri.decodeComponent(uri.userInfo);
  final colon = credentials.indexOf(':');
  if (colon < 1 || colon == credentials.length - 1) return null;
  final p = <String, dynamic>{
    'name': _fragment(uri),
    'type': 'shadowquic',
    'server': uri.host,
    'port': uri.port,
    'username': credentials.substring(0, colon),
    'password': credentials.substring(colon + 1),
  };
  _putNonEmpty(p, 'sni', q['sni']);
  _putNonEmpty(p, 'alpn', _alpn(q['alpn']) ?? ['h3']);
  _putNonEmpty(p, 'quic-versions', _alpn(q['quic-versions'] ?? q['quic_versions']));
  _putNonEmpty(p, 'keep-alive-interval', int.tryParse(q['keep-alive-interval'] ?? ''));
  _putNonEmpty(p, 'congestion-controller', q['congestion-controller']);
  _putNonEmpty(p, 'up', q['up']);
  _putNonEmpty(p, 'down', q['down']);
  if (_truthy(q['udp-over-stream'])) p['udp-over-stream'] = true;
  if (_truthy(q['zero-rtt'])) p['zero-rtt'] = true;
  return p;
}

/// Parses an AnyTLS share URI into Mihomo's outbound schema.
/// AnyTLS is TLS-based by definition; Mihomo's AnyTLS outbound uses SNI
/// rather than a separate `tls: true` field.
Map<String, dynamic>? _parseAnyTls(String link) {
  final uri = Uri.parse(link);
  if (uri.host.isEmpty || !uri.hasPort || uri.userInfo.isEmpty) return null;
  final q = uri.queryParameters;
  final p = <String, dynamic>{
    'name': _fragment(uri),
    'type': 'anytls',
    'server': uri.host,
    'port': uri.port,
    'password': Uri.decodeComponent(uri.userInfo),
    'udp': true,
  };
  _putNonEmpty(p, 'sni', q['sni'] ?? q['peer']);
  _putNonEmpty(p, 'alpn', _alpn(q['alpn']));
  _putNonEmpty(p, 'client-fingerprint', q['fp']);
  if (_truthy(q['insecure']) || _truthy(q['allowInsecure'])) {
    p['skip-cert-verify'] = true;
  }
  return p;
}
