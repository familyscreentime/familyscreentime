import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final profiles = [
    const Profile(id: 'normal', name: 'Normal', kind: ProfileKind.normal),
    Profile(
      id: 'holidays',
      name: 'Holidays',
      kind: ProfileKind.vacation,
      periods: [DateRange(at(12, 0), at(16, 0))],
    ),
    Profile(
      id: 'exams',
      name: 'Exams',
      kind: ProfileKind.custom,
      periods: [DateRange(at(7, 0), at(8, 0)), DateRange(at(13, 0), at(14, 0))],
    ),
  ];
  final cfg = configWith(profiles: profiles);
  final state = FamilyState(
    rules: [
      Rule(
        id: 'normal',
        childId: child,
        profileId: 'normal',
        dailyQuota: min(60),
      ),
      Rule(
        id: 'holidays',
        childId: child,
        profileId: 'holidays',
        dailyQuota: min(180),
      ),
      Rule(
        id: 'exams',
        childId: child,
        profileId: 'exams',
        dailyQuota: min(30),
      ),
      // A limit the child set: valid in every profile.
      Rule(id: 'mine', childId: child, dailyQuota: min(120), setByChild: true),
    ],
  );

  group('Calendar profiles', () {
    test('holidays, then custom, then normal', () {
      expect(activeProfileId(profiles, at(5, 10)), 'normal');
      expect(activeProfileId(profiles, at(7, 10)), 'exams');
      expect(activeProfileId(profiles, at(13, 10)), 'holidays');
      expect(activeProfileId(const [], at(5, 10)), isNull);
    });

    test('the active profile replaces the other profiles\' rules', () {
      final normal = check(state, at(5, 10), cfg: cfg);
      expect(normal.remaining, min(60));
      expect(normal.ruleId, 'normal');

      final holidays = check(state, at(13, 10), cfg: cfg);
      expect(holidays.remaining, min(120));
      expect(holidays.ruleId, 'mine');

      expect(check(state, at(8, 10), cfg: cfg).remaining, min(30));
    });

    test('both ends of a period are included', () {
      final p = DateRange(at(12, 0), at(16, 0));
      expect(p.contains(at(12, 0)), isTrue);
      expect(p.contains(at(16, 23, 59)), isTrue);
      expect(p.contains(at(17, 0)), isFalse);
    });
  });
}
