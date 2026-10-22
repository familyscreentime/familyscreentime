import 'package:convert/convert.dart';
import 'package:family_screen_time/src/pin.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PBKDF2-HMAC-SHA256 matches the RFC 7914 test vector', () {
    final key = pbkdf2('passwd'.codeUnits, 'salt'.codeUnits, 1, 64);
    expect(
      hex.encode(key),
      '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
      '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
    );
  });

  group('Parent code', () {
    const base = AppSettings(deviceId: 'd', language: 'en');

    test('the right code is accepted, a wrong one refused', () async {
      final s = await withNewPin(base, '123456');
      expect((await checkPin(s, '123456')).ok, isTrue);
      expect((await checkPin(s, '654321')).ok, isFalse);
    });

    test('five failures lock the code, for longer each time', () async {
      var s = await withNewPin(base, '123456');
      final now = DateTime(2026, 10, 20, 12);
      for (var i = 0; i < 4; i++) {
        final r = await checkPin(s, '000000', now: now);
        expect(r.lockedFor, isNull);
        s = r.settings;
      }
      final fifth = await checkPin(s, '000000', now: now);
      expect(fifth.lockedFor, const Duration(seconds: 30));
      // Even the right code is refused while locked.
      final locked = await checkPin(fifth.settings, '123456', now: now);
      expect(locked.ok, isFalse);
      final sixth = await checkPin(
        fifth.settings,
        '000000',
        now: now.add(const Duration(seconds: 31)),
      );
      expect(sixth.lockedFor, const Duration(minutes: 1));
      final unlocked = await checkPin(
        sixth.settings,
        '123456',
        now: now.add(const Duration(minutes: 5)),
      );
      expect(unlocked.ok, isTrue);
      expect(unlocked.settings.pinFailures, 0);
    });
  });
}
