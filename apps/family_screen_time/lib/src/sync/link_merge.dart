/// A device set up on its own, joining other devices, or leaving them:
/// what of its family it brings, and what it keeps.
library;

import 'dart:convert';

import 'package:screentime_engine/screentime_engine.dart';

import '../store.dart';

typedef _Json = Map<String, Object?>;

_Json _copy(Object? j) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(j)) as Map);

List<_Json> _list(Object? v) => [
  for (final i in v as List<Object?>? ?? const []) _copy(i),
];

/// What the linked devices' family ([group]) becomes with what this device
/// had on its own ([local]).
///
/// [localChild] is this device's child here, [groupChild] the child the
/// parent chose for it when linking it ([newChild]: a child the other
/// devices did not know). The child's groups of apps, and calendars, of the same name
/// are merged, the others' winning on everything else. A new child comes
/// with all their rules. For a known child, this device's rules are kept
/// only when [keepRules], for this device only ([deviceId]).
FamilyData mergeJoining({
  required FamilyData group,
  required FamilyData local,
  required String? localChild,
  required String? groupChild,
  required bool newChild,
  required bool keepRules,
  required String deviceId,
}) {
  if (localChild == null || groupChild == null) return group;
  final g = _copy(ownGroups(group).toJson());
  final l = _copy(ownGroups(local).toJson());
  final lChildren = _list(l['children']);
  final gChildren = _list(g['children']);
  final mine = lChildren.where((c) => c['id'] == localChild).firstOrNull;
  if (mine == null) return group;
  final known = gChildren.indexWhere((c) => c['id'] == groupChild);
  final isNew = newChild || known < 0;
  final bring = isNew || keepRules;

  // The child: a new one keeps what was set here (volume…), under the
  // name the parent gave when linking.
  if (isNew) {
    final child = {
      ...mine,
      'id': groupChild,
      if (known >= 0) 'name': gChildren[known]['name'],
    };
    if (known >= 0) {
      gChildren[known] = child;
    } else {
      gChildren.add(child);
    }
    g['children'] = gChildren;
  }

  final gConfig = _copy(g['config']);
  final lConfig = _copy(l['config']);

  // The child's groups of apps, matched by name with theirs there: the
  // apps installed here join them.
  final gGroups = _copy(gConfig['appGroups']);
  final gNames = Map<String, Object?>.from(g['groupNames'] as Map? ?? {});
  final gOwners = Map<String, Object?>.from(g['groupOwners'] as Map? ?? {});
  final lGroups = _copy(lConfig['appGroups']);
  final lNames = Map<String, Object?>.from(l['groupNames'] as Map? ?? {});
  final lOwners = Map<String, Object?>.from(l['groupOwners'] as Map? ?? {});
  String norm(Object? s) => (s as String? ?? '').trim().toLowerCase();
  final groupIds = <String, String>{};
  final theirs = {
    for (final id in {...gGroups.keys, ...gNames.keys})
      if (gOwners[id] == groupChild) id,
  };
  for (final e in lGroups.entries) {
    if (lOwners[e.key] != localChild) continue;
    final name = lNames[e.key] ?? e.key;
    final match = theirs
        .where((id) => norm(gNames[id] ?? id) == norm(name))
        .firstOrNull;
    final apps = {for (final a in e.value as List<Object?>) a as String};
    if (match != null) {
      groupIds[e.key] = match;
      gGroups[match] = ({
        ...?(gGroups[match] as List<Object?>?)?.cast<String>(),
        ...apps,
      }.toList()..sort());
    } else if (bring) {
      final id = gGroups.containsKey(e.key) || gNames.containsKey(e.key)
          ? newId()
          : e.key;
      groupIds[e.key] = id;
      gGroups[id] = apps.toList()..sort();
      if (lNames[e.key] != null) gNames[id] = lNames[e.key];
      gOwners[id] = groupChild;
    }
  }
  gConfig['appGroups'] = gGroups;
  g['groupNames'] = gNames;
  g['groupOwners'] = gOwners;

  // Apps always allowed, or within the hours: either device's choice.
  for (final k in ['alwaysAllowed', 'allowedInHours']) {
    final both = {
      ...?(gConfig[k] as List<Object?>?)?.cast<String>(),
      ...?(lConfig[k] as List<Object?>?)?.cast<String>(),
    };
    if (both.isNotEmpty) gConfig[k] = both.toList()..sort();
  }

  // Names given to apps here, unless the others named them already.
  final gAppNames = Map<String, Object?>.from(g['appNames'] as Map? ?? {});
  for (final e in (l['appNames'] as Map? ?? {}).entries) {
    gAppNames.putIfAbsent(e.key as String, () => e.value);
  }
  if (gAppNames.isNotEmpty) g['appNames'] = gAppNames;

  // Calendars, matched by name.
  final gProfiles = _list(gConfig['profiles']);
  final profileIds = <String, String>{};
  if (bring) {
    for (final p in _list(lConfig['profiles'])) {
      final match = gProfiles
          .where((q) => norm(q['name']) == norm(p['name']))
          .firstOrNull;
      if (match != null) {
        profileIds[p['id'] as String] = match['id'] as String;
        continue;
      }
      final id = gProfiles.any((q) => q['id'] == p['id'])
          ? newId()
          : p['id'] as String;
      profileIds[p['id'] as String] = id;
      gProfiles.add({...p, 'id': id});
    }
  }
  gConfig['profiles'] = gProfiles;
  g['config'] = gConfig;

  if (!bring) return FamilyData.fromJson(g);

  _Json? target(Object? t) {
    if (t == null) return null;
    final j = _copy(t);
    if (j['kind'] == 'group') j['id'] = groupIds[j['id']] ?? j['id'];
    return j;
  }

  // The rules of this device's child.
  final gState = _copy(g['state']);
  final lState = _copy(l['state']);
  final gRules = _list(gState['rules']);
  final taken = {for (final r in gRules) r['id']};
  final ruleIds = <String, String>{};
  for (final r in _list(lState['rules'])) {
    if (r['childId'] != localChild) continue;
    final id = taken.contains(r['id']) ? newId() : r['id'] as String;
    ruleIds[r['id'] as String] = id;
    final device = _copy(r['deviceTarget'] ?? const {'kind': 'all'});
    gRules.add({
      ...r,
      'id': id,
      'childId': groupChild,
      'appTarget': target(r['appTarget']) ?? const {'kind': 'all'},
      if (r['profileId'] != null)
        'profileId': profileIds[r['profileId']] ?? r['profileId'],
      // A known child: the others' rules apply, these only here.
      'deviceTarget': isNew && device['kind'] == 'one'
          ? device
          : isNew
          ? const {'kind': 'all'}
          : {'kind': 'one', 'id': deviceId},
    });
  }
  gState['rules'] = gRules;

  // A new child's bonuses, breaks and unlocks come too.
  if (isNew) {
    for (final k in [
      'bonuses',
      'temporaryBlocks',
      'dayUnlocks',
      'hoursUnlocks',
    ]) {
      final items = _list(gState[k]);
      for (final i in _list(lState[k])) {
        if (i['childId'] != localChild) continue;
        items.add({
          ...i,
          'childId': groupChild,
          if (i['ruleId'] != null)
            'ruleId': ruleIds[i['ruleId']] ?? i['ruleId'],
          if (i['appTarget'] != null) 'appTarget': target(i['appTarget']),
          if (k == 'temporaryBlocks') 'deviceTarget': const {'kind': 'all'},
        });
      }
      gState[k] = items;
    }
    final injected = _list(g['injected']);
    for (final u in _list(l['injected'])) {
      if (u['childId'] != localChild) continue;
      injected.add({
        ...u,
        'childId': groupChild,
        'injectedTarget': target(u['injectedTarget']),
      });
    }
    g['injected'] = injected;
  }
  g['state'] = gState;

  // The record of the limits the child set here.
  final log = _list(g['selfLimitLog']);
  for (final e in _list(l['selfLimitLog'])) {
    final id = ruleIds[e['ruleId']];
    if (id == null) continue;
    log.add({...e, 'ruleId': id, 'target': target(e['target'])});
  }
  g['selfLimitLog'] = log;
  return FamilyData.fromJson(g);
}

