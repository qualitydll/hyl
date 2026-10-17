
import 'dart:io';
import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../state/models.dart';

enum _Tab { home, nodes, profiles, activity, settings }

class CrewShell extends StatefulWidget {
  const CrewShell({super.key, required this.state});
  final AppState state;
  @override
  State<CrewShell> createState() => _CrewShellState();
}

class _CrewShellState extends State<CrewShell> {
  _Tab tab = _Tab.home;
  @override
  Widget build(BuildContext context) {
    final desktop = !Platform.isAndroid && MediaQuery.sizeOf(context).width >= 720;
    final state = widget.state;
    final page = switch (tab) {
      _Tab.home => _Home(state: state),
      _Tab.nodes => _Nodes(state: state),
      _Tab.profiles => _Profiles(state: state),
      _Tab.activity => _Activity(state: state),
      _Tab.settings => _Settings(state: state),
    };
    final duration = Duration(milliseconds: state.settings.reducedMotion ? 0 : state.settings.animationDuration);
    return Scaffold(
      body: SafeArea(child: Row(children: [
        if (desktop) Container(
          width: 72, margin: const EdgeInsets.fromLTRB(10, 12, 0, 12),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(25)),
          child: Column(children: [
            const SizedBox(height: 14), const _Mark(), const SizedBox(height: 18),
            for (final t in _Tab.values) Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: IconButton.filledTonal(tooltip: _title(t), isSelected: tab == t, onPressed: () => setState(() => tab = t), icon: Icon(_icon(t))),
            ),
            const Spacer(), const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('0.1', style: TextStyle(fontSize: 11))),
          ]),
        ),
        Expanded(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 12, 18, 8), child: Row(children: [
            if (!desktop) ...[const _Mark(), const SizedBox(width: 9), const Text('crew', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -.7))],
            const Spacer(), _Status(state: state),
            IconButton(tooltip: 'Профили', onPressed: () => setState(() => tab = _Tab.profiles), icon: const Icon(Icons.layers_outlined)),
            IconButton(tooltip: 'Настройки', onPressed: () => setState(() => tab = _Tab.settings), icon: const Icon(Icons.tune_rounded)),
          ])),
          Expanded(child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: _curve(state.settings.motionPreset),
            transitionBuilder: (child, a) => FadeTransition(opacity: a, child: state.settings.motionPreset == 'fade' ? child : SlideTransition(position: Tween<Offset>(begin: const Offset(0, .02), end: Offset.zero).animate(a), child: child)),
            child: KeyedSubtree(key: ValueKey(tab), child: page),
          )),
        ])),
      ])),
      bottomNavigationBar: desktop ? null : NavigationBar(
        selectedIndex: tab.index, animationDuration: duration,
        onDestinationSelected: (i) => setState(() => tab = _Tab.values[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt_rounded), label: 'Домой'),
          NavigationDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub_rounded), label: 'Узлы'),
          NavigationDestination(icon: Icon(Icons.layers_outlined), selectedIcon: Icon(Icons.layers_rounded), label: 'Профили'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Трафик'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.tune_rounded), label: 'Настройки'),
        ],
      ),
    );
  }
}

Curve _curve(String v) => switch (v) { 'spring' => Curves.easeOutBack, 'soft' => Curves.easeInOutSine, 'slide' => Curves.easeOutCubic, 'fade' => Curves.linear, _ => Curves.easeInOutCubicEmphasized };
String _title(_Tab t) => switch (t) { _Tab.home => 'Главная', _Tab.nodes => 'Узлы', _Tab.profiles => 'Профили', _Tab.activity => 'Трафик', _Tab.settings => 'Настройки' };
IconData _icon(_Tab t) => switch (t) { _Tab.home => Icons.bolt_rounded, _Tab.nodes => Icons.hub_rounded, _Tab.profiles => Icons.layers_rounded, _Tab.activity => Icons.insights_rounded, _Tab.settings => Icons.tune_rounded };

