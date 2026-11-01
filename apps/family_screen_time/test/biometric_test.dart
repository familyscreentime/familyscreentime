import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/pin.dart';
import 'package:family_screen_time/src/platform.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/ui/pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.familyscreentime/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory dir;
  late List<String> calls;

  /// What the next prompt answers; null: as a real one would.
  String? answer;
  bool available = true;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fst');
    calls = [];
    answer = null;
    available = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'biometricAvailable':
          return available;
        case 'biometricSeal':
          return answer == null
              ? {'status': 'ok', 'seal': 'sealed:${args['code']}'}
              : {'status': answer};
        case 'biometricOpen':
          final seal = args['seal'] as String;
          return answer == null
              ? {'status': 'ok', 'code': seal.substring('sealed:'.length)}
              : {'status': answer};
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });

  Future<AppController> controller({
    bool parentDevice = true,
    String code = '123456',
  }) async {
    final settings = await withNewPin(
      AppSettings(
        deviceId: 'd',
        language: 'fr',
        setupDone: true,
        parentDevice: parentDevice,
        childId: parentDevice ? null : 'emma',
      ),
      code,
    );
    return AppController(
      LocalStore(dir),
      settings,
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
      ),
    );
  }

  test('turned on with the code, then opens parent mode', () async {
    final c = await controller();
    expect(await c.biometricAvailable(), isTrue);
    expect(c.biometricOn, isFalse);
    expect(await c.enableBiometric('123456'), BiometricStatus.ok);
    expect(c.biometricOn, isTrue);
    expect(c.settings.biometricOffered, isTrue);
    expect(c.parentCodeKnown, isFalse);
    expect(await c.biometricUnlock(), BiometricStatus.ok);
    expect(c.parentCodeKnown, isTrue);
    // Kept on the device.
    final back = AppSettings.fromJson(c.settings.toJson());
    expect(back.biometricSeal, 'sealed:123456');
    expect(back.biometricOffered, isTrue);
  });

  test(
    'a finger or a face added: the code is asked, and offered again',
    () async {
      final c = await controller();
      await c.enableBiometric('123456');
      answer = 'invalidated';
      expect(await c.biometricUnlock(), BiometricStatus.invalidated);
      expect(c.biometricOn, isFalse);
      expect(c.settings.biometricOffered, isFalse);
      expect(calls, contains('biometricForget'));
    },
  );

  test('the code changed since: no failure counted, turned off', () async {
    final c = await controller();
    await c.enableBiometric('123456');
    await c.updateSettings(await withNewPin(c.settings, '999999'));
    expect(await c.biometricUnlock(), BiometricStatus.invalidated);
    expect(c.settings.pinFailures, 0);
    expect(c.biometricOn, isFalse);
    expect(c.parentCodeKnown, isFalse);
  });

  test('cancelled: nothing changes, the code is typed', () async {
    final c = await controller();
    await c.enableBiometric('123456');
    answer = 'cancelled';
    expect(await c.biometricUnlock(), BiometricStatus.cancelled);
    expect(c.biometricOn, isTrue);
    expect(c.parentCodeKnown, isFalse);
  });

  test('opens even while typed codes are locked out', () async {
    final c = await controller();
    await c.enableBiometric('123456');
    for (var i = 0; i < 5; i++) {
      await c.checkParentCode('000000');
    }
    expect((await c.checkParentCode('123456')).ok, isFalse);
    expect(await c.biometricUnlock(), BiometricStatus.ok);
    expect(c.settings.pinFailures, 0);
    expect(c.settings.pinLockedUntil, isNull);
  });

  test('a new code: the former one is no longer kept', () async {
    final c = await controller();
    await c.enableBiometric('123456');
    await c.changeParentCode('654321');
    expect(c.biometricOn, isFalse);
    expect(c.settings.biometricSeal, isNull);
    expect(calls, contains('biometricForget'));
  });

  test('turned off by the parent: not offered again', () async {
    final c = await controller();
    await c.enableBiometric('123456');
    await c.disableBiometric();
    expect(c.biometricOn, isFalse);
    expect(c.settings.biometricOffered, isTrue);
  });

  test('never on a child\'s device', () async {
    final c = await controller(parentDevice: false);
    expect(await c.biometricAvailable(), isFalse);
    expect(await c.enableBiometric('123456'), BiometricStatus.error);
    expect(c.biometricOn, isFalse);
    expect(calls, isNot(contains('biometricSeal')));
  });

  testWidgets('offered once after the code is typed', (tester) async {
    final c = await tester.runAsync(controller);
    bool? ok;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => ok = await askParentPin(context, c!),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('OK'));
    // The code is hashed off the main thread.
    for (var i = 0; i < 50 && find.text('Activer').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Ouvrir avec l\'empreinte ?'), findsOneWidget);
    await tester.tap(find.text('Activer'));
    for (var i = 0; i < 50 && ok == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(ok, isTrue);
    expect(c!.biometricOn, isTrue);
  });

  testWidgets('turned on: asked first, the code not needed', (tester) async {
    final c = (await tester.runAsync(controller))!;
    await tester.runAsync(() => c.enableBiometric('123456'));
    bool? ok;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => ok = await askParentPin(context, c),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 50 && ok == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(ok, isTrue);
    expect(calls, contains('biometricOpen'));
    expect(c.parentCodeKnown, isTrue);
  });
}
