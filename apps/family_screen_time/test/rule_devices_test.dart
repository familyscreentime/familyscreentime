import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/family.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  const devices = {'tablet', 'phone', 'pc'};

  test('all the devices, or none chosen: the rule is on all of them', () {
    final (target, groups) = aimRule('r', null, devices, const {});
    expect(target, const DeviceTarget.all());
    expect(groups, isEmpty);
    final (every, _) = aimRule('r', {...devices}, devices, const {});
    expect(every, const DeviceTarget.all());
  });

  test('one device: the rule targets it', () {
    final (target, groups) = aimRule('r', {'pc'}, devices, const {});
    expect(target, const DeviceTarget.device('pc'));
    expect(groups, isEmpty);
  });

  test('some devices: the rule has its own group, gone with them', () {
    final (target, groups) = aimRule(
      'r',
      {'tablet', 'pc'},
      devices,
      const {
        'tablets': {'tablet'},
      },
    );
    expect(target, const DeviceTarget.group('rule-r'));
    expect(groups, {
      'tablets': {'tablet'},
      'rule-r': {'tablet', 'pc'},
    });
    // Back to all: the rule's group goes, the parent's stays.
    final (_, after) = aimRule('r', null, devices, groups);
    expect(after, {
      'tablets': {'tablet'},
    });
  });

  test('the groups of rules deleted go, the others stay', () {
    const kept = Rule(
      id: 'a',
      childId: 'emma',
      deviceTarget: DeviceTarget.group('rule-a'),
    );
    final groups = pruneRuleDeviceGroups(
      const {
        'rule-a': {'pc', 'phone'},
        'rule-gone': {'pc', 'tablet'},
        'tablets': {'tablet'},
      },
      const [kept],
    );
    expect(groups.keys, unorderedEquals(['rule-a', 'tablets']));
    expect(ruleDevices(kept, groups), {'pc', 'phone'});
  });

  test('a rule on some devices says which, by name', () {
    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    const rule = Rule(
      id: 'r',
      childId: 'emma',
      dailyQuota: Duration(hours: 1),
      deviceTarget: DeviceTarget.group('rule-r'),
    );
    final c = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'pc', language: 'fr', childId: 'emma'),
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
        config: FamilyConfig(
          deviceGroups: {
            'rule-r': {'pc', 'tablet'},
          },
        ),
        state: FamilyState(rules: [rule]),
      ),
    );
    c.deviceLabels = {'pc': 'PC du salon', 'tablet': 'Tablette'};
    expect(c.devicesLabel(rule), 'PC du salon, Tablette');
    expect(c.summaryOf(rule), 'sur PC du salon, Tablette · 1 h par jour');
    expect(
      ruleSummary(
        const Rule(id: 'x', childId: 'emma', dailyQuota: Duration(hours: 1)),
        const S('fr'),
      ),
      '1 h par jour',
    );
  });
}