class _Mark extends StatelessWidget {
  const _Mark();
  @override
  Widget build(BuildContext context) => Container(width: 34, height: 34, decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), gradient: const LinearGradient(colors: [Color(0xFFFFA15C), Color(0xFFEE6B32), Color(0xFFB74725)])), child: const Icon(Icons.hub_rounded, color: Colors.white, size: 19));
}
class _Status extends StatelessWidget {
  const _Status({required this.state}); final AppState state;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: state.isConnected ? Theme.of(context).colorScheme.tertiaryContainer : Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(99)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: state.isConnected ? const Color(0xFF29BD82) : Theme.of(context).colorScheme.onSurfaceVariant)), const SizedBox(width: 7), Text(state.isConnected ? 'Защищено' : state.isBusy ? 'Подключение' : 'Отключено', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700))]));
}

class _Home extends StatelessWidget {
  const _Home({required this.state}); final AppState state;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = switch (state.settings.connectButtonSize) { 0 => 130.0, 2 => 190.0, _ => 160.0 };
    return ListView(padding: EdgeInsets.all(state.settings.compactDensity ? 14 : 18), children: [
      Text('Твоя сеть. Твои правила.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1)),
      const SizedBox(height: 5), Text('Спокойное подключение без лишнего шума.', style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 18),
      _Card(child: Column(children: [
        AnimatedSwitcher(duration: Duration(milliseconds: state.settings.reducedMotion ? 0 : state.settings.animationDuration), child: Column(key: ValueKey(state.status), children: [
          Text(state.isConnected ? 'Подключено' : state.isBusy ? 'Подключаемся' : 'Готов к подключению', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5), Text(state.isConnected ? 'Трафик идёт через выбранный маршрут.' : state.profiles.isEmpty ? 'Добавь профиль, чтобы начать.' : 'Выбери узел или подключись в один тап.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ])),
        const SizedBox(height: 18),
        _Power(size: size, active: state.isConnected, busy: state.isBusy, reduced: state.settings.reducedMotion, onTap: state.isBusy ? null : state.toggle),
        const SizedBox(height: 10), Text(state.isConnected ? 'Нажми, чтобы отключиться' : 'Нажми, чтобы подключиться', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 18),
        Row(children: [Expanded(child: _Metric(icon: Icons.download_rounded, label: 'Входящий', value: formatSpeed(state.traffic.currentDown))), const SizedBox(width: 9), Expanded(child: _Metric(icon: Icons.upload_rounded, label: 'Исходящий', value: formatSpeed(state.traffic.currentUp)))]),
      ])),
      const SizedBox(height: 12),
      _Card(child: Row(children: [const _IconTile(icon: Icons.public_rounded), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Текущий маршрут', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 4), Text(state.currentServer ?? 'Автоматический выбор', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(state.activeProfile?.name ?? 'Профиль не выбран', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ]))])),
      const SizedBox(height: 12),
      _Card(child: Row(children: [const _IconTile(icon: Icons.layers_rounded), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Активный профиль', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 4), Text(state.activeProfile?.name ?? 'Добавь подписку', style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(state.activeProfile == null ? 'Подписки и конфиги Mihomo' : state.activeProfile!.proxyCount.toString() + ' узлов', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ]))])),
      if (state.error != null) ...[const SizedBox(height: 12), _Card(child: Row(children: [Icon(Icons.error_outline, color: cs.error), const SizedBox(width: 8), Expanded(child: Text(state.error!)), IconButton(onPressed: state.clearError, icon: const Icon(Icons.close))]))],
    ]);
  }
}

class _Power extends StatefulWidget {
  const _Power({required this.size, required this.active, required this.busy, required this.reduced, required this.onTap});
  final double size; final bool active; final bool busy; final bool reduced; final VoidCallback? onTap;
  @override
  State<_Power> createState() => _PowerState();
}
class _PowerState extends State<_Power> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat(reverse: true);
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final color = widget.active ? const Color(0xFF29BD82) : Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(animation: c, builder: (context, _) {
      final pulse = widget.reduced ? 0.0 : c.value;
      return Semantics(button: true, label: widget.active ? 'Отключить VPN' : 'Подключить VPN', child: GestureDetector(onTap: widget.onTap, child: SizedBox(width: widget.size + 24, height: widget.size + 24, child: Stack(alignment: Alignment.center, children: [
        Container(width: widget.size + 16 + pulse * 8, height: widget.size + 16 + pulse * 8, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: .18)))),
        Container(width: widget.size + pulse * 5, height: widget.size + pulse * 5, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .08 + pulse * .04))),
        AnimatedContainer(duration: Duration(milliseconds: widget.reduced ? 0 : 360), width: widget.size, height: widget.size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: widget.active ? const [Color(0xFF53E2A8), Color(0xFF179D6B)] : [color, Color.lerp(color, const Color(0xFF6846C7), .28)!]), boxShadow: [BoxShadow(color: color.withValues(alpha: .32 + pulse * .08), blurRadius: 28 + pulse * 8)]), child: Center(child: widget.busy ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Icon(widget.active ? Icons.check_rounded : Icons.power_settings_new_rounded, size: widget.size * .32, color: Colors.white))),
      ]))));
    });
  }
}

class _Nodes extends StatelessWidget {
  const _Nodes({required this.state}); final AppState state;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    const _Heading('Узлы', 'Выбирай маршрут и проверяй задержку.'),
    const SizedBox(height: 12),
    if (state.profiles.isEmpty) const _Empty(title: 'Сначала добавь профиль', subtitle: 'Вставь ссылку подписки в разделе «Профили».')
    else if (state.nodes.isEmpty) const _Empty(title: 'Узлы появятся после загрузки', subtitle: 'Подключись, чтобы получить список прокси.')
    else for (final g in state.groups.where((x) => x.isGroup)) _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      if (g.now != null) Text('Выбран: ' + g.now!, style: Theme.of(context).textTheme.bodySmall),
      for (final n in g.all.take(12)) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(n == g.now ? Icons.radio_button_checked : Icons.circle_outlined), title: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(state.nodes[n]?.type ?? 'Proxy'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [if (state.delays[n] != null) Text(state.delays[n].toString() + ' ms'), IconButton(tooltip: 'Проверить задержку', onPressed: state.testing.contains(n) ? null : () => state.testDelay(n), icon: const Icon(Icons.speed_rounded))]), onTap: g.isSelectable ? () => state.select(g.name, n) : null),
    ])),
  ]);
}

