/// Access to the system side, Android or Windows (permissions, apps,
/// monitor control).
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Name and icon (PNG) of an installed app.
class AppInfo {
  final String label;
  final Uint8List? icon;

  const AppInfo(this.label, this.icon);
}

class InstalledApp {
  final String package;
  final String label;

  const InstalledApp(this.package, this.label);
}

/// An app version: its name (`0.28.1`) and its number (55), which grows
/// with every version.
class AppVersion {
  final String name;
  final int build;

  const AppVersion(this.name, this.build);
}

/// Packages with a special role on this device.
class SystemPackages {
  final String self;
  final String? dialer;
  final String? sms;
  final List<String> launchers;

  /// The screens of a phone call (the in-call screens and the phone app),
  /// which differ from maker to maker.
  final List<String> callScreens;

  const SystemPackages({
    required this.self,
    this.dialer,
    this.sms,
    this.launchers = const [],
    this.callScreens = const [],
  });
}

/// How a biometric prompt went.
enum BiometricStatus {
  ok,

  /// The parent chose the code instead, or left.
  cancelled,

  /// A finger or a face was added, or the screen lock removed: what was
  /// sealed can no longer be opened.
  invalidated,

  /// Too many tries: the device's own lock must be used first.
  lockout,

  /// No strong biometric on this device (or Android before 10).
  unavailable,
  error,
}

/// What a biometric prompt gave: the [seal] of a code, or the [code].
class BiometricResult {
  final BiometricStatus status;
  final String? seal;
  final String? code;

  const BiometricResult(this.status, {this.seal, this.code});

  bool get ok => status == BiometricStatus.ok;
}

/// The words of the biometric prompt.
class BiometricTexts {
  final String title;
  final String? subtitle;

  /// The button that leaves the prompt (for the code).
  final String cancel;

  const BiometricTexts({
    required this.title,
    this.subtitle,
    required this.cancel,
  });

  Map<String, Object?> toMap() => {
    'title': title,
    'subtitle': subtitle,
    'cancel': cancel,
  };
}

/// Whether this is the Windows client (a PC), rather than Android; tests
/// set it to try the Windows client.
bool onWindows = Platform.isWindows;

/// Permissions the monitor relies on, in the order they are asked for. On
/// Windows: starting with Windows, running now, and whether the child's
/// account is a standard one (an administrator could stop the monitor).
List<String> get permissionKinds => onWindows
    ? const ['autostartWindows', 'monitorRunning', 'standardAccount']
    : const [
        'accessibility',
        'overlay',
        'notifications',
        'battery',
        'usageAccess',
        'deviceAdmin',
      ];

/// Permissions without which limits cannot be enforced.
Set<String> get requiredPermissions => onWindows
    ? const {'autostartWindows', 'monitorRunning'}
    : const {'accessibility', 'overlay', 'notifications'};

/// A method channel that, on Windows, writes each call and its outcome to
/// the log: after a crash, the last call without an outcome says where.
class LoggedMethodChannel extends MethodChannel {
  const LoggedMethodChannel(super.name);

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    if (!onWindows) return super.invokeMethod<T>(method, arguments);
    final short = name.substring(name.lastIndexOf('/') + 1);
    debugPrint('→ $short.$method');
    var outcome = 'failed';
    try {
      final result = await super.invokeMethod<T>(method, arguments);
      outcome = 'ok';
      return result;
    } finally {
      debugPrint('← $short.$method $outcome');
    }
  }
}

class PlatformApi {
  static const _channel = LoggedMethodChannel('org.familyscreentime/platform');

  const PlatformApi();

  Future<Map<String, bool>> permissionStatus() async {
    final m = await _channel.invokeMapMethod<String, bool>('permissionStatus');
    return m ?? const {};
  }

  Future<void> openPermissionSettings(String kind) =>
      _channel.invokeMethod('openPermissionSettings', {'kind': kind});

