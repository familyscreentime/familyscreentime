import 'package:family_screen_time/src/children_glance.dart';
import 'package:family_screen_time/src/demo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the demo family: Léa can use her devices, Tom is blocked', () {
    final now = DateTime(2026, 10, 28, 17);
    final family = demoFamily(now);
    expect(family.children.map((c) => c.name), ['Léa', 'Tom']);
    final usage = family.state.usage;
    expect(childLocked(family, usage, 'lea', const {'demo-lea'}, now), isFalse);
    expect(childLocked(family, usage, 'tom', const {'demo-tom'}, now), isTrue);
    final block = family.state.temporaryBlocks.single;
    expect(block.message, isNotNull);
    expect(usage.every((u) => !u.end.isAfter(now)), isTrue);
  });
}
