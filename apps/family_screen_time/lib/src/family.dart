/// Helpers around the family data used by both the interface and the monitor.
library;

import 'package:screentime_engine/screentime_engine.dart';

import 'platform.dart';
import 'store.dart';
import 'strings.dart';

/// System components that must never be blocked: blocking them would break
/// the device, Google's parental supervision, or the parent's access to
/// settings.
const knownSystemPackages = {
  'com.android.systemui',
  'com.android.settings',
  'com.google.android.gms',
  'com.google.android.apps.kids.familylinkhelper',
  'com.google.android.apps.kids.familylink',
  // The supervision's own lock screen ("Parental control system").
  'com.google.android.gms.supervision',
  'com.google.android.permissioncontroller',
  'com.android.permissioncontroller',
};

/// Home screens of the usual makers: not counted in the statistics, even
/// from a device that has not shared its own (see `FamilySync.publishSystem`).
const knownLaunchers = {
  'com.miui.home',
  'com.mi.android.globallauncher',
  'com.sec.android.app.launcher',
  'com.google.android.apps.nexuslauncher',
  'com.android.launcher',
  'com.android.launcher3',
  'com.huawei.android.launcher',
  'com.hihonor.android.launcher',
  'com.oppo.launcher',
  'com.motorola.launcher3',
  'com.teslacoilsw.launcher',
  'com.microsoft.launcher',
};

/// Configuration for a new family on this device.
FamilyConfig initialConfig(SystemPackages p) => FamilyConfig(
  alwaysAllowed: {?p.dialer, ?p.sms},
  neverBlocked: {
    p.self,
    ...p.launchers,
    ...p.callScreens,
    ...knownSystemPackages,
  },
);

/// [f] with [apps] among those never blocked nor counted: the screens of a
/// phone call on this device, say.
FamilyData withNeverBlocked(FamilyData f, Iterable<String> apps) =>
    f.config.neverBlocked.containsAll(apps)
    ? f
    : f.copyWith(
        config: f.config.copyWith(
          neverBlocked: {...f.config.neverBlocked, ...apps},
        ),
      );

/// Keeps the list of system components up to date (launchers can change).
/// The always-allowed apps are the parent's choice: set once at setup, then
/// left alone.
FamilyConfig refreshSystemLists(FamilyConfig c, SystemPackages p) => c.copyWith(
  neverBlocked: {
    ...c.neverBlocked,
    p.self,
    ...p.launchers,
    ...p.callScreens,
    ...knownSystemPackages,
  },
);

/// [f] with the known system components and home screens among the apps
/// never blocked nor counted, so components added in an update apply at
/// once, to existing families and to the time already recorded. The home
/// screens of the usual makers count for the devices that have not shared
/// theirs: a child's home screen is never screen time, whichever device
/// adds up the time.
FamilyData withKnownSystem(FamilyData f) =>
    withNeverBlocked(f, {...knownSystemPackages, ...knownLaunchers});

/// Name shown for a rule. An app's own name comes from [labels] (Android's
/// names by package), unless the parent renamed it.
String ruleLabel(
  Rule r,
  FamilyData f,
  S s, {
  Map<String, String> labels = const {},
}) => switch (r.appTarget.kind) {
  TargetKind.all => s.t('allScreens'),
  TargetKind.group => f.groupNames[r.appTarget.id] ?? r.appTarget.id!,
  TargetKind.single =>
    f.appNames[r.appTarget.id] ??
        labels[r.appTarget.id] ??
        (r.appTarget.id == browserVideoApp
            ? s.t('browserVideos')
            : r.appTarget.id!),
};

/// Packages of the apps limited on their own.
Set<String> singleAppTargets(Iterable<Rule> rules) => {
  for (final r in rules)
    if (r.appTarget.kind == TargetKind.single) r.appTarget.id!,
};

/// Usage history the engine may need: weekly quota, carry-over, savings.
const usageHistoryDays = 40;

/// The rules of [after], each with its daily limit's earlier versions
/// (`Rule.history`): those it had in [before], and the version [before]
/// held when its daily limit, or whether it is on, changed at [now]. A
/// rule new at [now] had none before. Versions older than the usage looked
/// at are dropped. Past days are thus judged by the limit in force then.
FamilyData withRuleVersions(FamilyData before, FamilyData after, DateTime now) {
  final was = {for (final r in before.state.rules) r.id: r};
  final oldest = now.subtract(const Duration(days: usageHistoryDays + 7));
  var changed = false;
  final rules = [
    for (final r in after.state.rules)
      () {
        final old = was[r.id];
        final versions = old == null
            // New here: none before, unless it came with its own (a rule
            // put back, say).
            ? (r.history.isEmpty ? [RuleVersion.none(now)] : [...r.history])
            : [
                ...old.history,
                if (_limitChanged(old, r)) RuleVersion.of(old, now),
              ];
        versions.removeWhere((v) => !v.until.isAfter(oldest));
        if (_sameVersions(versions, r.history)) return r;
        changed = true;
        return r.withHistory(versions);
      }(),
  ];
  if (!changed) return after;
  return after.copyWith(state: after.state.copyWith(rules: rules));
}

