import 'package:family_screen_time/src/call_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  final at = DateTime(2026, 11, 12, 7, 43);

  UsageSegment use(String device, String app) => UsageSegment.device(
    childId: 'emma',
    deviceId: device,
    appId: app,
    start: at,
    end: at.add(const Duration(seconds: 30)),
  );

  test('a call\'s screens count as the phone app of their device', () {
    final merged = callScreensAsPhone(
      [
        use('phone', 'com.maker.incallui'),
        use('phone', 'com.maker.dialer'),
        use('tablet', 'com.maker.incallui'),
        use('old', 'com.samsung.android.incallui'),
        use('phone', 'minecraft'),
      ],
      {
        'phone': {'com.maker.incallui': 'com.maker.dialer'},
      },
    );
    expect(merged.map((s) => s.appId), [
      'com.maker.dialer',
      'com.maker.dialer',
      // Another device's app with that name: left as it is.
      'com.maker.incallui',
      // Samsung's, known even from a device that did not say.
      'com.samsung.android.dialer',
      'minecraft',
    ]);
    expect(merged.first.deviceId, 'phone');
    expect(merged.first.start, at);
  });
}
