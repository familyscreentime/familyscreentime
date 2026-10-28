/// Access to the system side, Android or Windows (permissions, apps,
/// monitor control).
library;

import 'dart:io' show Platform;

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

/// Packages with a special role on this device.
class SystemPackages {
  final String self;
  final String? dialer;
  final String? sms;
  final List<String> launchers;

  const SystemPackages({
    required this.self,
    this.dialer,
    this.sms,
    this.launchers = const [],
  });
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

class PlatformApi {
  static const _channel = MethodChannel('org.familyscreentime/platform');

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
