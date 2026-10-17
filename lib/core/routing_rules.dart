import 'config_builder.dart';
import 'link_parser.dart';

String normalizeDomainRule(
  String input, {
  required bool includeSubdomains,
  required String action,
  required List<String> allowedActions,
}) {
  final domain = input.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  final labels = domain.split('.');
  final valid = labels.length >= 2 &&
      labels.every(
        (label) =>
            label.length <= 63 &&
            RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
      ) &&
      domain.length <= 253;
  if (!valid) {
    throw FormatException(
      'Введите домен без схемы и пути, например example.com.',
    );
  }
  if (!allowedActions.contains(action)) {
    throw ArgumentError.value(action, 'action');
  }
  return '${includeSubdomains ? 'DOMAIN-SUFFIX' : 'DOMAIN'},$domain,$action';
}

List<String> routingActionsFor(ParsedSubscription subscription) {
  final config = baseConfigFor(subscription);
  final groups = config['proxy-groups'];
  final groupNames = <String>[
    if (groups is List)
      for (final group in groups)
        if (group is Map && group['name'] is String)
          (group['name'] as String).trim(),
  ];
  final actions = <String>{
    'DIRECT',
    'REJECT',
    ...groupNames.where((name) => name.isNotEmpty && name != 'GLOBAL'),
  }.toList();
  actions.sort((a, b) {
    if (a == 'DIRECT') return -1;
    if (b == 'DIRECT') return 1;
    if (a == 'REJECT') return -1;
    if (b == 'REJECT') return 1;
    if (a == kMainGroup) return -1;
    if (b == kMainGroup) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return actions;
}