  Future<List<InstalledApp>> launcherApps() async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'launcherApps',
    );
    return [
      for (final m in list ?? const <Map<Object?, Object?>>[])
        InstalledApp(m['package'] as String, m['label'] as String),
    ];
  }

  /// Names and icons of [packages]; missing ones are not installed (or not
  /// visible to this app). Icons are [iconSize] pixels wide when given.
  Future<Map<String, AppInfo>> appInfo(
    Iterable<String> packages, {
    int? iconSize,
  }) async {
    final m = await _channel.invokeMapMethod<String, Object?>('appInfo', {
      'packages': packages.toList(),
      'size': ?iconSize,
    });
    return {
      for (final e in (m ?? const {}).entries)
        e.key: AppInfo(
          (e.value as Map<Object?, Object?>)['label'] as String,
          (e.value as Map<Object?, Object?>)['icon'] as Uint8List?,
        ),
    };
  }

  /// Foreground sessions rebuilt from Android's own usage history, between
  /// [from] and [to]. Android keeps about ten days of it. `null` without
  /// usage access.
  ///
  /// [closeOpen]: the use still going on counts up to [to].
  Future<List<({String package, DateTime start, DateTime end})>?> usageHistory(
    DateTime from,
    DateTime to, {
    bool closeOpen = false,
  }) async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'usageHistory',
      {
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
        if (closeOpen) 'closeOpen': true,
      },
    );
    if (list == null) return null;
    return [
      for (final m in list)
        (
          package: m['package'] as String,
          start: DateTime.fromMillisecondsSinceEpoch(m['start'] as int),
          end: DateTime.fromMillisecondsSinceEpoch(m['end'] as int),
        ),
    ];
  }

  /// This app's version: its name (`0.28.1`) and its number (55); `null`
  /// when the platform cannot say.
  Future<AppVersion?> appVersion() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('appVersion');
      final version = m?['version'];
      final build = m?['build'];
      if (version is! String || build is! num) return null;
      return AppVersion(version, build.toInt());
    } on Object {
      return null;
    }
  }

  /// A strong biometric (fingerprint, face) can open parent mode here.
  Future<bool> biometricAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('biometricAvailable') ?? false;
    } on Object {
      return false;
    }
  }

  /// Seals [code] behind the biometric, after a prompt.
  Future<BiometricResult> biometricSeal(String code, BiometricTexts texts) =>
      _biometric('biometricSeal', {'code': code, ...texts.toMap()});

  /// Opens a [seal], after a prompt: the code.
  Future<BiometricResult> biometricOpen(String seal, BiometricTexts texts) =>
      _biometric('biometricOpen', {'seal': seal, ...texts.toMap()});

  /// Forgets the biometric key: no seal opens any more.
  Future<void> biometricForget() async {
    try {
      await _channel.invokeMethod<void>('biometricForget');
    } on Object {
      // Nothing to forget.
    }
  }

  Future<BiometricResult> _biometric(
    String method,
    Map<String, Object?> args,
  ) async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>(method, args);
      final status = BiometricStatus.values.firstWhere(
        (s) => s.name == m?['status'],
        orElse: () => BiometricStatus.unavailable,
      );
      return BiometricResult(
        status,
        seal: m?['seal'] as String?,
        code: m?['code'] as String?,
      );
    } on Object {
      return const BiometricResult(BiometricStatus.unavailable);
    }
  }

  Future<SystemPackages> systemPackages() async {
    final m =
        await _channel.invokeMapMethod<String, Object?>('systemPackages') ?? {};
    return SystemPackages(
      self: m['self'] as String? ?? 'org.familyscreentime',
      dialer: m['dialer'] as String?,
      sms: m['sms'] as String?,
      launchers: [
        for (final p in m['launchers'] as List<Object?>? ?? const [])
          p as String,
      ],
      callScreens: [
        for (final p in m['callScreens'] as List<Object?>? ?? const [])
          p as String,
      ],
    );
  }

  Future<void> startMonitor() => _channel.invokeMethod('startMonitor');

  /// The device's maker and model ("Xiaomi Redmi Pad 2"), to name it.
  Future<String> deviceName() async {
    try {
      return await _channel.invokeMethod<String>('deviceName') ?? _system;
    } on Object {
      return _system;
    }
  }

  static String get _system => onWindows ? 'PC' : 'Android';

  Future<void> reloadMonitor() => _channel.invokeMethod('reloadMonitor');

  /// Offers the file at [path] to the apps that take one (Drive, mail…).
  /// Whether it could be offered.
  Future<bool> shareFile(String path, String mime, String subject) async {
    try {
      return await _channel.invokeMethod<bool>('shareFile', {
            'path': path,
            'mime': mime,
            'subject': subject,
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  /// While parent mode is on (for [duration] at most), the Android settings
  /// pages that could switch the app off may be opened, and a notification
  /// says so, with a button to leave it ([texts]: title, text, leave).
  Future<void> setParentMode(
    bool on, {
    Duration duration = Duration.zero,
    Map<String, String> texts = const {},
  }) => _channel.invokeMethod('parentMode', {
    'on': on,
    'forMs': duration.inMilliseconds,
    ...texts,
  });

  /// Calls from Android to the interface.
  static void listen({
    required void Function() onLeaveParentMode,
    void Function()? onFamilyChanged,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'leaveParentMode':
          onLeaveParentMode();
        case 'familyChanged':
          onFamilyChanged?.call();
      }
      return null;
    });
  }

  /// Turns uninstall protection off, without going through the settings.
  Future<void> disableDeviceAdmin() =>
      _channel.invokeMethod('disableDeviceAdmin');
}
