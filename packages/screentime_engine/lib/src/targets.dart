/// Targets of rules, bonuses and blocks.
library;

/// Kind of target: everything, a single item, or a named group.
enum TargetKind { all, single, group }

/// App target: all apps, one app, or an app group.
class AppTarget {
  final TargetKind kind;

  /// App or group id; `null` for [TargetKind.all].
  final String? id;

  const AppTarget.all() : kind = TargetKind.all, id = null;

  const AppTarget.app(String this.id) : kind = TargetKind.single;

  const AppTarget.group(String this.id) : kind = TargetKind.group;

  /// True when [appId] is covered, given the app groups
  /// (group id → app ids).
  bool covers(String appId, Map<String, Set<String>> appGroups) {
    switch (kind) {
      case TargetKind.all:
        return true;
      case TargetKind.single:
        return id == appId;
      case TargetKind.group:
        return appGroups[id]?.contains(appId) ?? false;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AppTarget && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => switch (kind) {
    TargetKind.all => 'AppTarget.all',
    TargetKind.single => 'AppTarget.app($id)',
    TargetKind.group => 'AppTarget.group($id)',
  };
}

/// Device target: all devices, one device, or a device group
/// (e.g. "Tablets").
class DeviceTarget {
  final TargetKind kind;

  /// Device or group id; `null` for [TargetKind.all].
  final String? id;

  const DeviceTarget.all() : kind = TargetKind.all, id = null;

  const DeviceTarget.device(String this.id) : kind = TargetKind.single;

  const DeviceTarget.group(String this.id) : kind = TargetKind.group;

  /// True when [deviceId] is covered, given the device groups.
  bool covers(String deviceId, Map<String, Set<String>> deviceGroups) {
    switch (kind) {
      case TargetKind.all:
        return true;
      case TargetKind.single:
        return id == deviceId;
      case TargetKind.group:
        return deviceGroups[id]?.contains(deviceId) ?? false;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceTarget && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => switch (kind) {
    TargetKind.all => 'DeviceTarget.all',
    TargetKind.single => 'DeviceTarget.device($id)',
    TargetKind.group => 'DeviceTarget.group($id)',
  };
}
