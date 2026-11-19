/// Time the parent entered for away from the devices (console, TV…), in
/// the statistics: as the use of a device of its own, with one "app" per
/// kind of time it counts as (all apps, a group, an app).
library;

import 'package:screentime_engine/screentime_engine.dart';

/// The device the time away is shown under.
const awayDevice = '#away';

const _awayPrefix = '#away';

/// The "app" of time away counted as [target]'s.
String awayApp(AppTarget target) => switch (target.kind) {
  TargetKind.all => _awayPrefix,
  TargetKind.group => '$_awayPrefix:group:${target.id}',
  TargetKind.single => '$_awayPrefix:app:${target.id}',
};

bool isAwayApp(String id) =>
    id == _awayPrefix || id.startsWith('$_awayPrefix:');

/// What the time away of [id] counts as; `null` for an app's id.
AppTarget? awayTarget(String id) {
  if (id == _awayPrefix) return const AppTarget.all();
  if (id.startsWith('$_awayPrefix:group:')) {
    return AppTarget.group(id.substring('$_awayPrefix:group:'.length));
  }
  if (id.startsWith('$_awayPrefix:app:')) {
    return AppTarget.app(id.substring('$_awayPrefix:app:'.length));
  }
  return null;
}

/// The time away among [injected], as segments of [awayDevice].
List<UsageSegment> awaySegments(Iterable<UsageSegment> injected) => [
  for (final u in injected)
    if (u.injectedTarget != null)
      UsageSegment.device(
        childId: u.childId,
        deviceId: awayDevice,
        appId: awayApp(u.injectedTarget!),
        start: u.start,
        end: u.end,
      ),
];