class _Profiles extends StatefulWidget {
  const _Profiles({required this.state}); final AppState state;
  @override
  State<_Profiles> createState() => _ProfilesState();
}
class _ProfilesState extends State<_Profiles> {
  final url = TextEditingController(); final name = TextEditingController(); bool busy = false;
  @override
  void dispose() { url.dispose(); name.dispose(); super.dispose(); }
  Future<void> add() async {
    if (url.text.trim().isEmpty) return;
    setState(() => busy = true);
    try { await widget.state.addProfile(url.text.trim(), name: name.text.trim().isEmpty ? null : name.text.trim()); url.clear(); name.clear(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Профиль добавлен'))); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось добавить: ' + e.toString()))); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    const _Heading('Профили', 'Подписки и конфигурации в одном месте.'), const SizedBox(height: 12),
    _Card(child: Column(children: [
      TextField(controller: name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Название (необязательно)', prefixIcon: Icon(Icons.label_outline_rounded))),
      const SizedBox(height: 9), TextField(controller: url, keyboardType: TextInputType.url, onSubmitted: (_) => add(), decoration: const InputDecoration(labelText: 'Ссылка подписки / конфигурации', hintText: 'https://…', prefixIcon: Icon(Icons.link_rounded))),
      const SizedBox(height: 12), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : add, icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_rounded), label: Text(busy ? 'Добавляем…' : 'Добавить профиль'))),
    ])),
    const SizedBox(height: 12),
    if (widget.state.profiles.isEmpty) const _Empty(title: 'Пока пусто', subtitle: 'Добавь ссылку — Crew импортирует поддерживаемые узлы.')
    else for (final p in widget.state.profiles) _Card(margin: const EdgeInsets.only(bottom: 9), child: Row(children: [
      const _IconTile(icon: Icons.layers_rounded), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), Text(p.proxyCount.toString() + ' узлов · ' + timeAgo(p.updatedAt), style: Theme.of(context).textTheme.bodySmall)])),
      if (widget.state.activeProfile?.id == p.id) const Icon(Icons.check_circle_rounded, color: Colors.green) else IconButton(tooltip: 'Активировать', onPressed: () => widget.state.setActiveProfile(p), icon: const Icon(Icons.radio_button_unchecked_rounded)),
      PopupMenuButton<String>(onSelected: (v) { if (v == 'delete') widget.state.deleteProfile(p); }, itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Удалить'))]),
    ])),
  ]);
}

