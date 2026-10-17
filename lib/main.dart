import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'brand.dart';
import 'state/app_state.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(760, 790),
      minimumSize: Size(680, 660),
      maximumSize: Size(980, 980),
      center: true,
      title: 'Crew',
      backgroundColor: Color(0xFF101114),
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(CrewBootstrap(state: state));
}

class CrewBootstrap extends StatefulWidget {
  const CrewBootstrap({super.key, required this.state});
  final AppState state;

  @override
  State<CrewBootstrap> createState() => _CrewBootstrapState();
}

class _CrewBootstrapState extends State<CrewBootstrap> {
  Object? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await widget.state.init();
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(seedColor: kCrewOrange, brightness: Brightness.dark),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF101114),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _CrewMark(size: 68),
                  const SizedBox(height: 24),
                  Text(_error == null ? 'Crew' : 'Не удалось запустить Crew',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (_error == null)
                    const LinearProgressIndicator()
                  else ...[
                    Text(_error.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => setState(() { _error = null; _ready = false; _initialize(); }), child: const Text('Повторить')),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return CrewApp(state: widget.state);
  }
}

class _CrewMark extends StatelessWidget {
  const _CrewMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * 0.34),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFA15C), Color(0xFFEE6B32), Color(0xFFB74725)],
      ),
      boxShadow: [BoxShadow(color: const Color(0xFFEE6B32).withValues(alpha: 0.22), blurRadius: size * 0.42, spreadRadius: 1)],
    ),
    child: Icon(Icons.hub_rounded, color: Colors.white, size: size * 0.52),
  );
}

class CrewApp extends StatelessWidget {
  const CrewApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            final s = state.settings;
            final seed = s.systemColor ? (darkDynamic?.primary ?? kCrewOrange) : s.seedColor;
            return MaterialApp(
              title: 'Crew',
              debugShowCheckedModeBanner: false,
              themeMode: s.themeMode,
              theme: buildTheme(crewScheme(seed, Brightness.light, s.schemeVariant)),
              darkTheme: buildTheme(crewScheme(seed, Brightness.dark, s.schemeVariant)),
              themeAnimationDuration: Duration(milliseconds: s.reducedMotion ? 0 : s.animationDuration),
              home: CrewShell(state: state),
            );
          },
        ),
      ),
    );
  }
}
