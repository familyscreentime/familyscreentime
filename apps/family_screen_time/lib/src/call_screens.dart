/// The screens of a phone call in the statistics: counted as the phone
/// app of the device the call was on (Samsung's in-call screen,
/// `com.samsung.android.incallui`, as Samsung's phone app, say).
library;

import 'package:screentime_engine/screentime_engine.dart';

/// Call screens known by name, for the devices that did not say theirs
/// (older versions): screen → phone app.
const knownCallScreens = {
  'com.samsung.android.incallui': 'com.samsung.android.dialer',
};

/// [history] with the use of a call screen counted as the phone app of
/// its device: [byDevice] says, for each device, its screens and app.
List<UsageSegment> callScreensAsPhone(
  Iterable<UsageSegment> history,
  Map<String, Map<String, String>> byDevice,
) => [
  for (final s in history)
    switch ((byDevice[s.deviceId] ?? const {})[s.appId] ??
        knownCallScreens[s.appId]) {
      final String phone when !s.isInjected && s.deviceId != null =>
        UsageSegment.device(
          childId: s.childId,
          deviceId: s.deviceId!,
          appId: phone,
          start: s.start,
          end: s.end,
          activity: s.activity,
        ),
      _ => s,
    },
];
