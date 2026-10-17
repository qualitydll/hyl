import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../brand.dart';

import 'models.dart';

class Settings {
  Settings(this._prefs);

  final SharedPreferences _prefs;

  ThemeMode get themeMode => ThemeMode.values[_prefs.getInt('themeMode') ?? 0];
  set themeMode(ThemeMode v) => _prefs.setInt('themeMode', v.index);

  /// Follow the OS accent color (Material You) instead of [seedColor].
  bool get systemColor => _prefs.getBool('systemColor') ?? false;
  set systemColor(bool v) => _prefs.setBool('systemColor', v);

  Color get seedColor {
    final v = _prefs.getInt('seedColor');
    return v == null ? kCrewOrange : Color(v);
  }

  set seedColor(Color c) => _prefs.setInt('seedColor', c.toARGB32());

  DynamicSchemeVariant get schemeVariant =>
      DynamicSchemeVariant.values[_prefs.getInt('schemeVariant') ??
          DynamicSchemeVariant.fidelity.index];
  set schemeVariant(DynamicSchemeVariant v) =>
      _prefs.setInt('schemeVariant', v.index);

  int get mixedPort => _prefs.getInt('mixedPort') ?? 7890;
  set mixedPort(int v) => _prefs.setInt('mixedPort', v);

  int get apiPort => _prefs.getInt('apiPort') ?? 9097;

  String get secret {
    var s = _prefs.getString('secret');
    if (s == null) {
      s = newId() + newId();
      _prefs.setString('secret', s);
    }
    return s;
  }

  String get mode => _prefs.getString('mode') ?? 'rule';
  set mode(String v) => _prefs.setString('mode', v);

  String get userRules => _prefs.getString('userRules') ?? '';
  set userRules(String v) => _prefs.setString('userRules', v);

  List<String> get domainRules => _prefs.getStringList('domainRules') ?? [];
  set domainRules(List<String> v) => _prefs.setStringList('domainRules', v);

  List<String> get favoriteServers =>
      _prefs.getStringList('favoriteServers') ?? [];
  set favoriteServers(List<String> v) =>
      _prefs.setStringList('favoriteServers', v);

  List<String> get recentServers =>
      _prefs.getStringList('recentServers') ?? [];
  set recentServers(List<String> v) => _prefs.setStringList('recentServers', v);

  bool get tun => _prefs.getBool('tun') ?? false;
  set tun(bool v) => _prefs.setBool('tun', v);

  bool get systemProxy => _prefs.getBool('systemProxy') ?? true;
  set systemProxy(bool v) => _prefs.setBool('systemProxy', v);

  bool get allowLan => _prefs.getBool('allowLan') ?? false;
  set allowLan(bool v) => _prefs.setBool('allowLan', v);

  bool get sniSpoofing => _prefs.getBool('sniSpoofing') ?? false;
  set sniSpoofing(bool v) => _prefs.setBool('sniSpoofing', v);

  String? get corePath => _prefs.getString('corePath');
  set corePath(String? v) =>
      v == null ? _prefs.remove('corePath') : _prefs.setString('corePath', v);

  bool get reducedMotion => _prefs.getBool('reducedMotion') ?? false;
  set reducedMotion(bool v) => _prefs.setBool('reducedMotion', v);

  int get animationDuration => _prefs.getInt('animationDuration') ?? 360;
  set animationDuration(int v) => _prefs.setInt('animationDuration', v.clamp(0, 900));

  String get motionPreset => _prefs.getString('motionPreset') ?? 'fluid';
  set motionPreset(String v) => _prefs.setString('motionPreset', v);

  bool get compactDensity => _prefs.getBool('compactDensity') ?? false;
  set compactDensity(bool v) => _prefs.setBool('compactDensity', v);

  int get connectButtonSize => _prefs.getInt('connectButtonSize') ?? 1;
  set connectButtonSize(int v) => _prefs.setInt('connectButtonSize', v.clamp(0, 2));

  bool get showTrafficChart => _prefs.getBool('showTrafficChart') ?? true;
  set showTrafficChart(bool v) => _prefs.setBool('showTrafficChart', v);

  String? get activeProfileId => _prefs.getString('activeProfile');
  set activeProfileId(String? v) => v == null
      ? _prefs.remove('activeProfile')
      : _prefs.setString('activeProfile', v);
}
