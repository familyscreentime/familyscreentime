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

/// Configuration for a new family on this device.
FamilyConfig initialConfig(SystemPackages p) => FamilyConfig(
  alwaysAllowed: {?p.dialer, ?p.sms},
  neverBlocked: {p.self, ...p.launchers, ...knownSystemPackages},
);

/// Keeps the list of system components up to date (launchers can change).
/// The always-allowed apps are the parent's choice: set once at setup, then
/// left alone.
FamilyConfig refreshSystemLists(FamilyConfig c, SystemPackages p) => c.copyWith(
  neverBlocked: {
    ...c.neverBlocked,
    p.self,
    ...p.launchers,
    ...knownSystemPackages,
  },
);

/// [f] with the known system components among the apps never blocked nor
/// counted, so components added in an update apply at once, to existing
/// families and to the time already recorded.
FamilyData withKnownSystem(FamilyData f) =>
    f.config.neverBlocked.containsAll(knownSystemPackages)
    ? f
    : f.copyWith(
        config: f.config.copyWith(
          neverBlocked: {...f.config.neverBlocked, ...knownSystemPackages},
        ),
      );

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
    f.appNames[r.appTarget.id] ?? labels[r.appTarget.id] ?? r.appTarget.id!,
};

/// Packages of the apps limited on their own.
Set<String> singleAppTargets(Iterable<Rule> rules) => {
  for (final r in rules)
    if (r.appTarget.kind == TargetKind.single) r.appTarget.id!,
};

/// Usage history the engine may need: weekly quota, carry-over, savings.
const usageHistoryDays = 40;

/// One-line summary of a rule: daily and weekly time, set hours.
///
/// [periodNames] names the special periods by id, for rules that only apply
/// during one of them.
String ruleSummary(Rule r, S s, {Map<String, String> periodNames = const {}}) =>
    [
      if (r.profileId == 'normal') s.t('ruleTagNormal'),
      if (r.profileId != null && r.profileId != 'normal')
        s.t('ruleTagPeriod', {
          'name': periodNames[r.profileId] ?? r.profileId!,
        }),
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
