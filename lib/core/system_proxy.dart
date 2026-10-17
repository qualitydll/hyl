import 'dart:io';

const _bypass =
    'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.2*;172.30.*;172.31.*;192.168.*;<local>';

/// Sets or clears the OS-level HTTP proxy.
class SystemProxy {
  static Future<void> enable(int port) async {
    if (Platform.isWindows) {
      await _windows(true, port);
    } else if (Platform.isLinux) {
      await _gsettings([
        ['org.gnome.system.proxy', 'mode', 'manual'],
        for (final kind in ['http', 'https', 'socks']) ...[
          ['org.gnome.system.proxy.$kind', 'host', '127.0.0.1'],
          ['org.gnome.system.proxy.$kind', 'port', '$port'],
        ],
      ]);
    } else if (Platform.isMacOS) {
      await _macos(true, port);
    }
  }

  static Future<void> disable() async {
    if (Platform.isWindows) {
      await _windows(false, 0);
    } else if (Platform.isLinux) {
      await _gsettings([
        ['org.gnome.system.proxy', 'mode', 'none'],
      ]);
    } else if (Platform.isMacOS) {
      await _macos(false, 0);
    }
  }

  static Future<void> _windows(bool on, int port) async {
    const key =
        r'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    final script =
        '''
\$k = '$key'
Set-ItemProperty -Path \$k -Name ProxyEnable -Value ${on ? 1 : 0}
${on ? "Set-ItemProperty -Path \$k -Name ProxyServer -Value '127.0.0.1:$port'\nSet-ItemProperty -Path \$k -Name ProxyOverride -Value '$_bypass'" : ''}
\$sig = '[DllImport("wininet.dll", SetLastError = true)] public static extern bool InternetSetOption(System.IntPtr h, int o, System.IntPtr b, int l);'
\$t = Add-Type -MemberDefinition \$sig -Name WinInet -Namespace Crew -PassThru
[void]\$t::InternetSetOption([System.IntPtr]::Zero, 39, [System.IntPtr]::Zero, 0)
[void]\$t::InternetSetOption([System.IntPtr]::Zero, 37, [System.IntPtr]::Zero, 0)
''';
    await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
  }

  static Future<void> _gsettings(List<List<String>> sets) async {
    for (final s in sets) {
      try {
        await Process.run('gsettings', ['set', ...s]);
      } catch (_) {}
    }
  }

  static Future<void> _macos(bool on, int port) async {
    final res = await Process.run('networksetup', ['-listallnetworkservices']);
    final services = (res.stdout as String)
        .split('\n')
        .skip(1)
        .where((s) => s.trim().isNotEmpty && !s.startsWith('*'));
    for (final svc in services) {
      if (on) {
        await Process.run('networksetup', [
          '-setwebproxy',
          svc,
          '127.0.0.1',
          '$port',
        ]);
        await Process.run('networksetup', [
          '-setsecurewebproxy',
          svc,
          '127.0.0.1',
          '$port',
        ]);
      } else {
        await Process.run('networksetup', ['-setwebproxystate', svc, 'off']);
        await Process.run('networksetup', [
          '-setsecurewebproxystate',
          svc,
          'off',
        ]);
      }
    }
  }
}

/// Windows elevation helpers (TUN requires administrator rights).
class Elevation {
  static Future<bool> isAdmin() async {
    if (Platform.isWindows) {
      final r = await Process.run('net', ['session']);
      return r.exitCode == 0;
    }
    if (Platform.isLinux || Platform.isMacOS) {
      final r = await Process.run('id', ['-u']);
      return (r.stdout as String).trim() == '0';
    }
    return false;
  }

  static Future<bool> relaunchAsAdmin() async {
    if (!Platform.isWindows) return false;
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "Start-Process -FilePath '$exe' -Verb RunAs",
    ]);
    return r.exitCode == 0;
  }
}