/// What a device leaving the others keeps: its child, their groups of
/// apps, their rules that apply here, and the calendars.
FamilyData keepOnLeaving(FamilyData family, String childId, String deviceId) {
  final f = ownGroups(family);
  final s = f.state;
  bool here(DeviceTarget t) => t.covers(deviceId, f.config.deviceGroups);
  final rules = [
    for (final r in s.rules)
      if (r.childId == childId && here(r.deviceTarget)) r,
  ];
  final ruleIds = {for (final r in rules) r.id};
  final groups = f.groupsOf(childId).keys.toSet();
  return f.copyWith(
    config: f.config.copyWith(
      appGroups: {
        for (final e in f.config.appGroups.entries)
          if (groups.contains(e.key)) e.key: e.value,
      },
    ),
    groupNames: {
      for (final e in f.groupNames.entries)
        if (groups.contains(e.key)) e.key: e.value,
    },
    groupOwners: {for (final id in groups) id: childId},
    children: [
      for (final c in f.children)
        if (c.id == childId) c,
    ],
    state: s.copyWith(
      rules: rules,
      bonuses: [
        for (final b in s.bonuses)
          if (b.childId == childId) b,
      ],
      temporaryBlocks: [
        for (final b in s.temporaryBlocks)
          if (b.childId == childId && here(b.deviceTarget)) b,
      ],
      dayUnlocks: [
        for (final u in s.dayUnlocks)
          if (u.childId == childId) u,
      ],
      hoursUnlocks: [
        for (final u in s.hoursUnlocks)
          if (u.childId == childId) u,
      ],
    ),
    injected: [
      for (final u in f.injected)
        if (u.childId == childId) u,
    ],
    selfLimitLog: [
      for (final e in f.selfLimitLog)
        if (ruleIds.contains(e.ruleId)) e,
    ],
  );
}
