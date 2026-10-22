import 'package:screentime_engine/screentime_engine.dart';

/// October 2026: the 5th is a Monday. No daylight-saving change before the 25th.
DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 10, day, hour, minute);

Duration min(int minutes) => Duration(minutes: minutes);

const child = 'emma';
const tablet = 'tablet';
const phone = 'phone';

final config = FamilyConfig(
  appGroups: {
    'games': {'minecraft', 'roblox'},
    'creative': {'minecraft'},
    'video': {'youtube'},
  },
  deviceGroups: {
    'tablets': {tablet},
  },
  alwaysAllowed: {'sms', 'dialer'},
  neverBlocked: {'launcher'},
);

UsageSegment use(
  String device,
  String app,
  DateTime start,
  int minutes, {
  String childId = child,
}) => UsageSegment.device(
  childId: childId,
  deviceId: device,
  appId: app,
  start: start,
  end: start.add(min(minutes)),
);

Decision check(
  FamilyState state,
  DateTime now, {
  String device = tablet,
  String app = 'minecraft',
  FamilyConfig? cfg,
}) => RuleEngine(
  cfg ?? config,
).evaluate(state, childId: child, deviceId: device, appId: app, now: now);

FamilyConfig configWith({
  SimultaneousCounting counting = SimultaneousCounting.sum,
  int weekStart = DateTime.monday,
  List<Profile> profiles = const [],
}) => FamilyConfig(
  appGroups: config.appGroups,
  deviceGroups: config.deviceGroups,
  alwaysAllowed: config.alwaysAllowed,
  neverBlocked: config.neverBlocked,
  counting: counting,
  weekStart: weekStart,
  profiles: profiles,
);
