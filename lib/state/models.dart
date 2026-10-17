import 'dart:math';

class Profile {
  Profile({
    required this.id,
    required this.name,
    this.url,
    required this.updatedAt,
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expire,
    this.proxyCount = 0,
    this.hasTrafficInfo = false,
    this.hasExpiryInfo = false,
  });

  final String id;
  String name;
  final String? url;
  DateTime updatedAt;
  int upload;
  int download;
  int total;
  DateTime? expire;
  int proxyCount;
  bool hasTrafficInfo;
  bool hasExpiryInfo;

  bool get isRemote => url != null;
  int get used => upload + download;
  double? get usage => total > 0 ? (used / total).clamp(0, 1).toDouble() : null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'updatedAt': updatedAt.toIso8601String(),
    'upload': upload,
    'download': download,
    'total': total,
    'expire': expire?.toIso8601String(),
    'proxyCount': proxyCount,
    'hasTrafficInfo': hasTrafficInfo,
    'hasExpiryInfo': hasExpiryInfo,
  };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    name: j['name'] as String,
    url: j['url'] as String?,
    updatedAt:
        DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    upload: (j['upload'] as num?)?.toInt() ?? 0,
    download: (j['download'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
    expire: DateTime.tryParse(j['expire'] as String? ?? ''),
    proxyCount: (j['proxyCount'] as num?)?.toInt() ?? 0,
    hasTrafficInfo:
        j['hasTrafficInfo'] as bool? ??
        ((j['total'] as num?)?.toInt() ?? 0) > 0,
    hasExpiryInfo:
        (j['hasExpiryInfo'] as bool?) ?? j['expire'] != null,
  );

  void applyUserInfo(String? header) {
    if (header == null) return;
    var hasTraffic = false;
    for (final part in header.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length != 2) continue;
      final v = int.tryParse(kv[1].trim()) ?? 0;
      switch (kv[0].trim()) {
        case 'upload':
          upload = v;
          hasTraffic = true;
        case 'download':
          download = v;
          hasTraffic = true;
        case 'total':
          total = v;
          hasTraffic = true;
        case 'expire':
          expire = v > 0 ? DateTime.fromMillisecondsSinceEpoch(v * 1000) : null;
          hasExpiryInfo = true;
      }
    }
    hasTrafficInfo = hasTraffic || hasTrafficInfo;
  }
}

class ProxyNode {
  ProxyNode({
    required this.name,
    required this.type,
    this.now,
    this.all = const [],
    this.history,
  });

  final String name;
  final String type;
  final String? now;
  final List<String> all;
  final int? history;

  static const groupTypes = {
    'Selector',
    'URLTest',
    'Fallback',
    'LoadBalance',
    'Relay',
  };
  bool get isGroup => groupTypes.contains(type);
  bool get isSelectable => type == 'Selector';

  factory ProxyNode.fromJson(String name, Map<String, dynamic> j) {
    final hist = j['history'] as List?;
    int? last;
    if (hist != null && hist.isNotEmpty) {
      last = ((hist.last as Map)['delay'] as num?)?.toInt();
      if (last == 0) last = -1;
    }
    return ProxyNode(
      name: name,
      type: j['type']?.toString() ?? '',
      now: j['now']?.toString(),
      all: (j['all'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      history: last,
    );
  }
}

class ProxyConnection {
  const ProxyConnection({
    required this.host,
    required this.port,
    required this.rule,
    required this.rulePayload,
    required this.chains,
    required this.network,
  });

  final String host;
  final String port;
  final String rule;
  final String rulePayload;
  final List<String> chains;
  final String network;

  factory ProxyConnection.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] is Map
        ? (json['metadata'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final destinationIp = metadata['destinationIP']?.toString() ?? '';
    return ProxyConnection(
      host: [
        metadata['host']?.toString(),
        if (destinationIp.isNotEmpty) destinationIp,
      ].firstWhere(
        (value) => value != null && value.isNotEmpty,
        orElse: () => '—',
      )!,
      port: metadata['destinationPort']?.toString() ?? '',
      rule: json['rule']?.toString() ?? '',
      rulePayload: json['rulePayload']?.toString() ?? '',
      chains:
          (json['chains'] as List?)?.map((value) => value.toString()).toList() ??
          const [],
      network: metadata['network']?.toString() ?? '',
    );
  }
}

enum ConnStatus { disconnected, connecting, connected, disconnecting }

class LogEntry {
  LogEntry(this.level, this.message) : time = DateTime.now();
  final String level;
  final String message;
  final DateTime time;
}

String newId() {
  final r = Random.secure();
  return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
}

String formatBytes(num bytes, {int digits = 1}) {
  const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : digits)} ${units[i]}';
}

String formatSpeed(num bytesPerSec) => '${formatBytes(bytesPerSec)}/с';

String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0
      ? '$h:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
      : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'только что';
  if (d.inHours < 1) return '${d.inMinutes} мин назад';
  if (d.inDays < 1) return '${d.inHours} ч назад';
  return '${d.inDays} дн назад';
}

String proxyTypeLabel(String type) => switch (type.toLowerCase()) {
  'vless' => 'VLESS',
  'vmess' => 'VMess',
  'trojan' => 'Trojan',
  'shadowsocks' || 'ss' => 'Shadowsocks',
  'hysteria2' => 'Hysteria 2',
  'tuic' => 'TUIC',
  'wireguard' => 'WireGuard',
  'direct' => 'Напрямую',
  'reject' => 'Блок',
  'selector' => 'Ручной выбор',
  'urltest' => 'Авто (по пингу)',
  'fallback' => 'Резерв',
  'loadbalance' => 'Балансировка',
  _ => type,
};
