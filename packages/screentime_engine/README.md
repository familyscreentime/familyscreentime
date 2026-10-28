# screentime_engine

The Family Screen Time rule engine, in pure Dart with no dependencies.
It answers a single question: **this app, on this device, for this child,
right now — allowed or not, and for how long?**

The engine is stateless. Everything it knows comes from a `FamilyState`
(rebuilt from the event log) and the instant passed in. Two devices holding
the same log therefore reach the same decision.

## Usage

```dart
import 'package:screentime_engine/screentime_engine.dart';

final engine = RuleEngine(FamilyConfig(
  appGroups: {'games': {'com.mojang.minecraftpe', 'com.roblox.client'}},
  deviceGroups: {'tablets': {'living-room-tablet'}},
  alwaysAllowed: {'com.android.dialer', 'com.google.android.apps.messaging'},
));

final state = FamilyState(
  rules: [
    Rule(
      id: 'games',
      childId: 'emma',
      appTarget: const AppTarget.group('games'),
      dailyQuota: const Duration(minutes: 60),
      rollover: const RolloverPolicy(days: 1),
      grace: const GracePolicy(length: Duration(minutes: 5)),
      breakPolicy: const BreakPolicy(
        after: Duration(minutes: 30),
        length: Duration(minutes: 10),
      ),
    ),
  ],
  usage: [/* usage segments */],
);

final d = engine.evaluate(state,
    childId: 'emma',
    deviceId: 'living-room-tablet',
    appId: 'com.roblox.client',
    now: DateTime.now());

if (!d.allowed) {
  // Block; d.reason says why, d.until says when it changes.
} else if (d.remaining != null) {
  // Show the countdown; d.limiter says what sets it.
}
```

## Evaluation order

1. "Always allowed" app or system component: allowed.
2. Active family block: blocked.
3. Temporary block on the app, the device or the child: blocked.
4. Day unlocked: allowed until midnight.
5. Pick today's profile (holidays, then custom, then normal) and the
   applicable rules. No rule: allowed.
6. Outside a rule's time ranges: blocked.
7. Mandatory break in progress: blocked.
8. Quota exhausted: grace period if any is left and the app was already in use when the time ran out; then, for a "listen only" rule, a short opening to pick the music; otherwise blocked.
9. Allowed; the countdown shows the nearest limit (quota, end of the time
   range, or next break).

## Design decisions

| Topic | Behaviour |
| --- | --- |
| Simultaneous use | `SimultaneousCounting.sum` (default): two devices at once count twice. `elapsed`: once. |
| App in several groups | Every rule targeting it applies; the strictest wins. |
| Injected time | Counts towards rules that target all devices and whose target is "All", the same target, or a group containing the injected app. Never triggers a break. |
| Expired bonus | Only counts for the part consumed while valid, so it does not inflate the week. |
| Grace | The overrun since the quota ran out is taken from the grace, so grace is used once per exhaustion. Grace is for finishing, not for starting: only the app in use when the time ran out keeps going, and only until it is left (another app, or a pause of more than a few seconds). Another app of the limit, or the same app opened again, is blocked. |
| Listen only | Optional (`ListenOnlyPolicy`), for music apps that also show clips. Once the time (grace included) is used up, the app opens for `openFor` (1 min by default) to pick the music, then is sent to the background, where the music keeps playing; it opens again `reopenAfter` (2 min) after it was left. That opening is recorded as `listenOnlyUse(app)`: it counts for total screen time, not for the rule's group or app. |
| Hardening | Counts past days (today excluded) whose daily overrun exceeded the threshold V. Relies on the daily limit. |
| Deducting overruns | Optional (`HardeningPolicy.deductOverruns`). When the limit turns firm, the overruns of the window become a debt, each overrun once, paid from the following days' time (a day's time cannot go below zero; the rest waits for the next day). Ignored when the rule has a carry-over. |
| Carry-over | Only affects the daily period. Measured against the nominal quota so carry-overs do not snowball. An unlocked day produces no overrun. |
| Saved time | Optional (`RolloverPolicy`), per rule, so it can be limited to one kind of time (e.g. games but not total screen time). Unused daily quota stays available for X days; a day without use saves its whole quota. Spent after the day's quota, oldest first, before grace. Only the nominal quota is saved (carry-over deducted, bonuses excluded). Optional `cap` on the balance; savings expiring tonight do not count against it. Weekly and rolling quotas still cap. |
| Turned-off rules | `Rule.enabled` false: the rule is kept, settings included, but never applies. |
| Apps open within the hours | `FamilyConfig.allowedInHours`: never counted nor limited by time, but closed outside the hours and during blocks (unlike `alwaysAllowed`, open at any time). |
| Hours opened early | `HoursUnlock`: a rule's schedule does not apply from `from` to `until` (its time limits still do); the countdown runs to `until`. |
| Daily time by weekday | `dailyQuotaByWeekday` overrides `dailyQuota` for given weekdays; zero blocks the day. A weekday with neither has no daily limit: it produces no overrun or savings and takes no carry-over. |
| Days outside a profile | A day when the rule is not in force produces neither savings nor overruns. |
| Mandatory break | Use on all covered devices is merged; a gap at least as long as the break resets the counter. |
| Eye break | Not a rule: `EyeBreakPolicy` per child, and `screenStretchStart` gives the start of the stretch of screen use on one device (all apps, those beside the one in front counted once). A gap at least as long as the break ends the stretch. `lengthAfter` makes a later break longer, in proportion, up to three times its length. |
| Rule history | Past days are recomputed with the current rules. |

## Tests

```sh
dart pub get
dart test
```

## Licence

MIT, see `LICENSE` at the repository root.
