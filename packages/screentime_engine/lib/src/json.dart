/// JSON encoding of the engine's types, for local storage and, later, sync.
///
/// Conventions: durations are whole seconds, instants are milliseconds since
/// the Unix epoch (time-zone independent), calendar days are `YYYY-MM-DD`
/// strings, and time ranges are `[startMinute, endMinute]` pairs.
library;

import 'calendar.dart';
import 'engine.dart';
import 'modifiers.dart';
import 'rules.dart';
import 'schedule.dart';
import 'targets.dart';
import 'usage.dart';

typedef Json = Map<String, Object?>;

// --- Primitives -------------------------------------------------------------

int durationToJson(Duration d) => d.inSeconds;

Duration durationFromJson(Object? v) => Duration(seconds: (v as num).toInt());

Duration? optionalDuration(Object? v) => v == null ? null : durationFromJson(v);

int instantToJson(DateTime t) => t.millisecondsSinceEpoch;

DateTime instantFromJson(Object? v) =>
    DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

DateTime? optionalInstant(Object? v) => v == null ? null : instantFromJson(v);

String dayToJson(DateTime day) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-${two(day.day)}';
}

DateTime dayFromJson(Object? v) {
  final parts = (v as String).split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

List<T> _list<T>(Object? v, T Function(Json) decode) => [
  for (final e in (v as List<Object?>? ?? const [])) decode(e as Json),
];

// --- Targets ----------------------------------------------------------------

const _kindNames = {
  TargetKind.all: 'all',
  TargetKind.single: 'one',
  TargetKind.group: 'group',
};

TargetKind _kindFromJson(Object? v) =>
    _kindNames.entries.firstWhere((e) => e.value == v).key;

Json appTargetToJson(AppTarget t) => {
  'kind': _kindNames[t.kind],
  if (t.id != null) 'id': t.id,
};

AppTarget appTargetFromJson(Json j) => switch (_kindFromJson(j['kind'])) {
  TargetKind.all => const AppTarget.all(),
  TargetKind.single => AppTarget.app(j['id'] as String),
  TargetKind.group => AppTarget.group(j['id'] as String),
};

Json deviceTargetToJson(DeviceTarget t) => {
  'kind': _kindNames[t.kind],
  if (t.id != null) 'id': t.id,
};

DeviceTarget deviceTargetFromJson(Json j) => switch (_kindFromJson(j['kind'])) {
  TargetKind.all => const DeviceTarget.all(),
  TargetKind.single => DeviceTarget.device(j['id'] as String),
  TargetKind.group => DeviceTarget.group(j['id'] as String),
};

// --- Schedule ---------------------------------------------------------------

Json weeklyScheduleToJson(WeeklySchedule s) => {
  for (final e in s.byWeekday.entries)
    '${e.key}': [
      for (final r in e.value) [r.startMinute, r.endMinute],
    ],
};

WeeklySchedule weeklyScheduleFromJson(Json j) => WeeklySchedule({
  for (final e in j.entries)
    int.parse(e.key): [
      for (final r in e.value as List<Object?>)
        TimeRange(
          ((r as List<Object?>)[0] as num).toInt(),
          (r[1] as num).toInt(),
        ),
    ],
});

// --- Rules ------------------------------------------------------------------

Json carryOverToJson(CarryOverPolicy p) => {
  'mode': p.mode.name,
  'days': p.days,
};

CarryOverPolicy carryOverFromJson(Json? j) {
  if (j == null) return const CarryOverPolicy.none();
  return switch (CarryOverMode.values.byName(j['mode'] as String)) {
    CarryOverMode.none => const CarryOverPolicy.none(),
    CarryOverMode.nextDay => const CarryOverPolicy.nextDay(),
    CarryOverMode.spread => CarryOverPolicy.spread((j['days'] as num).toInt()),
  };
}

Json ruleToJson(Rule r) => {
  'id': r.id,
  'childId': r.childId,
  if (r.profileId != null) 'profileId': r.profileId,
  'appTarget': appTargetToJson(r.appTarget),
  'deviceTarget': deviceTargetToJson(r.deviceTarget),
  if (r.schedule != null) 'schedule': weeklyScheduleToJson(r.schedule!),
  if (r.dailyQuota != null) 'dailyQuota': durationToJson(r.dailyQuota!),
  if (r.dailyQuotaByWeekday.isNotEmpty)
    'dailyQuotaByWeekday': {
      for (final e in r.dailyQuotaByWeekday.entries)
        '${e.key}': durationToJson(e.value),
    },
  if (r.weeklyQuota != null) 'weeklyQuota': durationToJson(r.weeklyQuota!),
  if (r.rollingQuota != null)
    'rollingQuota': {
      'days': r.rollingQuota!.days,
      'quota': durationToJson(r.rollingQuota!.quota),
    },
  if (r.breakPolicy != null)
    'breakPolicy': {
      'after': durationToJson(r.breakPolicy!.after),
      'length': durationToJson(r.breakPolicy!.length),
    },
  if (r.grace != null)
    'grace': {
      'length': durationToJson(r.grace!.length),
      if (r.grace!.hardening != null)
        'hardening': {
          'threshold': durationToJson(r.grace!.hardening!.threshold),
          'days': r.grace!.hardening!.days,
          'window': r.grace!.hardening!.window,
          if (r.grace!.hardening!.deductOverruns) 'deductOverruns': true,
        },
    },
  if (r.carryOver.mode != CarryOverMode.none)
    'carryOver': carryOverToJson(r.carryOver),
  if (r.rollover != null)
    'rollover': {
      'days': r.rollover!.days,
      if (r.rollover!.cap != null) 'cap': durationToJson(r.rollover!.cap!),
    },
  if (r.listenOnly != null)
    'listenOnly': {
      'openFor': durationToJson(r.listenOnly!.openFor),
      'reopenAfter': durationToJson(r.listenOnly!.reopenAfter),
    },
  if (r.setByChild) 'setByChild': true,
  if (!r.enabled) 'enabled': false,
};

Rule ruleFromJson(Json j) {
  final rolling = j['rollingQuota'] as Json?;
  final brk = j['breakPolicy'] as Json?;
  final grace = j['grace'] as Json?;
  final hardening = grace?['hardening'] as Json?;
  final rollover = j['rollover'] as Json?;
  final listen = j['listenOnly'] as Json?;
  return Rule(
    id: j['id'] as String,
    childId: j['childId'] as String,
    profileId: j['profileId'] as String?,
    appTarget: appTargetFromJson(j['appTarget'] as Json),
    deviceTarget: deviceTargetFromJson(j['deviceTarget'] as Json),
    schedule: j['schedule'] == null
        ? null
        : weeklyScheduleFromJson(j['schedule'] as Json),
    dailyQuota: optionalDuration(j['dailyQuota']),
    dailyQuotaByWeekday: {
      for (final e in (j['dailyQuotaByWeekday'] as Json? ?? const {}).entries)
        int.parse(e.key): durationFromJson(e.value),
    },
    weeklyQuota: optionalDuration(j['weeklyQuota']),
    rollingQuota: rolling == null
        ? null
        : RollingQuota(
            days: (rolling['days'] as num).toInt(),
            quota: durationFromJson(rolling['quota']),
          ),
    breakPolicy: brk == null
        ? null
        : BreakPolicy(
            after: durationFromJson(brk['after']),
            length: durationFromJson(brk['length']),
          ),
    grace: grace == null
        ? null
        : GracePolicy(
            length: durationFromJson(grace['length']),
            hardening: hardening == null
                ? null
                : HardeningPolicy(
                    threshold: durationFromJson(hardening['threshold']),
                    days: (hardening['days'] as num).toInt(),
                    window: (hardening['window'] as num).toInt(),
                    deductOverruns:
                        hardening['deductOverruns'] as bool? ?? false,
                  ),
          ),
    carryOver: carryOverFromJson(j['carryOver'] as Json?),
    rollover: rollover == null
        ? null
        : RolloverPolicy(
            days: (rollover['days'] as num).toInt(),
            cap: optionalDuration(rollover['cap']),
          ),
    listenOnly: listen == null
        ? null
        : ListenOnlyPolicy(
            openFor: durationFromJson(listen['openFor']),
            reopenAfter: durationFromJson(listen['reopenAfter']),
          ),
    setByChild: j['setByChild'] as bool? ?? false,
    enabled: j['enabled'] as bool? ?? true,
  );
}

// --- Calendar ---------------------------------------------------------------

Json profileToJson(Profile p) => {
  'id': p.id,
  'name': p.name,
  'kind': p.kind.name,
  'periods': [
    for (final r in p.periods)
      {'first': dayToJson(r.first), 'last': dayToJson(r.last)},
  ],
};

Profile profileFromJson(Json j) => Profile(
  id: j['id'] as String,
  name: j['name'] as String,
  kind: ProfileKind.values.byName(j['kind'] as String),
  periods: _list(
    j['periods'],
    (r) => DateRange(dayFromJson(r['first']), dayFromJson(r['last'])),
  ),
);

// --- Modifiers --------------------------------------------------------------

Json bonusToJson(Bonus b) => {
  'id': b.id,
  'childId': b.childId,
  if (b.ruleId != null) 'ruleId': b.ruleId,
  if (b.appTarget != null) 'appTarget': appTargetToJson(b.appTarget!),
  'amount': durationToJson(b.amount),
  'grantedAt': instantToJson(b.grantedAt),
  'validUntil': instantToJson(b.validUntil),
};

Bonus bonusFromJson(Json j) {
  final id = j['id'] as String;
  final childId = j['childId'] as String;
  final amount = durationFromJson(j['amount']);
  final grantedAt = instantFromJson(j['grantedAt']);
  final validUntil = instantFromJson(j['validUntil']);
  final ruleId = j['ruleId'] as String?;
  if (ruleId != null) {
    return Bonus.forRule(
      id: id,
      childId: childId,
      ruleId: ruleId,
      amount: amount,
      grantedAt: grantedAt,
      validUntil: validUntil,
    );
  }
  return Bonus.forTarget(
    id: id,
    childId: childId,
    appTarget: appTargetFromJson(j['appTarget'] as Json),
    amount: amount,
    grantedAt: grantedAt,
    validUntil: validUntil,
  );
}

Json temporaryBlockToJson(TemporaryBlock b) => {
  'id': b.id,
  'childId': b.childId,
  'appTarget': appTargetToJson(b.appTarget),
  'deviceTarget': deviceTargetToJson(b.deviceTarget),
  'from': instantToJson(b.from),
  if (b.until != null) 'until': instantToJson(b.until!),
  if (b.voluntary) 'voluntary': true,
};

TemporaryBlock temporaryBlockFromJson(Json j) => TemporaryBlock(
  id: j['id'] as String,
  childId: j['childId'] as String,
  appTarget: appTargetFromJson(j['appTarget'] as Json),
  deviceTarget: deviceTargetFromJson(j['deviceTarget'] as Json),
  from: instantFromJson(j['from']),
  until: optionalInstant(j['until']),
  voluntary: j['voluntary'] as bool? ?? false,
);

Json hoursUnlockToJson(HoursUnlock u) => {
  'id': u.id,
  'childId': u.childId,
  'ruleId': u.ruleId,
  'from': instantToJson(u.from),
  'until': instantToJson(u.until),
};

HoursUnlock hoursUnlockFromJson(Json j) => HoursUnlock(
  id: j['id'] as String,
  childId: j['childId'] as String,
  ruleId: j['ruleId'] as String,
  from: instantFromJson(j['from']),
  until: instantFromJson(j['until']),
);

Json dayUnlockToJson(DayUnlock u) => {
  'id': u.id,
  'childId': u.childId,
  'day': dayToJson(u.day),
};

DayUnlock dayUnlockFromJson(Json j) => DayUnlock(
  id: j['id'] as String,
  childId: j['childId'] as String,
  day: dayFromJson(j['day']),
);

Json familyBlockToJson(FamilyBlock b) => {
  'id': b.id,
  'from': instantToJson(b.from),
  if (b.until != null) 'until': instantToJson(b.until!),
};

FamilyBlock familyBlockFromJson(Json j) => FamilyBlock(
  id: j['id'] as String,
  from: instantFromJson(j['from']),
  until: optionalInstant(j['until']),
);

// --- Usage ------------------------------------------------------------------

Json usageSegmentToJson(UsageSegment s) => {
  'childId': s.childId,
  if (s.deviceId != null) 'deviceId': s.deviceId,
  if (s.appId != null) 'appId': s.appId,
  if (s.injectedTarget != null)
    'injectedTarget': appTargetToJson(s.injectedTarget!),
  'start': instantToJson(s.start),
  'end': instantToJson(s.end),
};

UsageSegment usageSegmentFromJson(Json j) {
  final injected = j['injectedTarget'] as Json?;
  if (injected != null) {
    return UsageSegment.injected(
      childId: j['childId'] as String,
      injectedTarget: appTargetFromJson(injected),
      start: instantFromJson(j['start']),
      end: instantFromJson(j['end']),
    );
  }
  return UsageSegment.device(
    childId: j['childId'] as String,
    deviceId: j['deviceId'] as String,
    appId: j['appId'] as String,
    start: instantFromJson(j['start']),
    end: instantFromJson(j['end']),
  );
}

// --- Configuration and state ------------------------------------------------

Json familyConfigToJson(FamilyConfig c) => {
  'appGroups': {
    for (final e in c.appGroups.entries) e.key: e.value.toList()..sort(),
  },
  'deviceGroups': {
    for (final e in c.deviceGroups.entries) e.key: e.value.toList()..sort(),
  },
  'alwaysAllowed': c.alwaysAllowed.toList()..sort(),
  if (c.allowedInHours.isNotEmpty)
    'allowedInHours': c.allowedInHours.toList()..sort(),
  'neverBlocked': c.neverBlocked.toList()..sort(),
  'profiles': [for (final p in c.profiles) profileToJson(p)],
  'weekStart': c.weekStart,
  'counting': c.counting.name,
};

Map<String, Set<String>> _groups(Object? v) => {
  for (final e in (v as Json? ?? const {}).entries)
    e.key: {for (final id in e.value as List<Object?>) id as String},
};

Set<String> _ids(Object? v) => {
  for (final id in (v as List<Object?>? ?? const [])) id as String,
};

FamilyConfig familyConfigFromJson(Json j) => FamilyConfig(
  appGroups: _groups(j['appGroups']),
  deviceGroups: _groups(j['deviceGroups']),
  alwaysAllowed: _ids(j['alwaysAllowed']),
  allowedInHours: _ids(j['allowedInHours']),
  neverBlocked: _ids(j['neverBlocked']),
  profiles: _list(j['profiles'], profileFromJson),
  weekStart: (j['weekStart'] as num?)?.toInt() ?? DateTime.monday,
  counting: SimultaneousCounting.values.byName(
    j['counting'] as String? ?? SimultaneousCounting.sum.name,
  ),
);

/// Encodes everything in [s] except usage, which is usually stored apart
/// because it grows all the time.
Json familyStateToJson(FamilyState s, {bool includeUsage = false}) => {
  'rules': [for (final r in s.rules) ruleToJson(r)],
  'bonuses': [for (final b in s.bonuses) bonusToJson(b)],
  'temporaryBlocks': [
    for (final b in s.temporaryBlocks) temporaryBlockToJson(b),
  ],
  'dayUnlocks': [for (final u in s.dayUnlocks) dayUnlockToJson(u)],
  'familyBlocks': [for (final b in s.familyBlocks) familyBlockToJson(b)],
  if (s.hoursUnlocks.isNotEmpty)
    'hoursUnlocks': [for (final u in s.hoursUnlocks) hoursUnlockToJson(u)],
  if (includeUsage) 'usage': [for (final u in s.usage) usageSegmentToJson(u)],
};

FamilyState familyStateFromJson(Json j, {List<UsageSegment>? usage}) =>
    FamilyState(
      rules: _list(j['rules'], ruleFromJson),
      bonuses: _list(j['bonuses'], bonusFromJson),
      temporaryBlocks: _list(j['temporaryBlocks'], temporaryBlockFromJson),
      hoursUnlocks: _list(j['hoursUnlocks'], hoursUnlockFromJson),
      dayUnlocks: _list(j['dayUnlocks'], dayUnlockFromJson),
      familyBlocks: _list(j['familyBlocks'], familyBlockFromJson),
      usage: usage ?? _list(j['usage'], usageSegmentFromJson),
    );