bool _limitChanged(Rule a, Rule b) =>
    a.enabled != b.enabled ||
    a.dailyQuota != b.dailyQuota ||
    !_sameQuotas(a.dailyQuotaByWeekday, b.dailyQuotaByWeekday);

bool _sameQuotas(Map<int, Duration> a, Map<int, Duration> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

bool _sameVersions(List<RuleVersion> a, List<RuleVersion> b) =>
    a.length == b.length &&
    [
      for (var i = 0; i < a.length; i++)
        a[i].until == b[i].until &&
            a[i].active == b[i].active &&
            a[i].dailyQuota == b[i].dailyQuota &&
            _sameQuotas(a[i].dailyQuotaByWeekday, b[i].dailyQuotaByWeekday),
    ].every((same) => same);

/// One-line summary of a rule: daily and weekly time, set hours.
///
/// [periodNames] names the special periods by id, for rules that only apply
/// during one of them.
///
/// [devices] names the devices of a rule aimed at some of them only.
String ruleSummary(
  Rule r,
  S s, {
  Map<String, String> periodNames = const {},
  String? devices,
}) => [
  if (devices != null) s.t('ruleTagDevices', {'devices': devices}),
  if (r.profileId == 'normal') s.t('ruleTagNormal'),
  if (r.profileId != null && r.profileId != 'normal')
    s.t('ruleTagPeriod', {'name': periodNames[r.profileId] ?? r.profileId!}),
  if (r.dailyQuotaByWeekday.isNotEmpty)
    s.t('ruleSummaryQuotaByDay')
  else if (r.dailyQuota != null)
    s.t('ruleSummaryQuota', {'time': s.duration(r.dailyQuota!)}),
  if (r.weeklyQuota != null)
    s.t('ruleSummaryWeekly', {'time': s.duration(r.weeklyQuota!)}),
  if (r.rollingQuota != null)
    s.t('ruleSummaryRolling', {
      'time': s.duration(r.rollingQuota!.quota),
      'days': s.days(r.rollingQuota!.days),
    }),
  if (r.schedule != null) s.t('ruleSummarySchedule'),
  if (r.breakPolicy != null)
    s.t('ruleSummaryBreak', {
      'length': s.duration(r.breakPolicy!.length),
      'after': s.duration(r.breakPolicy!.after),
    }),
  if (r.grace != null)
    s.t('ruleSummaryGrace', {'time': s.duration(r.grace!.length)}),
  if (r.carryOver.mode != CarryOverMode.none) s.t('ruleSummaryCarry'),
  if (r.rollover != null)
    s.t('ruleSummaryRollover', {'days': s.days(r.rollover!.days)}),
  if (r.listenOnly != null) s.t('listenOnly').toLowerCase(),
].join(' · ');

/// Prefix of the groups of devices made for one rule, aimed at some of the
/// child's devices: `rule-<rule id>`. The parent never sees them as groups.
const ruleDeviceGroupPrefix = 'rule-';

/// The devices [r] applies to, by id; `null` for all the child's devices.
Set<String>? ruleDevices(Rule r, Map<String, Set<String>> deviceGroups) =>
    switch (r.deviceTarget.kind) {
      TargetKind.all => null,
      TargetKind.single => {r.deviceTarget.id!},
      TargetKind.group => deviceGroups[r.deviceTarget.id] ?? const {},
    };

/// The target of rule [ruleId] for the devices [chosen] among the child's
/// [devices] (`null`, or every one of them: all, those added later too),
/// and the family's groups of devices with the rule's own group set or
/// gone.
(DeviceTarget, Map<String, Set<String>>) aimRule(
  String ruleId,
  Set<String>? chosen,
  Set<String> devices,
  Map<String, Set<String>> deviceGroups,
) {
  final own = '$ruleDeviceGroupPrefix$ruleId';
  final groups = {...deviceGroups}..remove(own);
  if (chosen == null || chosen.isEmpty || chosen.containsAll(devices)) {
    return (const DeviceTarget.all(), groups);
  }
  if (chosen.length == 1) return (DeviceTarget.device(chosen.single), groups);
  groups[own] = {...chosen};
  return (DeviceTarget.group(own), groups);
}

/// [deviceGroups] without the groups of rules that no longer use them.
Map<String, Set<String>> pruneRuleDeviceGroups(
  Map<String, Set<String>> deviceGroups,
  Iterable<Rule> rules,
) {
  final used = {
    for (final r in rules)
      if (r.deviceTarget.kind == TargetKind.group) r.deviceTarget.id,
  };
  return {
    for (final e in deviceGroups.entries)
      if (!e.key.startsWith(ruleDeviceGroupPrefix) || used.contains(e.key))
        e.key: e.value,
  };
}
