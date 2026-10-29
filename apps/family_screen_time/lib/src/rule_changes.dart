/// Rules changed on another device (a parent's, or another device in parent
/// mode): what the child's device tells the child when they arrive.
library;

import 'dart:convert';

import 'package:screentime_engine/screentime_engine.dart';

import 'family.dart';
import 'store.dart';
import 'strings.dart';

enum RuleChangeKind { added, changed, removed }

class RuleChange {
  final RuleChangeKind kind;

  /// The rule as it is now; as it was, once removed.
  final Rule rule;

  const RuleChange(this.kind, this.rule);
}

/// The ids of the rules [keys] (keys of the family log's events) touch.
Set<String> touchedRules(Iterable<String> keys, String rulePrefix) => {
  for (final k in keys)
    if (k.startsWith(rulePrefix)) k.substring(rulePrefix.length),
};

/// How the rules [touched] of [childId] went from [before] to [after]. The
/// limits the child set for themselves are left out: the child knows.
List<RuleChange> ruleChanges(
  FamilyData before,
  FamilyData after,
  Set<String> touched,
  String childId,
) {
  Rule? find(FamilyData f, String id) {
    for (final r in f.state.rules) {
      if (r.id == id) return r;
    }
    return null;
  }

  final out = <RuleChange>[];
  for (final id in touched) {
    final was = find(before, id);
    final now = find(after, id);
    final rule = now ?? was;
    if (rule == null || rule.childId != childId || rule.setByChild) continue;
    if (was == null && now != null) {
      out.add(RuleChange(RuleChangeKind.added, now));
    } else if (was != null && now == null) {
      out.add(RuleChange(RuleChangeKind.removed, was));
    } else if (was != null &&
        now != null &&
        jsonEncode(ruleToJson(was)) != jsonEncode(ruleToJson(now))) {
      out.add(RuleChange(RuleChangeKind.changed, now));
    }
  }
  return out;
}

/// The notification's title and text for [changes] (not empty).
(String, String) ruleChangeNotice(
  List<RuleChange> changes,
  FamilyData family,
  S s, {
  Map<String, String> labels = const {},
}) {
  final periods = {for (final p in family.config.profiles) p.id: p.name};
  String label(Rule r) => ruleLabel(r, family, s, labels: labels);
  String what(RuleChange c) {
    if (c.kind == RuleChangeKind.removed) return s.t('ruleChangeRemovedText');
    if (!c.rule.enabled) return s.t('ruleOff');
    final summary = ruleSummary(c.rule, s, periodNames: periods);
    return summary.isEmpty ? s.t('noLimit') : summary;
  }

  if (changes.length == 1) {
    final c = changes.single;
    return (
      s.t('ruleChange_${c.kind.name}', {'label': label(c.rule)}),
      what(c),
    );
  }
  return (
    s.t('ruleChangesTitle', {'count': '${changes.length}'}),
    [
      for (final c in changes)
        s.t('ruleChangeLine', {
          'kind': s.t('ruleChangeShort_${c.kind.name}'),
          'label': label(c.rule),
          'what': what(c),
        }),
    ].join('\n'),
  );
}
