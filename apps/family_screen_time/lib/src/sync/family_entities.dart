/// The family's data cut into entities for the sync log, and put back
/// together: each rule, bonus, group or child is merged on its own, field
/// by field.
library;

import 'package:crypto/crypto.dart';
import 'package:screentime_sync/screentime_sync.dart';

import '../store.dart';

/// Keys of the entities, by kind.
abstract final class FamilyKeys {
  /// Family-wide settings.
  static const family = 'family';
  static const child = 'child/';
  static const group = 'group/';
  static const deviceGroup = 'deviceGroup/';
  static const appName = 'appName/';
  static const profile = 'profile/';
  static const rule = 'rule/';
  static const bonus = 'bonus/';
  static const temporaryBlock = 'temporaryBlock/';
  static const dayUnlock = 'dayUnlock/';
  static const familyBlock = 'familyBlock/';
  static const hoursUnlock = 'hoursUnlock/';
  static const injected = 'injected/';
  static const selfLimitLog = 'selfLimitLog/';

  /// State lists stored as one entity per item, by their `id`.
  static const stateLists = {
    'rules': rule,
    'bonuses': bonus,
    'temporaryBlocks': temporaryBlock,
    'dayUnlocks': dayUnlock,
    'familyBlocks': familyBlock,
    'hoursUnlocks': hoursUnlock,
  };
}

/// Id of an item that has none of its own: a hash of its content.
String contentId(Map<String, Object?> item) =>
    sha256.convert(canonicalBytes(item)).toString().substring(0, 24);

Map<String, Object?> _map(Object? v) =>
    v == null ? <String, Object?>{} : Map<String, Object?>.from(v as Map);

List<Map<String, Object?>> _items(Object? v) => [
  for (final i in v as List<Object?>? ?? const []) _map(i),
];

/// [f] as entities by key. Left out: what belongs to this device only (the
/// system components never blocked, which differ from one device to the
/// next).
Map<String, Map<String, Object?>> familyEntities(FamilyData f) {
  final j = f.toJson();
  final config = _map(j['config']);
  final state = _map(j['state']);
  final groups = _map(config['appGroups']);
  final names = _map(j['groupNames']);
  final owners = _map(j['groupOwners']);
  final children = _items(j['children']);
  final profiles = _items(config['profiles']);
  return {
    FamilyKeys.family: {
      'graceReminderMinutes': j['graceReminderMinutes'],
      'outOfTime': j['outOfTime'],
      'settingsParentOnly': j['settingsParentOnly'] ?? false,
      'alwaysAllowed': config['alwaysAllowed'],
      'allowedInHours': config['allowedInHours'] ?? const <String>[],
      'weekStart': config['weekStart'],
      'counting': config['counting'],
      'usageKeptDays': j['usageKeptDays'],
    },
    for (final (i, c) in children.indexed)
      '${FamilyKeys.child}${c['id']}': {...c, 'order': i},
    for (final id in {...groups.keys, ...names.keys})
      '${FamilyKeys.group}$id': {
        'apps': groups[id] ?? const <String>[],
        'name': ?names[id],
        'childId': ?owners[id],
      },
    for (final e in _map(config['deviceGroups']).entries)
      '${FamilyKeys.deviceGroup}${e.key}': {'devices': e.value},
    for (final e in _map(j['appNames']).entries)
      '${FamilyKeys.appName}${e.key}': {'name': e.value},
    for (final (i, p) in profiles.indexed)
      '${FamilyKeys.profile}${p['id']}': {...p, 'order': i},
    for (final list in FamilyKeys.stateLists.entries)
      for (final item in _items(state[list.key]))
        '${list.value}${item['id']}': item,
    for (final u in _items(j['injected']))
      '${FamilyKeys.injected}${contentId(u)}': u,
    for (final e in _items(j['selfLimitLog']))
      '${FamilyKeys.selfLimitLog}${contentId(e)}': e,
  };
}

/// The family put back together from [entities]. What belongs to this
/// device only is taken from [local].
FamilyData familyFromEntities(
  Map<String, Map<String, Object?>> entities,
  FamilyData local,
) {
  // Sorted by key: every device then builds the same lists.
  final keys = entities.keys.toList()..sort();
  Map<String, Map<String, Object?>> kind(String prefix) => {
    for (final k in keys)
      if (k.startsWith(prefix)) k.substring(prefix.length): entities[k]!,
  };
  List<Map<String, Object?>> ordered(String prefix) {
    final items = kind(prefix).values.toList()
      ..sort(
        (a, b) =>
            ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0),
      );
    return [
      for (final i in items) {...i}..remove('order'),
    ];
  }

  final defaults = const FamilyData().toJson();
  final defaultConfig = _map(defaults['config']);
  final family = entities[FamilyKeys.family] ?? const {};
  final groups = kind(FamilyKeys.group);
  final localConfig = _map(local.toJson()['config']);
  final json = <String, Object?>{
    'children': ordered(FamilyKeys.child),
    'config': {
      'appGroups': {
        for (final e in groups.entries) e.key: e.value['apps'] ?? const [],
      },
      'deviceGroups': {
        for (final e in kind(FamilyKeys.deviceGroup).entries)
          e.key: e.value['devices'] ?? const [],
      },
      'alwaysAllowed':
          family['alwaysAllowed'] ?? defaultConfig['alwaysAllowed'],
      'allowedInHours': family['allowedInHours'] ?? const [],
      'neverBlocked': localConfig['neverBlocked'],
      'profiles': ordered(FamilyKeys.profile),
      'weekStart': family['weekStart'] ?? defaultConfig['weekStart'],
      'counting': family['counting'] ?? defaultConfig['counting'],
    },
    'state': {
      for (final list in FamilyKeys.stateLists.entries)
        list.key: kind(list.value).values.toList(),
    },
    'groupNames': {
      for (final e in groups.entries)
        if (e.value['name'] != null) e.key: e.value['name'],
    },
    'groupOwners': {
      for (final e in groups.entries)
        if (e.value['childId'] != null) e.key: e.value['childId'],
    },
    'appNames': {
      for (final e in kind(FamilyKeys.appName).entries) e.key: e.value['name'],
    },
    'graceReminderMinutes':
        family['graceReminderMinutes'] ?? defaults['graceReminderMinutes'],
    'injected': kind(FamilyKeys.injected).values.toList(),
    'selfLimitLog': kind(FamilyKeys.selfLimitLog).values.toList()
      ..sort((a, b) => '${a['at']}'.compareTo('${b['at']}')),
    'outOfTime': family['outOfTime'] ?? defaults['outOfTime'],
    'settingsParentOnly': family['settingsParentOnly'] ?? false,
    'usageKeptDays': family['usageKeptDays'] ?? defaults['usageKeptDays'],
  };
  return FamilyData.fromJson(json);
}
