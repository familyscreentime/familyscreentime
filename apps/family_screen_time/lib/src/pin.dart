/// Parent code hashing (PBKDF2-HMAC-SHA256) and attempt throttling.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'store.dart';

const pinIterations = 60000;
const minPinLength = 6;

/// PBKDF2 with HMAC-SHA256 (RFC 8018).
List<int> pbkdf2(
  List<int> password,
  List<int> salt,
  int iterations,
  int length,
) {
  final hmac = Hmac(sha256, password);
  final out = <int>[];
  for (var block = 1; out.length < length; block++) {
    var u = hmac.convert([
      ...salt,
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ]).bytes;
    final t = List<int>.of(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.addAll(t);
  }
  return out.sublist(0, length);
}

/// Hashes [pin] off the main thread so the interface does not freeze.
Future<String> hashPin(String pin, String salt, int iterations) => Isolate.run(
  () => base64Encode(
    pbkdf2(utf8.encode(pin), base64Decode(salt), iterations, 32),
  ),
);

String newSalt() {
  final r = Random.secure();
  return base64Encode(List.generate(16, (_) => r.nextInt(256)));
}

/// Settings with a new parent code.
Future<AppSettings> withNewPin(AppSettings s, String pin) async {
  final salt = newSalt();
  final hash = await hashPin(pin, salt, pinIterations);
  return s.copyWith(
    pinHash: hash,
    pinSalt: salt,
    pinIterations: pinIterations,
    pinFailures: 0,
    clearLock: true,
  );
}

bool _sameBytes(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Result of a code check, with the settings to save.
class PinCheck {
  final bool ok;
  final Duration? lockedFor;
  final AppSettings settings;

  const PinCheck(this.ok, this.lockedFor, this.settings);
}

/// Checks [pin]. After 5 failures, each new failure locks the code for an
/// increasing time: 30 s, 1 min, 2 min… up to 1 h.
Future<PinCheck> checkPin(AppSettings s, String pin, {DateTime? now}) async {
  final t = now ?? DateTime.now();
  final locked = s.pinLockedUntil;
  if (locked != null && t.isBefore(locked)) {
    return PinCheck(false, locked.difference(t), s);
  }
  if (s.pinHash == null || s.pinSalt == null) return PinCheck(false, null, s);
  final hash = await hashPin(pin, s.pinSalt!, s.pinIterations);
  if (_sameBytes(hash, s.pinHash!)) {
    return PinCheck(true, null, s.copyWith(pinFailures: 0, clearLock: true));
  }
  final failures = s.pinFailures + 1;
  Duration? lock;
  if (failures >= 5) {
    final seconds = min(3600, 30 * pow(2, failures - 5).toInt());
    lock = Duration(seconds: seconds);
  }
  return PinCheck(
    false,
    lock,
    s.copyWith(
      pinFailures: failures,
      pinLockedUntil: lock == null ? null : t.add(lock),
    ),
  );
}
