import 'dart:io';

import 'package:family_screen_time/src/monitor.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

/// Drives the monitor through a fake Android side.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.familyscreentime/monitor');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory dir;
  late LocalStore store;
  late List<MethodCall> calls;
  late Monitor monitor;

  Future<void> send(String method, Object? args) =>
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );

  /// Records [minutes] of Minecraft, right after the previous call's,
  /// starting 45 minutes ago.
  var cursor = DateTime.now();
  Future<void> use(int minutes) async {
    final end = cursor.add(Duration(minutes: minutes));
    await store.appendUsage(
      UsageSegment.device(
        childId: 'emma',
        deviceId: 'tablet',
        appId: 'minecraft',
        start: cursor,
        end: end,
      ),
    );
    cursor = end;
  }

  setUp(() async {
    cursor = DateTime.now().subtract(const Duration(minutes: 45));
    dir = await Directory.systemTemp.createTemp('fst');
    store = LocalStore(dir);
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'state') return {'foreground': null, 'screenOn': true};
      return null;
    });
    await store.saveSettings(
      const AppSettings(
        deviceId: 'tablet',
        language: 'fr',
        setupDone: true,
        childId: 'emma',
      ),
    );
    await store.saveFamily(
      FamilyData(
        children: const [Child(id: 'emma', name: 'Emma')],
        config: const FamilyConfig(
          appGroups: {
            'games': {'minecraft'},
          },
          neverBlocked: {'launcher'},
        ),
        state: FamilyState(
          rules: [
            Rule(
              id: 'r',
              childId: 'emma',
              appTarget: const AppTarget.group('games'),
              // Never allowed: the test does not depend on the time of day.
              schedule: WeeklySchedule(const {}),
            ),
          ],
        ),
        groupNames: const {'games': 'Jeux'},
      ),
    );
    monitor = Monitor(store);
    await monitor.start();
  });

  tearDown(() async {
    monitor.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });

  test('opening a blocked app shows the block screen', () async {
    await send('foreground', {'package': 'minecraft'});
    final block = calls.where((c) => c.method == 'block').toList();
    expect(block, hasLength(1));
    final args = block.single.arguments as Map<Object?, Object?>;
    expect(args['message'], contains('horaires'));
  });

  test('an app without rules gets the "no limit" countdown', () async {
    await send('foreground', {'package': 'youtube'});
    expect(calls.where((c) => c.method == 'block'), isEmpty);
    final last = calls.lastWhere((c) => c.method == 'countdown');
    expect(
      (last.arguments as Map<Object?, Object?>)['title'],
      'Pas de limite pour cette appli',
    );
  });

  test('screen off closes the current segment', () async {
    await send('foreground', {'package': 'youtube'});
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await send('screen', {'on': false});
    final usage = await store.loadUsage(since: dayOf(DateTime.now()));
    expect(usage.single.appId, 'youtube');
    expect(await store.loadOpen(), isNull);
  });

  test('with a family log, use goes into it, history once', () async {
    if (dayOf(DateTime.now()) != dayOf(cursor)) {
      return markTestSkipped('too close to midnight');
    }
    await use(10);
    final (ui, _) = await FamilySync.create(
      store: store,
      settings: await store.loadSettings(),
      family: await store.loadFamily(),
      parentCode: '123456',
      deviceName: 'Tablette',
    );
    await send('reload', null);
    await send('reload', null);
    final logged = await ui.readOthers();
    // The 10 minutes recorded before the family existed, once.
    expect(logged.map((e) => e.data['appId']), ['minecraft']);
    // Then use as it is recorded.
    await send('foreground', {'package': 'youtube'});
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await send('screen', {'on': false});
    final live = await ui.readOthers();
    expect(live.single.data['appId'], 'youtube');
    expect(live.single.origin, 'tablet#usage');
  });

  test('a reload picks up new rules', () async {
    await send('foreground', {'package': 'youtube'});
    final family = await store.loadFamily();
    await store.saveFamily(
      family.copyWith(
        state: FamilyState(
          rules: [
            ...family.state.rules,
            Rule(
              id: 'all',
              childId: 'emma',
              schedule: WeeklySchedule(const {}),
            ),
          ],
        ),
      ),
    );
    await send('reload', null);
    expect(calls.where((c) => c.method == 'block'), hasLength(1));
  });

  test('the volume caps go to Android, once per change', () async {
    final family = await store.loadFamily();
    await store.saveFamily(
      family.copyWith(
        children: const [Child(id: 'emma', name: 'Emma', volumeHeadphones: 60)],
      ),
    );
    await send('reload', null);
    final sent = calls.where((c) => c.method == 'volumeCap').toList();
    final args = sent.last.arguments as Map<Object?, Object?>;
    expect(args['headphones'], 60);
    expect(args['speaker'], isNull);
    expect(args['message'], 'Volume limité à {percent} %');
    await send('reload', null);
    expect(calls.where((c) => c.method == 'volumeCap'), hasLength(sent.length));
  });

  test('the floating countdown follows the child\'s choice', () async {
    final settings = await store.loadSettings();
    await store.saveSettings(settings.copyWith(overlay: 'disc'));
    final family = await store.loadFamily();
    await store.saveFamily(
      family.copyWith(
        state: const FamilyState(
          rules: [
            Rule(
              id: 'r',
              childId: 'emma',
              appTarget: AppTarget.group('games'),
              dailyQuota: Duration(minutes: 60),
            ),
          ],
        ),
      ),
    );
    await send('reload', null);
    await send('foreground', {'package': 'minecraft'});
    final shown = calls.lastWhere((c) => c.method == 'overlay');
    final args = shown.arguments as Map<Object?, Object?>;
    expect(args['style'], 'disc');
    final endsAt = DateTime.fromMillisecondsSinceEpoch(args['endsAt'] as int);
    expect(
      endsAt.difference(DateTime.now()).inMinutes,
      inInclusiveRange(58, 60),
    );

    await send('foreground', {'package': 'youtube'});
    expect(
      calls.last.method == 'overlayHide' ||
          calls.any((c) => c.method == 'overlayHide'),
      isTrue,
    );

    await store.saveSettings(settings.copyWith(overlay: 'off'));
    await send('foreground', {'package': 'minecraft'});
    await send('reload', null);
    final overlays = calls.where((c) => c.method == 'overlay').length;
    await send('foreground', {'package': 'youtube'});
    await send('foreground', {'package': 'minecraft'});
    expect(calls.where((c) => c.method == 'overlay').length, overlays);
  });

  test('the countdown leaves out the limits the child chose', () async {
    final settings = await store.loadSettings();
    await store.saveSettings(
      settings.copyWith(overlay: 'digits', hiddenCountdowns: {'group:games'}),
    );
    final family = await store.loadFamily();
    await store.saveFamily(
      family.copyWith(
        state: const FamilyState(
          rules: [
            Rule(
              id: 'r',
              childId: 'emma',
              appTarget: AppTarget.group('games'),
              dailyQuota: Duration(minutes: 60),
            ),
            Rule(id: 'all', childId: 'emma', dailyQuota: Duration(hours: 2)),
          ],
        ),
      ),
    );
    await send('reload', null);
    await send('foreground', {'package': 'minecraft'});
    int minutesShown() {
      final args =
          calls.lastWhere((c) => c.method == 'overlay').arguments
              as Map<Object?, Object?>;
      return DateTime.fromMillisecondsSinceEpoch(args['endsAt'] as int)
          .difference(DateTime.now())
          .inMinutes;
    }

    // Games left out: the total time, though the games end sooner.
    expect(minutesShown(), inInclusiveRange(118, 120));
    final countdown = calls.lastWhere((c) => c.method == 'countdown');
    expect(
      (countdown.arguments as Map<Object?, Object?>)['title'],
      contains('Jeux'),
    );

    // Everything left out: no floating countdown.
    await store.saveSettings(
      settings.copyWith(
        overlay: 'digits',
        hiddenCountdowns: {'group:games', 'all'},
      ),
    );
    await send('reload', null);
    expect(calls.last.method, 'overlayHide');
  });

  group('listen only', () {
    final today = DateTime.now();
    final tooEarly =
        today.difference(dayOf(today)) < const Duration(minutes: 20);

    Future<void> prepare(List<UsageSegment> usage) async {
      final family = await store.loadFamily();
      await store.saveFamily(
        family.copyWith(
          config: family.config.copyWith(
            appGroups: {
              'music': {'spotify'},
            },
          ),
          groupNames: const {'music': 'Musique'},
          state: const FamilyState(
            rules: [
              Rule(
                id: 'clips',
                childId: 'emma',
                appTarget: AppTarget.group('music'),
                dailyQuota: Duration(minutes: 10),
                listenOnly: ListenOnlyPolicy(),
              ),
            ],
          ),
        ),
      );
      for (final u in usage) {
        await store.appendUsage(u);
      }
      await send('reload', null);
    }

    UsageSegment spotify(String app, int fromMinutes, int toMinutes) {
      final now = DateTime.now();
      return UsageSegment.device(
        childId: 'emma',
        deviceId: 'tablet',
        appId: app,
        start: now.subtract(Duration(minutes: fromMinutes)),
        end: now.subtract(Duration(minutes: toMinutes)),
      );
    }

    test('the app opens to pick the music, recorded apart', () async {
      if (tooEarly) return markTestSkipped('too close to midnight');
      await prepare([spotify('spotify', 15, 5)]);
      await send('foreground', {'package': 'spotify'});
      expect(calls.where((c) => c.method == 'block'), isEmpty);
      final warn = calls.lastWhere((c) => c.method == 'warn');
      expect(
        (warn.arguments as Map<Object?, Object?>)['title'],
        'Écoute seule : 1 min pour choisir ta musique',
      );
      final countdown = calls.lastWhere((c) => c.method == 'countdown');
      expect(
        (countdown.arguments as Map<Object?, Object?>)['title'],
        'Musique : écoute seule',
      );
      expect((await store.loadOpen())!.appId, listenOnlyUse('spotify'));
      // Said once per opening.
      await send('reload', null);
      expect(calls.where((c) => c.method == 'warn'), hasLength(1));
    });

    test('reopened too soon: closed, the music goes on', () async {
      if (tooEarly) return markTestSkipped('too close to midnight');
      await prepare([
        spotify('spotify', 15, 5),
        spotify(listenOnlyUse('spotify'), 2, 1),
      ]);
      await send('foreground', {'package': 'spotify'});
      final block = calls.lastWhere((c) => c.method == 'block');
      final args = block.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Écoute seule');
      expect(
        args['message'] as String,
        startsWith(
          'Musique : la musique continue en arrière-plan. '
          'L\'appli pourra se rouvrir à ',
        ),
      );
    });
  });

  group('warnings', () {
    final now = DateTime.now();
    // Usage written before the test, within today.
    final todayOnly =
        dayOf(now.subtract(const Duration(minutes: 70))) == dayOf(now);

    /// Minecraft used [minutes] earlier today, an hour ago, apart from the
    /// use going on.
    Future<void> earlier(int minutes) {
      final end = DateTime.now().subtract(const Duration(minutes: 60));
      return store.appendUsage(
        UsageSegment.device(
          childId: 'emma',
          deviceId: 'tablet',
          appId: 'minecraft',
          start: end.subtract(Duration(minutes: minutes)),
          end: end,
        ),
      );
    }

    Future<void> prepare({
      required int usedMinutes,
      List<int>? warnings,
      int graceReminders = 1,
    }) async {
      final settings = await store.loadSettings();
      await store.saveSettings(settings.copyWith(warningMinutes: warnings));
      final family = await store.loadFamily();
      await store.saveFamily(
        family.copyWith(
          graceReminderMinutes: graceReminders,
          state: const FamilyState(
            rules: [
              Rule(
                id: 'r',
                childId: 'emma',
                appTarget: AppTarget.group('games'),
                dailyQuota: Duration(minutes: 30),
                grace: GracePolicy(length: Duration(minutes: 10)),
              ),
            ],
          ),
        ),
      );
      // Minecraft in use until now: the time ran out while playing.
      cursor = DateTime.now().subtract(Duration(minutes: usedMinutes));
      await use(usedMinutes);
      await send('reload', null);
    }

    List<String> warnings() => [
      for (final c in calls)
        if (c.method == 'warn')
          (c.arguments as Map<Object?, Object?>)['title'] as String,
    ];

    test('before the end, at the times the child chose', () async {
      if (!todayOnly) return markTestSkipped('too close to midnight');
      await prepare(usedMinutes: 28, warnings: [3]);
      await send('foreground', {'package': 'minecraft'});
      expect(warnings(), ['Plus que 2 min']);
      await send('foreground', {'package': 'minecraft'});
      expect(warnings(), hasLength(1));
    });

    test('none when the child chose none', () async {
      if (!todayOnly) return markTestSkipped('too close to midnight');
      await prepare(usedMinutes: 28, warnings: []);
      await send('foreground', {'package': 'minecraft'});
      expect(warnings(), isEmpty);
    });

    test('grace time says the time is up, then reminds', () async {
      if (!todayOnly) return markTestSkipped('too close to midnight');
      await prepare(usedMinutes: 32, warnings: [], graceReminders: 2);
      await send('foreground', {'package': 'minecraft'});
      // Announced on entering grace time, whatever the child chose.
      expect(warnings(), ['Temps dépassé : fermeture dans 8 min']);
      final countdown = calls.lastWhere((c) => c.method == 'countdown');
      expect(
        (countdown.arguments as Map<Object?, Object?>)['title'],
        'Jeux : temps dépassé',
      );
      // Two more minutes of grace used: the next reminder, at 6 minutes left.
      await earlier(2);
      await send('reload', null);
      expect(warnings(), [
        'Temps dépassé : fermeture dans 8 min',
        'Temps dépassé : fermeture dans 6 min',
      ]);
    });

    test('out of time, the block says so and names the app', () async {
      if (!todayOnly) return markTestSkipped('too close to midnight');
      await prepare(usedMinutes: 41);
      await send('foreground', {'package': 'minecraft'});
      final block = calls.lastWhere((c) => c.method == 'block');
      final args = block.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Le temps est écoulé');
      expect(args['message'], 'Jeux : plus de temps disponible.');
      // Android fills in the app's name.
      expect(args['closed'], 'L\'appli {app} a été fermée.');
      expect(args['package'], 'minecraft');
    });

    test('out of screen time: when it comes back, and what closes', () async {
      if (!todayOnly) return markTestSkipped('too close to midnight');
      final family = await store.loadFamily();
      await store.saveFamily(
        family.copyWith(
          outOfTime: OutOfTime.device,
          state: const FamilyState(
            rules: [
              Rule(
                id: 'all',
                childId: 'emma',
                dailyQuota: Duration(minutes: 30),
              ),
            ],
          ),
        ),
      );
      await use(31);
      await send('reload', null);
      await send('foreground', {'package': 'youtube'});
      final block = calls.lastWhere((c) => c.method == 'block');
      final args = block.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Le temps est écoulé');
      expect(
        args['message'],
        'Ton temps d\'aujourd\'hui est écoulé. On se retrouve demain.',
      );
      final lock =
          calls.lastWhere((c) => c.method == 'lockState').arguments
              as Map<Object?, Object?>;
      expect(lock['deviceLocked'], isTrue);
      expect(lock['settingsLocked'], isTrue);
      expect(lock['message'], args['message']);
    });

    test('the device locks only once the app in grace is left', () async {
      if (!todayOnly) return markTestSkipped('too close to midnight');
      final family = await store.loadFamily();
      await store.saveFamily(
        family.copyWith(
          outOfTime: OutOfTime.device,
          state: const FamilyState(
            rules: [
              Rule(
                id: 'all',
                childId: 'emma',
                dailyQuota: Duration(minutes: 30),
                grace: GracePolicy(length: Duration(minutes: 10)),
              ),
            ],
          ),
        ),
      );
      cursor = DateTime.now().subtract(const Duration(minutes: 32));
      await use(32);
      await send('reload', null);
      await send('foreground', {'package': 'minecraft'});
      Map<Object?, Object?> lock() =>
          calls.lastWhere((c) => c.method == 'lockState').arguments
              as Map<Object?, Object?>;
      expect(lock()['deviceLocked'], isFalse);
      expect(calls.where((c) => c.method == 'block'), isEmpty);
      await send('foreground', {'package': 'launcher'});
      expect(lock()['deviceLocked'], isTrue);
    });

    test(
      'with time left, the settings stay open unless for the parent only',
      () async {
        await send('foreground', {'package': 'youtube'});
        var lock =
            calls.lastWhere((c) => c.method == 'lockState').arguments
                as Map<Object?, Object?>;
        expect(lock['settingsLocked'], isFalse);
        expect(lock['deviceLocked'], isFalse);

        final family = await store.loadFamily();
        await store.saveFamily(family.copyWith(settingsParentOnly: true));
        await send('reload', null);
        lock =
            calls.lastWhere((c) => c.method == 'lockState').arguments
                as Map<Object?, Object?>;
        expect(lock['settingsLocked'], isTrue);
        expect(
          lock['settingsMessage'],
          'Les paramètres sont réservés au parent.',
        );
      },
    );

    test(
      'Family Link\'s lock screen never counts, even recorded before',
      () async {
        if (!todayOnly) return markTestSkipped('too close to midnight');
        final family = await store.loadFamily();
        await store.saveFamily(
          family.copyWith(
            state: const FamilyState(
              rules: [
                Rule(
                  id: 'all',
                  childId: 'emma',
                  dailyQuota: Duration(minutes: 30),
                ),
              ],
            ),
          ),
        );
        // Recorded by an earlier version, which counted it.
        await store.appendUsage(
          UsageSegment.device(
            childId: 'emma',
            deviceId: 'tablet',
            appId: 'com.google.android.gms.supervision',
            start: DateTime.now().subtract(const Duration(minutes: 44)),
            end: DateTime.now().subtract(const Duration(minutes: 2)),
          ),
        );
        await send('reload', null);
        await send('foreground', {'package': 'youtube'});
        expect(calls.where((c) => c.method == 'block'), isEmpty);
      },
    );

    test('a break the child took is called a break', () async {
      final family = await store.loadFamily();
      await store.saveFamily(
        family.copyWith(
          state: FamilyState(
            rules: family.state.rules,
            temporaryBlocks: [
              TemporaryBlock(
                id: 'p',
                childId: 'emma',
                from: DateTime.now().subtract(const Duration(minutes: 1)),
                until: DateTime.now().add(const Duration(minutes: 14)),
                voluntary: true,
              ),
            ],
          ),
        ),
      );
      await send('reload', null);
      await send('foreground', {'package': 'youtube'});
      final block = calls.lastWhere((c) => c.method == 'block');
      final args = block.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Pause');
      expect(args['message'], startsWith('Tu fais une pause jusqu\'à'));
    });

    test('grace reminders can be limited to the start', () async {
      if (!todayOnly) return markTestSkipped('too close to midnight');
      await prepare(usedMinutes: 32, graceReminders: 0);
      await send('foreground', {'package': 'minecraft'});
      await earlier(4);
      await send('reload', null);
      expect(warnings(), ['Temps dépassé : fermeture dans 8 min']);
    });

    test('grace is only for the app in use when time ran out', () async {
      if (!todayOnly) return markTestSkipped('too close to midnight');
      await prepare(usedMinutes: 32);
      await send('foreground', {'package': 'minecraft'});
      expect(calls.where((c) => c.method == 'block'), isEmpty);
      // Leaving Minecraft for a few seconds and coming back: grace is over.
      await send('foreground', {'package': 'launcher'});
      final back = DateTime.now();
      await store.appendUsage(
        UsageSegment.device(
          childId: 'emma',
          deviceId: 'tablet',
          appId: 'launcher',
          start: back.subtract(const Duration(seconds: 3)),
          end: back,
        ),
      );
      await send('reload', null);
      await send('foreground', {'package': 'minecraft'});
      final block = calls.lastWhere((c) => c.method == 'block');
      expect(
        (block.arguments as Map<Object?, Object?>)['message'],
        'Jeux : plus de temps disponible.',
      );
    });
  });
}
