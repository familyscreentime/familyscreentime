# Family Screen Time — Android client

First version of the child-device client. It runs on its own, without a
server or another device: the parent sets the rules on the child's device,
behind the parent code.

## What it does

- Detects the app in the foreground (accessibility service, with usage
  statistics as a fallback) and records usage per day.
- Evaluates the rules with `screentime_engine` and enforces them: the
  child is sent home and a notice says why ("Time is up", the app that was
  closed), drawn over the home screen so the closing is not taken for a
  crash; a full-screen activity without the accessibility service; a countdown in a persistent notification, and
  warnings before time runs out (10, 5 and 1 minute by default; the child
  picks them). Once grace time starts, the message says the time is up and
  when the app closes, at the start and then at an interval only the
  parent sets (every minute by default).
- Warnings and the floating countdown are drawn by the app in the
  accessibility service's overlay layer, so they show over full-screen
  games and whatever the notification settings (Do Not Disturb, game
  modes); the warning is also kept, quietly, in the notifications. Without
  the accessibility service, the countdown uses "display over other apps"
  and warnings fall back to pop-up notifications.
- Parent mode behind a 6-digit code (PBKDF2, throttled after 5 failures,
  closes after 5 minutes without a touch).
- Quick actions in parent mode: extra time on a limit until midnight (the
  limit closest to running out is offered first; a bonus can be taken
  back), lifting every restriction until midnight, blocking all apps or a
  group now (15 min to 2 h, until a given time, or until lifted). The
  child's home screen shows a lifted day and the blocks in force.
- Parent screen organised by kind of time: one line for total screen time,
  then one per app group, each leading to its rules (which can be turned
  off without being deleted) and, for a group, its apps. In the group
  editor, the group's apps come first.
