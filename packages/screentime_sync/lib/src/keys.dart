/// Keys: the family's parent key, kept sealed by the parent code on every
/// device, and each device's own keys.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'event.dart';
import 'hlc.dart';

final _ed25519 = Ed25519();
final _x25519 = X25519();
final _random = Random.secure();

/// [n] random bytes from the system's secure generator.
Uint8List randomBytes(int n) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) _random.nextInt(256)]);

String b64(List<int> bytes) => base64Encode(bytes);

/// SHA-256 of [bytes].
Future<List<int>> sha256Bytes(List<int> bytes) async =>
    (await Sha256().hash(bytes)).bytes;
Uint8List unb64(String s) => base64Decode(s);

/// An Ed25519 key pair, kept as its 32-byte seed.
class SigningKey {
  final Uint8List seed;
  final SimpleKeyPair _pair;
  final String publicKey;

  SigningKey._(this.seed, this._pair, this.publicKey);

  static Future<SigningKey> fromSeed(List<int> seed) async {
    final pair = await _ed25519.newKeyPairFromSeed(seed);
    final public = await pair.extractPublicKey();
    return SigningKey._(Uint8List.fromList(seed), pair, b64(public.bytes));
  }

  static Future<SigningKey> generate() => fromSeed(randomBytes(32));

  /// Ed25519 signature of [message], base64.
  Future<String> sign(List<int> message) async {
    final s = await _ed25519.sign(message, keyPair: _pair);
    return b64(s.bytes);
  }
}

/// Whether [signature] (base64) is [publicKey]'s (base64) for [message].
Future<bool> verifySignature(
  List<int> message,
  String signature,
  String publicKey,
) async {
  try {
    return await _ed25519.verify(
      message,
      signature: Signature(
        unb64(signature),
        publicKey: SimplePublicKey(unb64(publicKey), type: KeyPairType.ed25519),
      ),
    );
  } on Object {
    return false;
  }
}

/// An X25519 key pair, for agreeing on session keys.
class AgreementKey {
  final Uint8List seed;
  final SimpleKeyPair _pair;
  final String publicKey;

  AgreementKey._(this.seed, this._pair, this.publicKey);

  static Future<AgreementKey> fromSeed(List<int> seed) async {
    final pair = await _x25519.newKeyPairFromSeed(seed);
    final public = await pair.extractPublicKey();
    return AgreementKey._(Uint8List.fromList(seed), pair, b64(public.bytes));
  }

  static Future<AgreementKey> generate() => fromSeed(randomBytes(32));

  /// The secret shared with the owner of [remotePublicKey] (base64).
  Future<List<int>> agree(String remotePublicKey) async {
    final secret = await _x25519.sharedSecretKey(
      keyPair: _pair,
      remotePublicKey: SimplePublicKey(
        unb64(remotePublicKey),
        type: KeyPairType.x25519,
      ),
    );
    return secret.extractBytes();
  }
}

/// A device's own identity: its id and signing key. The private part never
/// leaves the device.
class DeviceIdentity {
  final String deviceId;
  final SigningKey signing;

  DeviceIdentity(this.deviceId, this.signing);

  static Future<DeviceIdentity> generate(String deviceId) async =>
      DeviceIdentity(deviceId, await SigningKey.generate());

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'signingSeed': b64(signing.seed),
  };

  static Future<DeviceIdentity> fromJson(Map<String, Object?> j) async =>
      DeviceIdentity(
        j['deviceId'] as String,
        await SigningKey.fromSeed(unb64(j['signingSeed'] as String)),
      );
}

/// Signs [draft] as event [seq] of [origin].
Future<SyncEvent> signEvent({
  required String origin,
  required int seq,
  required Hlc hlc,
  required EventDraft draft,
  required Signer signer,
  required SigningKey key,
}) async {
  final unsigned = SyncEvent(
    origin: origin,
    seq: seq,
    hlc: hlc,
    type: draft.type,
    key: draft.key,
    data: draft.data,
    signer: signer,
    sig: '',
  );
  return SyncEvent(
    origin: origin,
    seq: seq,
    hlc: hlc,
    type: draft.type,
    key: draft.key,
    data: draft.data,
    signer: signer,
    sig: await key.sign(unsigned.signedBytes),
  );
}

/// Whether [e] is signed by [publicKey] (base64).
Future<bool> verifyEvent(SyncEvent e, String publicKey) =>
    verifySignature(e.signedBytes, e.sig, publicKey);

/// The parent key sealed by the parent code, as stored on every device and
/// shared in the family log: Argon2id derives a key from the code, which
/// encrypts the key's seed (XChaCha20-Poly1305).
abstract final class ParentVault {
  /// Argon2id cost: memory in KiB and passes (OWASP's minimum for
  /// interactive use). Kept in the sealed form, so it can grow later.
  static const memory = 19 * 1024;
  static const iterations = 2;

  static Future<SecretKey> _derive(
    String code,
    List<int> salt,
    int memory,
    int iterations,
  ) => Argon2id(
    parallelism: 1,
    memory: memory,
    iterations: iterations,
    hashLength: 32,
  ).deriveKeyFromPassword(password: code, nonce: salt);

  /// The parent key's seed, sealed by [code].
  static Future<Map<String, Object?>> seal(List<int> seed, String code) async {
    final salt = randomBytes(16);
    final key = await _derive(code, salt, memory, iterations);
    final box = await Xchacha20.poly1305Aead().encrypt(seed, secretKey: key);
    return {
      'v': 1,
      'kdf': 'argon2id',
      'm': memory,
      't': iterations,
      'salt': b64(salt),
      'nonce': b64(box.nonce),
      'box': b64([...box.cipherText, ...box.mac.bytes]),
    };
  }

  /// The parent key, or `null` when [code] is wrong.
  static Future<SigningKey?> open(
    Map<String, Object?> sealed,
    String code,
  ) async {
    final seed = await openBytes(sealed, code);
    return seed == null ? null : SigningKey.fromSeed(seed);
  }

  /// The bytes [seal]ed, or `null` when [code] is wrong.
  static Future<List<int>?> openBytes(
    Map<String, Object?> sealed,
    String code,
  ) async {
    final key = await _derive(
      code,
      unb64(sealed['salt'] as String),
      (sealed['m'] as num).toInt(),
      (sealed['t'] as num).toInt(),
    );
    final box = unb64(sealed['box'] as String);
    try {
      final seed = await Xchacha20.poly1305Aead().decrypt(
        SecretBox(
          box.sublist(0, box.length - 16),
          nonce: unb64(sealed['nonce'] as String),
          mac: Mac(box.sublist(box.length - 16)),
        ),
        secretKey: key,
      );
      return seed;
    } on SecretBoxAuthenticationError {
      return null;
    }
  }
}
