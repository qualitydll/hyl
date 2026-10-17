import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'mihomo_api.dart';

/// Runs the mihomo binary as a child process.
class MihomoCore {
  Process? _process;
  final _output = <String>[];
  void Function(String line)? onLine;
  void Function(int code)? onExit;

  bool get isRunning => _process != null;

  static String get binaryName => Platform.isWindows ? 'mihomo.exe' : 'mihomo';

  static Future<String?> locate({
    String? customPath,
    required String dataDir,
  }) async {
    final candidates = <String>[
      if (customPath != null && customPath.isNotEmpty) customPath,
      if (Platform.environment['BREW_CORE'] != null)
        Platform.environment['BREW_CORE']!,
      p.join(p.dirname(Platform.resolvedExecutable), 'core', binaryName),
      p.join(p.dirname(Platform.resolvedExecutable), binaryName),
      p.join(dataDir, 'core', binaryName),
    ];
    for (final c in candidates) {
      if (await File(c).exists()) return c;
    }
    try {
      final res = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'mihomo',
      ]);
      if (res.exitCode == 0) {
        final first = (res.stdout as String)
            .split(RegExp(r'[\r\n]+'))
            .first
            .trim();
        if (first.isNotEmpty) return first;
      }
    } catch (_) {}
    return null;
  }

  /// Validates a config with `mihomo -t`. Returns null when valid, otherwise
  /// the core's error message (e.g. `proxy 3: invalid REALITY public key`).
  static Future<String?> check({
    required String binary,
    required String homeDir,
    required String configPath,
  }) async {
    final res = await Process.run(binary, [
      '-t',
      '-d',
      homeDir,
      '-f',
      configPath,
    ]);
    if (res.exitCode == 0) return null;
    final out = '${res.stdout}\\n${res.stderr}'.trim();
    final msgs = RegExp(r'level=(?:error|fatal) msg="((?:[^"\\\\]|\\\\.)*)"')
        .allMatches(out)
        .map((m) => m.group(1)!)
        .map((message) => message.trim())
        .where((message) => message.isNotEmpty)
        .toList();
    // Some Mihomo builds emit an empty structured message while writing the
    // useful validation reason to another output line. Never hide that reason.
    if (msgs.isNotEmpty) return msgs.last;
    if (out.isNotEmpty) return out;
    return 'Mihomo завершил проверку с кодом ${res.exitCode}, но не вывел причину. '
        'Проверьте журнал приложения и файл конфигурации.';
  }

  Future<void> start({
    required String binary,
    required String homeDir,
    required String configPath,
    required MihomoApi api,
  }) async {
    await stop();
    _output.clear();
    final proc = await Process.start(binary, [
      '-d',
      homeDir,
      '-f',
      configPath,
    ], workingDirectory: homeDir);
    _process = proc;
    var exited = false;
    int? exitCode;
    void handle(String line) {
      _output.add(line);
      if (_output.length > 50) _output.removeAt(0);
      onLine?.call(line);
    }

    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(handle);
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(handle);
    unawaited(
      proc.exitCode.then((code) {
        exited = true;
        exitCode = code;
        if (identical(_process, proc)) {
          _process = null;
          onExit?.call(code);
        }
      }),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      if (exited) {
        throw CoreStartException(
          'Ядро завершилось с кодом $exitCode',
          _output.join('\n'),
        );
      }
      try {
        await api.version();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    await stop();
    throw CoreStartException(
      'Ядро не ответило за 15 секунд',
      _output.join('\n'),
    );
  }

  Future<void> stop() async {
    final proc = _process;
    if (proc == null) return;
    _process = null;
    proc.kill();
    try {
      await proc.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      proc.kill(ProcessSignal.sigkill);
    }
  }
}

class CoreStartException implements Exception {
  CoreStartException(this.message, this.output);
  final String message;
  final String output;
  @override
  String toString() => output.isEmpty ? message : '$message\n$output';
}

class CoreConfigException implements Exception {
  CoreConfigException(this.message);
  final String message;
  @override
  String toString() => 'Ядро не приняло конфигурацию: $message';
}
