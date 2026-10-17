import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/android_vpn.dart';
import '../core/config_builder.dart';
import '../core/link_parser.dart';
import '../core/mihomo_config_path.dart';
import '../core/mihomo_api.dart';
import '../core/mihomo_core.dart';
import '../core/proxy_probe.dart';
import '../core/routing_rules.dart';
import '../core/system_proxy.dart';
import 'models.dart';
import 'settings.dart';

/// Rolling traffic history (bytes/sec), one sample per second.
class TrafficStore extends ChangeNotifier {
  static const length = 60;
  final up = Queue<int>.from(List.filled(length, 0));
  final down = Queue<int>.from(List.filled(length, 0));
  DateTime lastSample = DateTime.now();
  int totalUp = 0;
  int totalDown = 0;

  int get currentUp => up.last;
  int get currentDown => down.last;

  void add(int u, int d) {
    up
      ..removeFirst()
      ..addLast(u);
    down
      ..removeFirst()
      ..addLast(d);
    totalUp += u;
    totalDown += d;
    lastSample = DateTime.now();
    notifyListeners();
  }

  void reset() {
    for (final q in [up, down]) {
      q
        ..clear()
        ..addAll(List.filled(length, 0));
    }
    totalUp = 0;
    totalDown = 0;
    notifyListeners();
  }
}

class LogStore extends ChangeNotifier {
  static const cap = 500;
  final entries = Queue<LogEntry>();

  void add(LogEntry e) {
    entries.addLast(e);
    if (entries.length > cap) entries.removeFirst();
    notifyListeners();
  }

  void clear() {
    entries.clear();
    notifyListeners();
  }
}

class AppState extends ChangeNotifier {
  late final Settings settings;
  late final String dataDir;
  final core = MihomoCore();
  final androidVpn = AndroidVpn();
  final traffic = TrafficStore();
  final logs = LogStore();

  List<Profile> profiles = [];
  ConnStatus status = ConnStatus.disconnected;
  String? error;

  /// Servers dropped on the last connect because the core rejected them.
  List<String> skipped = const [];
  String? coreVersion;
  String? corePath;
  DateTime? connectedAt;
  bool isAdmin = false;

  Map<String, ProxyNode> nodes = {};
  Map<String, Map<String, dynamic>> proxyConfigs = {};
  List<ProxyNode> groups = [];
  String? viewGroup;
  final Map<String, int> delays = {};
  final Set<String> testing = {};
  final Set<String> _autoDelayAttempted = {};
  bool busyProfile = false;
  bool probingProfile = false;
  String? reachabilityMessage;
  Map<String, bool> reachability = {};
  List<ProxyConnection> activeConnections = const [];
  String? connectionsError;

  MihomoApi? _api;
  StreamSubscription<Map<String, dynamic>>? _trafficSub;
  StreamSubscription<Map<String, dynamic>>? _logSub;
  Timer? _connectionsTimer;
  bool _refreshingConnections = false;
  String? _androidSessionId;

  String _serverKey(String name) =>
      '${activeProfile?.id ?? 'default'}::$name';

  bool isFavoriteServer(String name) =>
      settings.favoriteServers.contains(_serverKey(name));

  void toggleFavoriteServer(String name) {
    final favorites = settings.favoriteServers;
    final key = _serverKey(name);
    if (favorites.contains(key)) {
      favorites.remove(key);
    } else {
      favorites.add(key);
    }
    settings.favoriteServers = favorites;
    notifyListeners();
  }

  List<String> get recentServerNames {
    final prefix = '${activeProfile?.id ?? 'default'}::';
    return [
      for (final key in settings.recentServers)
        if (key.startsWith(prefix)) key.substring(prefix.length),
    ];
  }

  void recordRecentServer(String name) {
    final key = _serverKey(name);
    final recent = settings.recentServers
      ..remove(key)
      ..insert(0, key);
    if (recent.length > 30) recent.removeRange(30, recent.length);
    settings.recentServers = recent;
  }