class _Activity extends StatelessWidget {
  const _Activity({required this.state}); final AppState state;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    const _Heading('Активность', 'Трафик, соединения и события ядра.'), const SizedBox(height: 12),
    Row(children: [Expanded(child: _Metric(icon: Icons.download_rounded, label: 'Получено', value: formatBytes(state.traffic.totalDown))), const SizedBox(width: 9), Expanded(child: _Metric(icon: Icons.upload_rounded, label: 'Отправлено', value: formatBytes(state.traffic.totalUp)))]),
    const SizedBox(height: 12), _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Соединения (' + state.activeConnections.length.toString() + ')', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      if (state.connectionsError != null) Text(state.connectionsError!) else if (state.activeConnections.isEmpty) const Text('Нет активных соединений.') else for (final c in state.activeConnections.take(10)) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.lan_rounded), title: Text(c.host + ':' + c.port, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(c.network + ' · ' + c.rule, maxLines: 1, overflow: TextOverflow.ellipsis)),
      Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: state.refreshConnections, icon: const Icon(Icons.refresh_rounded), label: const Text('Обновить'))),
    ])),
    const SizedBox(height: 12), _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Expanded(child: Text('Журнал ядра', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))), TextButton(onPressed: state.logs.clear, child: const Text('Очистить'))]),
      if (state.logs.entries.isEmpty) const Text('События появятся после запуска ядра.') else for (final e in state.logs.entries.toList().reversed.take(15)) Padding(padding: const EdgeInsets.only(top: 8), child: Text(e.message, style: Theme.of(context).textTheme.bodySmall)),
    ])),
  ]);
}

