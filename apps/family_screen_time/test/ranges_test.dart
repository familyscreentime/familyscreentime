import 'package:family_screen_time/src/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  List<List<int>> plain(List<TimeRange> r) => [
    for (final x in r) [x.startMinute, x.endMinute],
  ];

  test('ranges are sorted and overlapping ones merged', () {
    expect(
      plain(
        normalizeRanges([
          TimeRange.hm(14, 0, 17, 0),
          TimeRange.hm(9, 0, 10, 0),
          TimeRange.hm(16, 0, 18, 0),
          TimeRange.hm(10, 0, 11, 0),
        ]),
      ),
      [
        [540, 660],
        [840, 1080],
      ],
    );
  });
}