- App groups chosen from the installed apps, and rules per group or for
  total screen time: time per day (one value, or one per weekday), time per week,
  allowed hours set day by day (a day without any range is blocked all day;
  one day's ranges can be copied to others).
- Rule settings for a maximum over a rolling period of several days, a
  mandatory break after continuous use, and carrying overruns over to the
  next day or spreading them over several days.
- Special periods (holidays, exams, study leave, a week at the
  grandparents', Lent…): named by the parent, each with its dates; each
  rule applies always, in normal times, or only during one of them. When
  periods overlap, the first in the list wins (drag to reorder). The child
  sees which period is running.
- Limits on a single app, besides total screen time and groups (from the
  parent screen or from the app's detail in the usage screen).
- Limits the child sets for themselves, freely and without the code (an
  app, a group or total screen time, a time per day), shown with "my
  limit" on their home screen. The parent sees the facts, with no
  judgement: days kept and exceeded, changes and removals, average lifetime
  and gap to the limit, over 7 or 30 days. The child is told this view
  exists.
- When there is no screen time left at all, the message says when it comes
  back ("Your time for today is up. See you tomorrow from 9.", "in 3 days"),
  on the block notice and the child's home screen. The parent chooses what
  happens then: the apps close; the Android settings and wallpaper close
  too (default); or the whole device is locked, behind a
  screen that only opens the phone, messages and this app (never over the
  lock screen or a call). The settings can also be kept for the parent only
  at all times.
- A rule belongs to the kind of time it was created for (total screen
  time, a group or an app). Its time per day can be 0 min: the apps are then
  only open with extra time from the parent.
- Extra time can go to one or more limits at once (game time without
  raising total screen time); the child's card shows it apart ("30 min
  planned + 15 min bonus"). Every duration offered in one tap has an
  "Other…" choice for any length.
- Outside its hours, a rule can be opened early from quick actions until
  the end of its next range (at 9:20, open until 12:00 for hours from 10
  to 12); its time limits still apply.
- Always available apps are chosen by the parent, each either at any hour
  (the phone: even during blocks and on a locked device) or within the
  hours only (messages); never limited by time nor counted.
- Outside the hours set for all apps, this app itself only opens parent
  mode.
- A notification shows while parent mode is on, with a button to leave it.
- Durations offered in one tap, chosen per child by the parent (e.g. 15,
  25, 35 and 45 min): extra time, blocks, time away from the devices,
  breaks, and the length of a mandatory break.
- The child can take a break of their own: every app is blocked (phone and
  messages aside) for the chosen time, which only a parent can cut short;
  messages say "break" rather than "blocked".
- Eye breaks, on by default and set per child: every 20 minutes of screen
  on a device, a notice at the top of the screen, then a veil with a
  countdown asking the child to look into the distance for 20 seconds. The
  child may put it off by a minute, three times; a later break lasts
  longer, in proportion (23 s after 23 min). Nothing is blocked, the time
  under the veil is not screen time, and the break waits for a call to end.
- Time away from the devices (console, TV), entered by the parent in quick
  actions, counts for total screen time or a group.
- Rule settings for grace time (with an optional firm limit after repeated
  overruns, which can also deduct those overruns from the following days)
  and for keeping unused daily time.
- Child's home screen: total screen time first, set apart, then each
  group: time left of the day's total with a progress bar, and the apps
  used today in it (not for total screen time: the usage screen has them).
- Per rule with a daily limit, the child's history of overruns and savings,
  day by day over the firm limit's window (7 days otherwise), with where the
  firm limit stands.
- Child's settings: floating countdown (digits, or a Time Timer-style disc
  on a 60-minute dial, shown over limited apps and draggable) and the
  warnings before time runs out. Tapping the countdown opens the app.
- Group labels next to each app (usage list and detail, group editor); in
  parent mode they lead to the group's rules. The group list shows the time
  spent today in each group.
- Apps can be renamed; the name is used everywhere in the app.
- Usage screen, whatever the rules: time per app today, over 7 or 30 days,
  by day and by hour, with flags for apps worth a look (first used in the
  last 7 days, not limited by any rule, used between 22:00 and 06:00). From
  parent mode, an app can be put in groups straight from its detail.
  On first use, Android's own usage history is imported (it keeps about ten
  days in detail), for statistics only: the rules never see it.
- A parent's device, locked: only the app's name and the unlock button.
  Unlocked: each child by name, a padlock saying whether their devices
  are locked now, and the actions that fit: extra time or unlocking (until
  the end of the next allowed hours today, which start early, or until
  midnight), or blocking now. With several children, "Lock everything" or
  "Unlock everything". Then the linked devices and the family's settings.
- A block can carry a short message for the child ("Dinner's ready!"),
  shown on the block screen; the messages written before are offered again.
- Family settings (special periods, devices used at the same time, how long
  use is kept, parent code): their own page on a parent's device, at the
  end of parent mode's settings on a child's device.
- Interface in French, Dutch and English.

This completes the features planned for phase 1 on Android; the next step
is a period of real use before the Windows client.

## How it fits together

```
MainActivity ── Flutter UI (lib/src/ui) ── writes settings.json, family.json
                                              │
MonitorService (foreground service)           │ reads
  └─ headless Flutter engine: monitorMain() ──┘
       lib/src/monitor.dart ── writes usage/YYYY-MM-DD.jsonl
         ▲ foreground app, screen on/off      │ countdown, warn, block
         │                                     ▼
ForegroundAccessibilityService            overlays (notice, banner, countdown),
                                          BlockActivity, notifications
```

- `MonitorService` starts at boot, when the app opens and when the
  accessibility service connects. It runs the Dart entry point
  `monitorMain` in its own Flutter engine, so the rules are evaluated by the
  same Dart code as everywhere else.
- Files are JSON in the app's private folder, each with a single writer.
  Usage is append-only, one file per day. The segment in progress is saved
  every 30 seconds in `open.json`, so a crash loses at most that much.
- Time in "always allowed" apps and in system components (home screens,
  settings, Google's parental supervision and its lock screen, Google Play
  services, this
  app) is never blocked and never counted; nor is the time the lock screen
  is shown (counting starts at unlock).

## Permissions

| Permission | Why | Required |
| --- | --- | --- |
| Accessibility service | Knows the app on screen at once, can send the child home, and shows warnings and the countdown over full-screen apps | Yes |
| Display over other apps | Opens the block screen from the background | Yes |
| Notifications | Countdown and warnings | Yes |
| No battery optimisation | Keeps the monitor alive | Strongly advised |
| Usage access | Fallback detection when accessibility is off; with uninstall protection, closes the safety center | Advised |
| Device administrator | Uninstall protection: see below | Optional |

On Android 13+, a sideloaded app needs "Allow restricted settings" before
its accessibility service can be turned on.

## Build and test

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

`flutter run` with a phone connected installs a debug build.

The demonstration build is an app of its own (`org.familyscreentime.demo`),
beside the real one: a parent's device with a made-up family of two
children, linked to nothing and started afresh at each launch, to check
the screens and take screenshots. Its parent code is 1234.

```sh
flutter build apk --release -t lib/main_demo.dart -P demo=true
```

Release builds are signed with the upload key named in `android/key.properties`
(not in the repository: `storePassword`, `keyPassword`, `keyAlias`, and
`storeFile`, relative to `android/`). Without that file they are signed with
the debug key, for local testing only. For Google Play:

```sh
flutter build appbundle --release   # build/app/outputs/bundle/release/app-release.aab
```

Google Play re-signs the app with its own key (Play App Signing): an APK
installed by hand cannot be updated from Play, and the reverse, without
uninstalling first.

## Uninstall protection

Android has no way to ask for a code in its own settings, so the
protection has two parts:

- The app is a device administrator (with no policies): Android refuses to
  uninstall it while that is on.
- While it is on, the accessibility service closes at once, with a notice,
  the settings pages that could switch the app off: turning off device
  administrators, and every settings or installer page about this app (app
  info with force stop and uninstall, its accessibility service, its
  permissions), recognised by their title, the app's name; and Android's
  security pages when they name the app (the safety center's "Review this
  app with full access to the device", which offers to remove its access).
  To find those, the screen content is read on the security and permission
  pages, and nowhere else. Since Android 14 the safety center ("Security &
  privacy") sends nothing to accessibility services that are not assistive
  tools, so it is recognised from the usage statistics instead (checked
  every second, needs usage access) and closed whatever it shows.

Updating is not affected: the installer's update screens are left alone
(versions 0.7.1 and 0.7.2 closed them too; with those, switch to parent mode
before installing an APK update). Google Play updates show no installer
screen and go through either way.

Those pages open normally while parent mode is on, and for three minutes
after the app itself opened one (permissions screen). To uninstall, turn
the protection off in parent mode (Permissions › Uninstall protection ›
Turn off), then uninstall as usual.

## Known limits of this version

- One child per device, no synchronisation between devices yet.
- Usage is only known for this device, from about ten days before
  installation onwards. Android also keeps weekly totals for four weeks,
  which are not imported.
- Apps without a launcher icon show their package name instead of their
  name and icon (Android's package visibility).
- Without the accessibility service, a blocked app is detected within about
  3 seconds and the block screen is shown again every 10 seconds.
- A child who is a device administrator, or who reaches the settings by a
  path the guard does not recognise (manufacturer screens, safe mode,
  a computer with adb), can still stop the monitor. Tamper alerts come
  with sync.