  Future<List<String>> routingActionsForActiveProfile() async {
    final profile = activeProfile;
    if (profile == null) return const ['DIRECT', 'REJECT'];
    final content = await _profileFile(profile.id).readAsString();
    return routingActionsFor(parseSubscription(content));
  }

  Future<void> addDomainRule(String rule) async {
    if (!settings.domainRules.contains(rule)) {
      settings.domainRules = [...settings.domainRules, rule];
      notifyListeners();
      if (isConnected) await reconnect();
    }
  }

  Future<void> removeDomainRule(String rule) async {
    settings.domainRules = settings.domainRules
        .where((r) => r != rule)
        .toList();
    notifyListeners();
    if (isConnected) await reconnect();
  }

  bool get isConnected => status == ConnStatus.connected;
  bool get isBusy =>
      status == ConnStatus.connecting || status == ConnStatus.disconnecting;

  Profile? get activeProfile {
    final id = settings.activeProfileId;
    for (final pr in profiles) {
      if (pr.id == id) return pr;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  Future<void> init() async {
    settings = Settings(await SharedPreferences.getInstance());
    final support = await getApplicationSupportDirectory();
    dataDir = support.path;
    await Directory(p.join(dataDir, 'profiles')).create(recursive: true);
    await Directory(p.join(dataDir, 'home')).create(recursive: true);
    await _loadProfiles();
    if (!Platform.isAndroid) {
      corePath = await MihomoCore.locate(
        customPath: settings.corePath,
        dataDir: dataDir,
      );
    }
    unawaited(_detectCoreVersion());
    unawaited(
      Elevation.isAdmin().then((v) {
        isAdmin = v;
        notifyListeners();
      }),
    );
    core.onLine = _onCoreLine;
    core.onExit = (code) {
      if (status == ConnStatus.connected) {
        error = 'Ядро неожиданно остановилось (код $code)';
        _afterStopped();
      }
    };
  }

  Future<void> _detectCoreVersion() async {
    final path = corePath;
    if (path == null) return;
    try {
      final r = await Process.run(path, ['-v']);
      final m = RegExp(r'v\d+\.\d+\.\d+').firstMatch(r.stdout as String);
      coreVersion =
          m?.group(0) ?? (r.stdout as String).trim().split('\n').first;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setCorePath(String? path) async {
    settings.corePath = path;
    corePath = await MihomoCore.locate(customPath: path, dataDir: dataDir);
    coreVersion = null;
    notifyListeners();
    await _detectCoreVersion();
  }

  // ---------------------------------------------------------------- profiles

  File _profileFile(String id) => File(p.join(dataDir, 'profiles', '$id.txt'));
  File get _profilesIndex => File(p.join(dataDir, 'profiles.json'));

  Future<void> _loadProfiles() async {
    try {
      final list = jsonDecode(await _profilesIndex.readAsString()) as List;
      profiles = list
          .map((e) => Profile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      profiles = [];
    }
  }

  Future<void> _saveProfiles() async {
    await _profilesIndex.writeAsString(
      jsonEncode([for (final pr in profiles) pr.toJson()]),
    );
  }

  http.Client _makeHttpClient() => http.Client();

  Future<(String, http.Response)> _download(String url) async {
    final client = _makeHttpClient();
    try {
      final res = await client
          .get(
            Uri.parse(url),
            headers: {'User-Agent': 'clash.meta/mihomo crew/0.1'},
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode >= 400) {
        final body = utf8.decode(res.bodyBytes, allowMalformed: true);
        final snippet = body.length > 300 ? body.substring(0, 300) : body;
        throw Exception(
          'Сервер вернул ${res.statusCode}\nОтвет: $snippet',
        );
      }
      return (utf8.decode(res.bodyBytes, allowMalformed: true), res);
    } on SocketException catch (e) {
      throw Exception(
        'Не удалось подключиться к серверу подписки: ${e.message}\n'
        'Проверьте адрес и сеть или вставьте ссылки серверов текстом.',
      );
    } on HandshakeException catch (e) {
      throw Exception('Ошибка TLS при подключении к серверу: ${e.message}');
    } on TimeoutException {
      throw Exception(
        'Сервер не ответил за 20 секунд.\n'
        'Проверьте адрес подписки и доступность сети.',
      );
    } finally {
      client.close();
    }
  }

  String? _titleFromHeaders(http.Response res, String url) {
    var t = res.headers['profile-title'];
    if (t != null && t.startsWith('base64:')) {
      t = tryDecodeBase64(t.substring(7));
    }
    if (t != null && t.trim().isNotEmpty) return t.trim();
    final cd = res.headers['content-disposition'];
    final m = cd == null
        ? null
        : RegExp(r'''filename\*?=(?:UTF-8'')?"?([^";]+)''').firstMatch(cd);
    if (m != null) return Uri.decodeComponent(m.group(1)!);
    return Uri.tryParse(url)?.host;
  }

  /// Adds a profile from a subscription URL or raw text (links / YAML).
  Future<void> addProfile(String input, {String? name}) async {
    final text = input.trim();
    busyProfile = true;
    notifyListeners();
    try {
      final isUrl =
          RegExp(r'^https?://', caseSensitive: false).hasMatch(text) &&
          !text.contains('\n');
      String content;
      String title;
      final profile = Profile(
        id: newId(),
        name: '',
        url: isUrl ? text : null,
        updatedAt: DateTime.now(),
      );
      if (isUrl) {
        final (body, res) = await _download(text);
        content = body;
        title = name ?? _titleFromHeaders(res, text) ?? 'Подписка';
        profile.applyUserInfo(res.headers['subscription-userinfo']);
      } else {
        content = text;
        title = name ?? 'Мои серверы';
      }
      final parsed = parseSubscription(content);
      if (parsed.isEmpty) {
        throw Exception('Не удалось распознать ни одного сервера');
      }
      profile
        ..name = title
        ..proxyCount = parsed.proxyCount;
      await _profileFile(profile.id).writeAsString(content);
      profiles.add(profile);
      settings.activeProfileId ??= profile.id;
      await _saveProfiles();
      error = null;
    } finally {
      busyProfile = false;
      notifyListeners();
    }
  }

  Future<void> updateProfile(Profile pr) async {
    if (pr.url == null) return;
    busyProfile = true;
    notifyListeners();
    try {
      final (body, res) = await _download(pr.url!);
      final parsed = parseSubscription(body);
      if (parsed.isEmpty) throw Exception('Подписка пуста');
      await _profileFile(pr.id).writeAsString(body);
      pr
        ..updatedAt = DateTime.now()
        ..proxyCount = parsed.proxyCount
        ..applyUserInfo(res.headers['subscription-userinfo']);
      await _saveProfiles();
      if (isConnected && pr.id == activeProfile?.id) await reconnect();
    } finally {
      busyProfile = false;
      notifyListeners();
    }
  }

  Future<void> renameProfile(Profile pr, String name) async {
    pr.name = name;
    await _saveProfiles();
    notifyListeners();
  }

  Future<void> deleteProfile(Profile pr) async {
    final wasActive = pr.id == activeProfile?.id;
    profiles.remove(pr);
    try {
      await _profileFile(pr.id).delete();
    } catch (_) {}
    if (wasActive) {
      settings.activeProfileId = profiles.isEmpty ? null : profiles.first.id;
      if (isConnected) {
        profiles.isEmpty ? await disconnect() : await reconnect();
      }
    }
    await _saveProfiles();
    notifyListeners();
  }

  Future<void> setActiveProfile(Profile pr) async {
    if (pr.id == activeProfile?.id) return;
    settings.activeProfileId = pr.id;
    delays.clear();
    notifyListeners();
    if (isConnected) await reconnect();
  }

  // -------------------------------------------------------------- connection

  Future<void> toggle() async {
    if (isBusy) return;
    isConnected ? await disconnect() : await connect();
  }

  CoreOptions get _options => CoreOptions(
    mixedPort: settings.mixedPort,
    apiPort: settings.apiPort,
    secret: settings.secret,
    mode: settings.mode,
    // Android supplies its TUN descriptor through VpnService instead of
    // asking mihomo to create a second, independent TUN interface.
    tun: !Platform.isAndroid && settings.tun,
    allowLan: settings.allowLan,
    externalTun: Platform.isAndroid,
    sniSpoofing: settings.sniSpoofing,
    userRules: [
      ...settings.domainRules,
      ...settings.userRules
          .split('\n')
          .map((rule) => rule.trim())
          .where((rule) => rule.isNotEmpty),
    ],
  );

  Future<String> checkProfileReachability() async {
    if (isConnected || isBusy) {
      return 'Отключитесь перед проверкой серверов.';
    }
    if (probingProfile) return 'Проверка уже выполняется.';
    final profile = activeProfile;
    if (profile == null) return 'Сначала добавьте подписку.';

    probingProfile = true;
    reachabilityMessage = null;
    reachability = {};
    notifyListeners();
    try {
      final content = await _profileFile(profile.id).readAsString();
      final endpoints = proxyEndpoints(parseSubscription(content));
      if (endpoints.isEmpty) {
        reachabilityMessage =
            'В профиле нет встроенных адресов узлов для проверки. '
            'Профили только с proxy-providers проверяйте после запуска Mihomo.';
        return reachabilityMessage!;
      }
      final results = await probeProxyEndpoints(endpoints);
      reachability = {
        for (final result in results)
          result.endpoint.name: result.isReachable,
      };
      final reachable = results.where((result) => result.isReachable).length;
      reachabilityMessage =
          'TCP-порт доступен: $reachable из ${results.length}. '
          'Это проверка порта, не проверка VPN-протокола; UDP-узлы могут '
          'быть доступны, даже если TCP-проверка не прошла.';
      return reachabilityMessage!;
    } catch (e) {
      reachabilityMessage = 'Не удалось проверить серверы: $e';
      return reachabilityMessage!;
    } finally {
      probingProfile = false;
      notifyListeners();
    }
  }

  Future<void> connect() async {
    final profile = activeProfile;
    if (profile == null) {
      error = 'Сначала добавьте подписку';
      notifyListeners();
      return;
    }
    if (corePath == null && !Platform.isAndroid) {
      error = 'Не найдено ядро mihomo. Укажите путь в настройках.';
      notifyListeners();
      return;
    }
    status = ConnStatus.connecting;
    error = null;
    skipped = const [];
    notifyListeners();
    final started = DateTime.now();
    var androidServiceStarted = false;
    String? androidSessionId;
    try {
      final content = await _profileFile(profile.id).readAsString();
      final config = applyCoreOptions(
        baseConfigFor(parseSubscription(content)),
        _options,
      );
      final rawProxies = config['proxies'];
      proxyConfigs = {
        if (rawProxies is List)
          for (final proxy in rawProxies)
            if (proxy is Map && proxy['name'] is String)
              proxy['name'] as String: Map<String, dynamic>.from(proxy),
      };
      final configFile = await prepareMihomoConfigFile(dataDir);
      skipped = await _writeValidConfig(config, configFile);
      for (final s in skipped) {
        logs.add(LogEntry('warning', 'Сервер пропущен: $s'));
      }

      final api = MihomoApi(port: settings.apiPort, secret: settings.secret);
      _api = api;
      if (Platform.isAndroid) {
        await androidVpn.prepare();
        androidSessionId = newId();
        _androidSessionId = androidSessionId;
        await androidVpn.start(
          configFile.path,
          sessionId: androidSessionId,
        );
        androidServiceStarted = true;
        await _waitForApi(api);
        coreVersion = await api.version();
      } else {
        await core.start(
          binary: corePath!,
          homeDir: p.join(dataDir, 'home'),
          configPath: configFile.path,
          api: api,
        );
      }
      if (!Platform.isAndroid && settings.systemProxy && !settings.tun) {
        await SystemProxy.enable(settings.mixedPort);
      }
      _subscribeStreams(api);
      await refreshProxies();
      // Let the connect animation breathe a little even on fast machines.
      final elapsed = DateTime.now().difference(started);
      if (elapsed < const Duration(milliseconds: 900)) {
        await Future<void>.delayed(const Duration(milliseconds: 900) - elapsed);
      }
      status = ConnStatus.connected;
      connectedAt = DateTime.now();
      notifyListeners();
    } catch (e) {
      Object connectionError = e;
      if (androidServiceStarted) {
        try {
          await androidVpn.stop(sessionId: androidSessionId!);
        } catch (stopError) {
          connectionError = StateError('$e; VPN cleanup failed: $stopError');
        }
      } else if (!Platform.isAndroid) {
        await core.stop();
      }
      if (_androidSessionId == androidSessionId) _androidSessionId = null;
      _api?.close();
      _api = null;
      _trafficSub?.cancel();
      _trafficSub = null;
      _logSub?.cancel();
      _logSub = null;
      _connectionsTimer?.cancel();
      _connectionsTimer = null;
      _refreshingConnections = false;
      activeConnections = const [];
      connectionsError = null;
      status = ConnStatus.disconnected;
      _androidSessionId = null;
      error = connectionError.toString();
      logs.add(LogEntry('error', connectionError.toString()));
      notifyListeners();
    }
  }

  /// Writes [config], dropping servers the core refuses to load so that one
  /// broken node in a subscription doesn't block all the others.
  /// Validates the generated profile without silently mutating provider data.
  ///
  /// A rejected proxy is surfaced as a configuration error. Removing it can
  /// break proxy groups, providers, or routing rules and can hide unsupported
  /// protocol fields from the user.
  Future<List<String>> _writeValidConfig(
    Map<String, dynamic> config,
    File file,
  ) async {
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );
    final err = Platform.isAndroid
        ? await androidVpn.validateConfig(file.path)
        : await MihomoCore.check(
            binary: corePath!,
            homeDir: file.parent.path,
            configPath: file.path,
          );
    if (err != null) throw CoreConfigException(err);
    return const [];
  }

  Future<void> disconnect() async {
    if (status == ConnStatus.disconnected) return;
    status = ConnStatus.disconnecting;
    error = null;
    notifyListeners();
    try {
      if (!Platform.isAndroid && settings.systemProxy) {
        await SystemProxy.disable();
      }
      if (Platform.isAndroid) {
        final sessionId = _androidSessionId;
        if (sessionId != null) {
          await androidVpn.stop(sessionId: sessionId);
        }
      } else {
        await core.stop();
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    } catch (e) {
      error = e.toString();
      logs.add(LogEntry('error', error!));
    } finally {
      _afterStopped();
    }
  }

  void _afterStopped() {
    _trafficSub?.cancel();
    _logSub?.cancel();
    _connectionsTimer?.cancel();
    _connectionsTimer = null;
    activeConnections = const [];
    connectionsError = null;
    _trafficSub = null;
    _logSub = null;
    _api?.close();
    _api = null;
    _androidSessionId = null;
    status = ConnStatus.disconnected;
    connectedAt = null;
    traffic.reset();
    notifyListeners();
  }

  Future<void> reconnect() async {
    await disconnect();
    if (error != null) return;
    await connect();
  }

  Future<void> shutdown() async {
    if (status != ConnStatus.disconnected) {
      if (!Platform.isAndroid && settings.systemProxy) {
        await SystemProxy.disable();
      }
      if (Platform.isAndroid) {
        final sessionId = _androidSessionId;
        if (sessionId != null) {
          await androidVpn.stop(sessionId: sessionId);
        }
      } else {
        await core.stop();
      }
    }
  }

  Future<void> _waitForApi(MihomoApi api) async {
    await waitForMihomoApi(api.version);
  }

  void _subscribeStreams(MihomoApi api) {
    _trafficSub?.cancel();
    _trafficSub = api.stream('/traffic').listen((j) {
      traffic.add(
        (j['up'] as num?)?.toInt() ?? 0,
        (j['down'] as num?)?.toInt() ?? 0,
      );
    }, onError: (_) {});
    _logSub?.cancel();
    _logSub = api.stream('/logs', {'level': 'info'}).listen((j) {
      logs.add(
        LogEntry(
          j['type']?.toString() ?? 'info',
          j['payload']?.toString() ?? '',
        ),
      );
    }, onError: (_) {});
    _connectionsTimer?.cancel();
    unawaited(refreshConnections());
    _connectionsTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(refreshConnections()),
    );
  }

  Future<void> refreshConnections() async {
    final api = _api;
    if (api == null || _refreshingConnections) return;
    _refreshingConnections = true;
    try {
      final raw = await api.connections();
      if (identical(_api, api)) {
        activeConnections = raw.map(ProxyConnection.fromJson).toList();
        connectionsError = null;
      }
    } catch (e) {
      if (identical(_api, api)) connectionsError = e.toString();
    } finally {
      _refreshingConnections = false;
      notifyListeners();
    }
  }

  void _onCoreLine(String line) {
    if (_logSub != null) return;
    final m = RegExp(r'level=(\w+) msg="?(.*?)"?$').firstMatch(line);
    logs.add(
      m != null ? LogEntry(m.group(1)!, m.group(2)!) : LogEntry('info', line),
    );
  }

  // ----------------------------------------------------------------- proxies

  Future<void> refreshProxies() async {
    final api = _api;
    if (api == null) return;
    final raw = await api.proxies();
    nodes = raw.map(
      (k, v) => MapEntry(
        k,
        ProxyNode.fromJson(k, (v as Map).cast<String, dynamic>()),
      ),
    );
    for (final n in nodes.values) {
      // A stale failed probe (-1) must not permanently hide a valid delay
      // reported by Mihomo's own history.
      if (n.history != null &&
          n.history! > 0 &&
          (delays[n.name] == null || delays[n.name]! <= 0)) {
        delays[n.name] = n.history!;
      }
    }
    final order = nodes['GLOBAL']?.all ?? const <String>[];
    groups = [
      for (final name in order)
        if (nodes[name]?.isGroup ?? false) nodes[name]!,
    ];
    if (settings.mode == 'global' && nodes['GLOBAL'] != null) {
      groups.insert(0, nodes['GLOBAL']!);
    }
    if (viewGroup == null || !groups.any((g) => g.name == viewGroup)) {
      viewGroup = mainGroup?.name;
    }
    notifyListeners();

    // The Android embedded core has no HTTP controller for Mihomo's delay
    // endpoint, so actively probe the currently selected leaf via the JNI
    // bridge instead of leaving the home-page latency chip at "— мс".
    final selected = currentServer;
    if (Platform.isAndroid &&
        selected != null &&
        (delays[selected] == null || delays[selected]! <= 0) &&
        !testing.contains(selected) &&
        _autoDelayAttempted.add(selected)) {
      unawaited(testDelay(selected));
    }
  }

  ProxyNode? get mainGroup {
    if (groups.isEmpty) return null;
    if (settings.mode == 'global') return nodes['GLOBAL'];
    return groups.firstWhere((g) => g.isSelectable, orElse: () => groups.first);
  }

  /// Follows the `now` chain from the main group, e.g. [PROXY, AUTO, Server 3].
  List<String> get currentChain {
    final chain = <String>[];
    var node = mainGroup;
    while (node != null && chain.length < 8) {
      chain.add(node.name);
      final next = node.now;
      if (next == null) break;
      final n = nodes[next];
      if (n == null || !n.isGroup) {
        chain.add(next);
        break;
      }
      node = n;
    }
    return chain;
  }

  String? get currentServer =>
      currentChain.length > 1 ? currentChain.last : null;

  void setViewGroup(String name) {
    viewGroup = name;
    notifyListeners();
  }

  Future<void> select(String group, String name) async {
    final api = _api;
    if (api == null) return;
    await api.select(group, name);
    recordRecentServer(name);
    await api.closeConnections();
    await refreshProxies();
  }

  Future<void> testDelay(String name) async {
    final api = _api;
    if (api == null) return;
    testing.add(name);
    notifyListeners();
    try {
      delays[name] = await api.delay(name);
    } catch (e) {
      delays[name] = -1;
      logs.add(LogEntry('warning', 'Не удалось проверить задержку $name: $e'));
    } finally {
      testing.remove(name);
      notifyListeners();
    }
  }

  Future<void> testGroup(String group) async {
    final api = _api;
    final g = nodes[group];
    if (api == null || g == null) return;
    final members = g.all.where(
      (n) => !(nodes[n]?.isGroup ?? false) && n != 'DIRECT' && n != 'REJECT',
    );
    testing.addAll(members);
    notifyListeners();
    final result = await api.groupDelay(group);
    for (final n in members) {
      delays[n] = result[n] ?? -1;
    }
    testing.removeAll(members);
    await refreshProxies();
  }

  /// Pings everything in the main group and switches to the fastest server.
  Future<String?> selectBest() async {
    final group = mainGroup;
    if (group == null || !group.isSelectable) return null;
    await testGroup(group.name);
    String? best;
    var bestDelay = 1 << 30;
    for (final n in group.all) {
      final node = nodes[n];
      if (node == null || node.isGroup || n == 'DIRECT' || n == 'REJECT') {
        continue;
      }
      final d = delays[n] ?? -1;
      if (d > 0 && d < bestDelay) {
        bestDelay = d;
        best = n;
      }
    }
    if (best != null) await select(group.name, best);
    return best;
  }

  // ---------------------------------------------------------------- settings

  Future<void> setMode(String mode) async {
    settings.mode = mode;
    notifyListeners();
    final api = _api;
    if (api != null) {
      await api.patchConfig({'mode': mode});
      await api.closeConnections();
      viewGroup = null;
      await refreshProxies();
    }
  }

  Future<void> setUserRules(String rules) async {
    settings.userRules = rules;
    notifyListeners();
    if (isConnected) await reconnect();
  }

  Future<void> setTun(bool v) async {
    settings.tun = v;
    notifyListeners();
    if (isConnected) await reconnect();
  }

  Future<void> setSystemProxy(bool v) async {
    settings.systemProxy = v;
    notifyListeners();
    if (isConnected && !settings.tun) {
      v
          ? await SystemProxy.enable(settings.mixedPort)
          : await SystemProxy.disable();
    }
  }

  Future<void> setAllowLan(bool v) async {
    settings.allowLan = v;
    notifyListeners();
    await _api?.patchConfig({'allow-lan': v});
  }

  Future<void> setSniSpoofing(bool v) async {
    settings.sniSpoofing = v;
    notifyListeners();
    if (isConnected) await reconnect();
  }

  Future<void> setMixedPort(int port) async {
    settings.mixedPort = port;
    notifyListeners();
    if (isConnected) await reconnect();
  }

  void setThemeMode(ThemeMode m) {
    settings.themeMode = m;
    notifyListeners();
  }

  void setSeed(Color c) {
    settings.seedColor = c;
    settings.systemColor = false;
    notifyListeners();
  }

  void setSystemColor(bool v) {
    settings.systemColor = v;
    notifyListeners();
  }

  void setVariant(DynamicSchemeVariant v) {
    settings.schemeVariant = v;
    notifyListeners();
  }

  void clearError() {
    error = null;
    skipped = const [];
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget
              as AppScope)
          .notifier!;
}
