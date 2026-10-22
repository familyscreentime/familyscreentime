/// When screen time comes back once the day's time is over: "see you
/// tomorrow from 9", "in 3 days"…
library;

import 'package:screentime_engine/screentime_engine.dart';

import 'strings.dart';

/// An app in no group: only the rules on all apps (total screen time,
/// family and temporary blocks, breaks) apply to it.
const probeApp = '\u0000any app';

/// Furthest day looked at.
const _horizonDays = 31;

/// First moment from [now] when an app covered only by the rules on all
/// apps is allowed again; `null` beyond a month (or never). The time used
/// so far is kept as is: the days ahead are taken as unused.
DateTime? nextAvailable(
  RuleEngine engine,
  FamilyState state, {
  required String childId,
  required String deviceId,
  required DateTime now,
}) {
  final horizon = addDays(dayOf(now), _horizonDays);
  var t = now;
  for (var step = 0; step < 4 * _horizonDays && t.isBefore(horizon); step++) {
    final d = engine.evaluate(
      state,
      childId: childId,
      deviceId: deviceId,
      appId: probeApp,
      now: t,
    );
    if (d.allowed) return t;
    final until = d.until;
    // Blocked until a known time (hours, a break, a block): go there;
    // otherwise (time used up) try the next day.
    t = until != null && until.isAfter(t) ? until : addDays(dayOf(t), 1);
  }
  return null;
}

/// "tomorrow from 9", "the day after tomorrow", "in 3 days", for a moment
/// after today; `null` for today.
String? whenBack(S s, DateTime back, DateTime now) {
  final days = DateTime.utc(
    back.year,
    back.month,
    back.day,
  ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  if (days <= 0) return null;
  final day = switch (days) {
    1 => s.t('whenTomorrow'),
    2 => s.t('whenAfterTomorrow'),
    _ => s.t('whenInDays', {'count': '$days'}),
  };
  if (back.hour == 0 && back.minute == 0) return day;
  return s.t('whenAt', {'day': day, 'time': s.hour(back)});
}

/// "Your time for today is up. See you tomorrow from 9." when screen time
/// only comes back on a later day; `null` otherwise.
String? timeOverMessage(S s, DateTime? back, DateTime now) {
  if (back == null) return s.t('timeOverToday');
  final when = whenBack(s, back, now);
  if (when == null) return null;
  return s.t('timeOverUntil', {'when': when});
}
