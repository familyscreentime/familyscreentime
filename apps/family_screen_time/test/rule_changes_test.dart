import 'package:family_screen_time/src/rule_changes.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  const s = S('fr');
  const games = Rule(
    id: 'games',
    childId: 'emma',
    appTarget: AppTarget.group('g'),
    dailyQuota: Duration(hours: 1),
  );
  FamilyData family(List<Rule> rules) => FamilyData(
    children: const [Child(id: 'emma', name: 'Emma')],
    state: FamilyState(rules: rules),
    groupNames: const {'g': 'Jeux'},
  );

  test('the rule keys of the events', () {
    expect(
      touchedRules([
        'rule/games',
        'bonus/b1',
        'rule/all',
        'child/emma',
      ], 'rule/'),
      {'games', 'all'},
    );
  });

  test('added, changed, removed; the same rule again is no change', () {
    const shorter = Rule(
      id: 'games',
      childId: 'emma',
      appTarget: AppTarget.group('g'),
      dailyQuota: Duration(minutes: 45),
    );
    const all = Rule(
      id: 'all',
      childId: 'emma',
      dailyQuota: Duration(hours: 2),
    );
    expect(
      ruleChanges(family([]), family([games]), {'games'}, 'emma').single.kind,
      RuleChangeKind.added,
    );
    expect(
      ruleChanges(family([games]), family([shorter]), {
        'games',
      }, 'emma').single.rule.dailyQuota,
      const Duration(minutes: 45),
    );
    expect(
      ruleChanges(family([games, all]), family([games]), {
        'all',
      }, 'emma').single.kind,
      RuleChangeKind.removed,
    );
    expect(
      ruleChanges(family([games]), family([games]), {'games'}, 'emma'),
      isEmpty,
    );
    // Untouched by the events: not told (a change made here, say).
    expect(ruleChanges(family([]), family([games]), {}, 'emma'), isEmpty);
  });

  test('other children\'s rules and the child\'s own limits are not told', () {
    const leo = Rule(id: 'leo', childId: 'leo', dailyQuota: Duration(hours: 1));
    const own = Rule(
      id: 'own',
      childId: 'emma',
      dailyQuota: Duration(minutes: 30),
      setByChild: true,
    );
    expect(
      ruleChanges(family([]), family([leo, own]), {'leo', 'own'}, 'emma'),
      isEmpty,
    );
  });

  test('one change, or several in one notification', () {
    final after = family([games]);
    expect(
      ruleChangeNotice(
        [const RuleChange(RuleChangeKind.added, games)],
        after,
        s,
      ),
      ('Nouvelle règle : Jeux', '1 h par jour'),
    );
    final (title, text) = ruleChangeNotice(
      [
        const RuleChange(RuleChangeKind.changed, games),
        RuleChange(RuleChangeKind.changed, games.withEnabled(false)),
        const RuleChange(RuleChangeKind.removed, games),
      ],
      after,
      s,
    );
    expect(title, '3 règles changées par un parent');
    expect(text.split('\n'), [
      'Modifiée · Jeux : 1 h par jour',
      'Modifiée · Jeux : Désactivée',
      'Retirée · Jeux : Elle ne s\'applique plus.',
    ]);
  });
}