class _Settings extends StatelessWidget {
  const _Settings({required this.state}); final AppState state;
  void save(BuildContext context, VoidCallback change) { change(); state.notifyListeners(); }
  @override
  Widget build(BuildContext context) {
    final s = state.settings; final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(18), children: [
      const _Heading('Настройки', 'Настрой Crew под себя.'), const SizedBox(height: 12),
      _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Внешний вид', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Цвет системы'), value: s.systemColor, onChanged: (v) => save(context, () => state.setSystemColor(v))),
        Wrap(spacing: 9, children: seedPalette.map((c) => InkWell(onTap: () => save(context, () => state.setSeed(c)), customBorder: const CircleBorder(), child: Container(width: 31, height: 31, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: s.seedColor.toARGB32() == c.toARGB32() ? cs.onSurface : Colors.transparent, width: 2.4)), child: s.seedColor.toARGB32() == c.toARGB32() ? const Icon(Icons.check, size: 17, color: Colors.white) : null))).toList()),
        const SizedBox(height: 12),
        SegmentedButton<ThemeMode>(segments: const [ButtonSegment(value: ThemeMode.system, label: Text('Авто')), ButtonSegment(value: ThemeMode.light, label: Text('Светлая')), ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная'))], selected: {s.themeMode}, onSelectionChanged: (v) => save(context, () => state.setThemeMode(v.first))),
      ])),
      const SizedBox(height: 12), _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Анимации и доступность', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Уменьшить движение'), subtitle: const Text('Отключает декоративную анимацию'), value: s.reducedMotion, onChanged: (v) => save(context, () { s.reducedMotion = v; s.animationDuration = v ? 0 : 360; })),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Стиль движения'), trailing: DropdownButton<String>(value: s.motionPreset, underline: const SizedBox.shrink(), items: const [DropdownMenuItem(value: 'fluid', child: Text('Fluid')), DropdownMenuItem(value: 'soft', child: Text('Soft')), DropdownMenuItem(value: 'spring', child: Text('Spring')), DropdownMenuItem(value: 'slide', child: Text('Slide')), DropdownMenuItem(value: 'fade', child: Text('Fade'))], onChanged: (v) { if (v != null) save(context, () => s.motionPreset = v); })),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Длительность переходов'), subtitle: Text(s.animationDuration.toString() + ' мс'), trailing: SizedBox(width: 130, child: Slider(min: 0, max: 900, divisions: 9, value: s.animationDuration.toDouble(), onChanged: (v) => save(context, () => s.animationDuration = v.round()))),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Компактный интерфейс'), value: s.compactDensity, onChanged: (v) => save(context, () => s.compactDensity = v)),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Размер кнопки'), trailing: SegmentedButton<int>(segments: const [ButtonSegment(value: 0, label: Text('S')), ButtonSegment(value: 1, label: Text('M')), ButtonSegment(value: 2, label: Text('L'))], selected: {s.connectButtonSize}, onSelectionChanged: (v) => save(context, () => s.connectButtonSize = v.first))),
      ])),
      const SizedBox(height: 12), _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Подключение', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('TUN на Windows'), subtitle: const Text('Перехват системного трафика'), value: s.tun, onChanged: (v) => state.setTun(v)),
        if (!Platform.isAndroid) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Системный прокси'), value: s.systemProxy, onChanged: (v) => state.setSystemProxy(v)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Разрешить LAN'), value: s.allowLan, onChanged: (v) => state.setAllowLan(v)),
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'rule', label: Text('Правила')), ButtonSegment(value: 'global', label: Text('Глобально')), ButtonSegment(value: 'direct', label: Text('Напрямую'))], selected: {s.mode}, onSelectionChanged: (v) => state.setMode(v.first)),
        const SizedBox(height: 8), Text('Mihomo: ' + (state.coreVersion ?? (Platform.isAndroid ? 'встроено' : 'не найдено')), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ])),
    ]);
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.subtitle); final String title; final String subtitle;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.8)), const SizedBox(height: 4), Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))]);
}
class _Card extends StatelessWidget {
  const _Card({required this.child, this.margin}); final Widget child; final EdgeInsetsGeometry? margin;
  @override
  Widget build(BuildContext context) => Container(margin: margin, padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 430 ? 14 : 17), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: .92), borderRadius: BorderRadius.circular(23), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .3))), child: child);
}
class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value}); final IconData icon; final String label; final String value;
  @override
  Widget build(BuildContext context) => _Card(child: Row(children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.labelSmall), const SizedBox(height: 3), FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)))]))]));
}
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon}); final IconData icon;
  @override
  Widget build(BuildContext context) => Container(width: 42, height: 42, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer));
}
class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.subtitle}); final String title; final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(26), child: Column(children: [const Icon(Icons.hub_outlined, size: 38), const SizedBox(height: 12), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(subtitle, textAlign: TextAlign.center)]));
}
