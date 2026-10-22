/// Local storage shared by the interface and the monitor.
///
/// Plain JSON files in the app's private folder. The interface writes the
/// settings and the family data; the monitor writes usage. Each file has a
/// single writer, and writes are atomic (temporary file, then rename).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:screentime_engine/screentime_engine.dart';

import 'self_limits.dart';

/// Warnings before time runs out, by default.
const defaultWarningMinutes = [10, 5, 1];

/// Settings of this device.
class AppSettings {
  final String deviceId;
  final String language;
  final bool setupDone;
  final String? childId;
  final String? pinHash;
  final String? pinSalt;
  final int pinIterations;
  final int pinFailures;
  final DateTime? pinLockedUntil;

  /// Android's own usage history has been imported (done once).
  final bool historyImported;

  /// Floating countdown chosen by the child: off, digits or disc.
  final String overlay;

  /// Minutes left at which the child wants a warning.
  final List<int> warningMinutes;

  /// Limits the floating countdown leaves out, by [countdownKey]: the
  /// child's choice. Warnings and closing still follow every limit.
  final Set<String> hiddenCountdowns;

  const AppSettings({
    required this.deviceId,
    required this.language,
    this.setupDone = false,
    this.childId,
    this.pinHash,
    this.pinSalt,
    this.pinIterations = 0,
    this.pinFailures = 0,
    this.pinLockedUntil,
    this.historyImported = false,
    this.overlay = 'off',
    this.warningMinutes = defaultWarningMinutes,
    this.hiddenCountdowns = const {},
  });

  AppSettings copyWith({
    String? language,
    bool? setupDone,
    String? childId,
    String? pinHash,
    String? pinSalt,
    int? pinIterations,
    int? pinFailures,
    DateTime? pinLockedUntil,
    bool clearLock = false,
    bool? historyImported,
    String? overlay,
    List<int>? warningMinutes,
    Set<String>? hiddenCountdowns,
  }) => AppSettings(
    deviceId: deviceId,
    language: language ?? this.language,
    setupDone: setupDone ?? this.setupDone,
    childId: childId ?? this.childId,
    pinHash: pinHash ?? this.pinHash,
    pinSalt: pinSalt ?? this.pinSalt,
    pinIterations: pinIterations ?? this.pinIterations,
    pinFailures: pinFailures ?? this.pinFailures,
    pinLockedUntil: clearLock ? null : pinLockedUntil ?? this.pinLockedUntil,
    historyImported: historyImported ?? this.historyImported,
    overlay: overlay ?? this.overlay,
    warningMinutes: warningMinutes ?? this.warningMinutes,
    hiddenCountdowns: hiddenCountdowns ?? this.hiddenCountdowns,
  );

  Json toJson() => {
    'deviceId': deviceId,
    'language': language,
    'setupDone': setupDone,
    if (childId != null) 'childId': childId,
    if (pinHash != null) 'pinHash': pinHash,
    if (pinSalt != null) 'pinSalt': pinSalt,
    'pinIterations': pinIterations,
    'pinFailures': pinFailures,
    if (pinLockedUntil != null)
      'pinLockedUntil': instantToJson(pinLockedUntil!),
    if (historyImported) 'historyImported': true,
    if (overlay != 'off') 'overlay': overlay,
    'warningMinutes': warningMinutes,
    if (hiddenCountdowns.isNotEmpty)
      'hiddenCountdowns': hiddenCountdowns.toList()..sort(),
  };

  factory AppSettings.fromJson(Json j) => AppSettings(
    deviceId: j['deviceId'] as String,
    language: j['language'] as String? ?? 'en',
    setupDone: j['setupDone'] as bool? ?? false,
    childId: j['childId'] as String?,
    pinHash: j['pinHash'] as String?,
    pinSalt: j['pinSalt'] as String?,
    pinIterations: (j['pinIterations'] as num?)?.toInt() ?? 0,
    pinFailures: (j['pinFailures'] as num?)?.toInt() ?? 0,
    pinLockedUntil: optionalInstant(j['pinLockedUntil']),
    historyImported: j['historyImported'] as bool? ?? false,
    overlay: j['overlay'] as String? ?? 'off',
    hiddenCountdowns: {
      for (final k in j['hiddenCountdowns'] as List<Object?>? ?? const [])
        k as String,
    },
    warningMinutes: j['warningMinutes'] == null
        ? defaultWarningMinutes
        : [
            for (final m in j['warningMinutes'] as List<Object?>)
              (m as num).toInt(),
          ],
  );
}

/// Key of [t] in [AppSettings.hiddenCountdowns]: total screen time, a
/// group or an app.
String countdownKey(AppTarget t) =>
    t.kind == TargetKind.all ? 'all' : '${t.kind.name}:${t.id}';

/// What happens when there is no screen time left at all.
enum OutOfTime {
  /// The apps close; settings and home screen stay open.
  apps,

  /// The Android settings (and wallpaper) close too.
  settings,

  /// The whole device is covered, except the phone, messages and this app.
  device,
}

/// Durations offered in one tap, in minutes, unless the parent chose others.
const defaultPresets = [15, 30, 45, 60];

class Child {
  final String id;
  final String name;

  /// Durations offered in one tap for this child, in minutes: bonuses,
  /// blocks, breaks…
  final List<int> presets;

  /// Media volume cap with headphones, in percent of the maximum; `null`:
  /// no cap.
  final int? volumeHeadphones;

  /// Media volume cap on the speaker, in percent; `null`: no cap.
  final int? volumeSpeaker;

  const Child({
    required this.id,
    required this.name,
    this.presets = defaultPresets,
    this.volumeHeadphones,
    this.volumeSpeaker,
  });

  Child withPresets(List<int> presets) => Child(
    id: id,
    name: name,
    presets: presets,
    volumeHeadphones: volumeHeadphones,
    volumeSpeaker: volumeSpeaker,
  );

  /// The same child with new volume caps (`null`: no cap).
  Child withVolume({int? headphones, int? speaker}) => Child(
    id: id,
    name: name,
    presets: presets,
    volumeHeadphones: headphones,
    volumeSpeaker: speaker,
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'presets': presets,
    'volumeHeadphones': ?volumeHeadphones,
    'volumeSpeaker': ?volumeSpeaker,
  };

  factory Child.fromJson(Json j) => Child(
    id: j['id'] as String,
    name: j['name'] as String,
    presets: j['presets'] == null
        ? defaultPresets
        : [for (final m in j['presets'] as List<Object?>) (m as num).toInt()],
    volumeHeadphones: (j['volumeHeadphones'] as num?)?.toInt(),
    volumeSpeaker: (j['volumeSpeaker'] as num?)?.toInt(),
  );
}

/// Family data: children, configuration, rules and modifiers (not usage).
class FamilyData {
  final List<Child> children;
  final FamilyConfig config;
  final FamilyState state;

  /// Display names of the app groups, by group id.
  final Map<String, String> groupNames;

  /// Names chosen by the parent for apps, by package.
  final Map<String, String> appNames;

  /// Minutes between reminders during grace time; 0: at the start only.
  final int graceReminderMinutes;

  /// Time spent away from the devices (console, TV), entered by the parent.
  /// Kept here rather than with the recorded usage, which only the monitor
  /// writes.
  final List<UsageSegment> injected;

  /// Every change the child made to their own limits, for the parent's
  /// follow-up view.
  final List<SelfLimitEvent> selfLimitLog;

  /// What happens when there is no screen time left at all: close the apps
  /// only, close the Android settings too, or lock the whole device.
  final OutOfTime outOfTime;

  /// The Android settings only open in parent mode, even with time left.
  final bool settingsParentOnly;

  const FamilyData({
    this.children = const [],
    this.config = const FamilyConfig(),
    this.state = const FamilyState(),
    this.groupNames = const {},
    this.appNames = const {},
    this.graceReminderMinutes = 1,
    this.injected = const [],
    this.selfLimitLog = const [],
    this.outOfTime = OutOfTime.settings,
    this.settingsParentOnly = false,
  });

  FamilyData copyWith({
    List<Child>? children,
    FamilyConfig? config,
    FamilyState? state,
    Map<String, String>? groupNames,
    Map<String, String>? appNames,
    int? graceReminderMinutes,
    List<UsageSegment>? injected,
    List<SelfLimitEvent>? selfLimitLog,
    OutOfTime? outOfTime,
    bool? settingsParentOnly,
  }) => FamilyData(
    children: children ?? this.children,
    config: config ?? this.config,
    state: state ?? this.state,
    groupNames: groupNames ?? this.groupNames,
    appNames: appNames ?? this.appNames,
    graceReminderMinutes: graceReminderMinutes ?? this.graceReminderMinutes,
    injected: injected ?? this.injected,
    selfLimitLog: selfLimitLog ?? this.selfLimitLog,
    outOfTime: outOfTime ?? this.outOfTime,
    settingsParentOnly: settingsParentOnly ?? this.settingsParentOnly,
  );

  Child? child(String? id) {
    for (final c in children) {
      if (c.id == id) return c;
    }
    return null;
  }

  Json toJson() => {
    'children': [for (final c in children) c.toJson()],
    'config': familyConfigToJson(config),
    'state': familyStateToJson(state),
    'groupNames': groupNames,
    if (appNames.isNotEmpty) 'appNames': appNames,
    'graceReminderMinutes': graceReminderMinutes,
    if (injected.isNotEmpty)
      'injected': [for (final u in injected) usageSegmentToJson(u)],
    if (selfLimitLog.isNotEmpty)
      'selfLimitLog': [for (final e in selfLimitLog) e.toJson()],
    'outOfTime': outOfTime.name,
    if (settingsParentOnly) 'settingsParentOnly': true,
  };

  factory FamilyData.fromJson(Json j) => FamilyData(
    children: [
      for (final c in j['children'] as List<Object?>? ?? const [])
        Child.fromJson(c as Json),
    ],
    config: familyConfigFromJson(j['config'] as Json? ?? const {}),
    state: familyStateFromJson(j['state'] as Json? ?? const {}),
    groupNames: {
      for (final e in (j['groupNames'] as Json? ?? const {}).entries)
        e.key: e.value as String,
    },
    appNames: {
      for (final e in (j['appNames'] as Json? ?? const {}).entries)
        e.key: e.value as String,
    },
    graceReminderMinutes: (j['graceReminderMinutes'] as num?)?.toInt() ?? 1,
    injected: [
      for (final u in j['injected'] as List<Object?>? ?? const [])
        usageSegmentFromJson(u as Json),
    ],
    selfLimitLog: [
      for (final e in j['selfLimitLog'] as List<Object?>? ?? const [])
        SelfLimitEvent.fromJson(e as Json),
    ],
    outOfTime:
        OutOfTime.values.asNameMap()[j['outOfTime']] ?? OutOfTime.settings,
    settingsParentOnly: j['settingsParentOnly'] as bool? ?? false,
  );
}

/// The app currently in use, saved regularly so a crash loses little.
class OpenSegment {
  final String appId;
  final DateTime start;
  final DateTime lastSeen;

  const OpenSegment(this.appId, this.start, this.lastSeen);

  Json toJson() => {
    'appId': appId,
    'start': instantToJson(start),
    'lastSeen': instantToJson(lastSeen),
  };

  factory OpenSegment.fromJson(Json j) => OpenSegment(
    j['appId'] as String,
    instantFromJson(j['start']),
    instantFromJson(j['lastSeen']),
  );
}

/// Random identifier, 16 bytes in hexadecimal.
String newId() {
  final r = Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class LocalStore {
  final Directory dir;

  LocalStore(this.dir);

  static Future<LocalStore> open() async =>
      LocalStore(await getApplicationSupportDirectory());

  File _file(String name) => File('${dir.path}/$name');

  Directory get _usageDir => Directory('${dir.path}/usage');

  Future<Json?> _readJson(String name) async {
    final f = _file(name);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Json;
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeJson(String name, Json data) async {
    final tmp = _file('$name.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(_file(name).path);
  }

  /// Settings; created with a new device id on first use.
  Future<AppSettings> loadSettings({String? defaultLanguage}) async {
    final j = await _readJson('settings.json');
    if (j != null) return AppSettings.fromJson(j);
    final s = AppSettings(deviceId: newId(), language: defaultLanguage ?? 'en');
    await saveSettings(s);
    return s;
  }

  Future<void> saveSettings(AppSettings s) =>
      _writeJson('settings.json', s.toJson());

  Future<FamilyData> loadFamily() async {
    final j = await _readJson('family.json');
    return j == null ? const FamilyData() : FamilyData.fromJson(j);
  }

  Future<void> saveFamily(FamilyData f) =>
      _writeJson('family.json', f.toJson());

  File _usageFile(DateTime day) =>
      File('${_usageDir.path}/${dayToJson(day)}.jsonl');

  /// Usage recorded from [since] (a day) up to now.
  Future<List<UsageSegment>> loadUsage({required DateTime since}) =>
      _readDays(_usageDir, since);

  Directory get _importedDir => Directory('${dir.path}/imported');

  /// Usage imported from Android's own history, from [since]. Used for
  /// statistics only, never by the rules.
  Future<List<UsageSegment>> loadImported({required DateTime since}) =>
      _readDays(_importedDir, since);

  /// Stores imported usage, one file per day (replacing earlier imports).
  Future<void> saveImported(List<UsageSegment> segments) async {
    await _importedDir.create(recursive: true);
    final byDay = <DateTime, List<UsageSegment>>{};
    for (final seg in segments.expand(splitByDay)) {
      byDay.putIfAbsent(dayOf(seg.start), () => []).add(seg);
    }
    for (final e in byDay.entries) {
      final f = File('${_importedDir.path}/${dayToJson(e.key)}.jsonl');
      await f.writeAsString(
        e.value.map((s) => '${jsonEncode(usageSegmentToJson(s))}\n').join(),
        flush: true,
      );
    }
  }

  Future<List<UsageSegment>> _readDays(Directory dir, DateTime since) async {
    final result = <UsageSegment>[];
    final today = dayOf(DateTime.now());
    for (var day = dayOf(since); !day.isAfter(today); day = addDays(day, 1)) {
      final f = File('${dir.path}/${dayToJson(day)}.jsonl');
      if (!await f.exists()) continue;
      for (final line in await f.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          result.add(usageSegmentFromJson(jsonDecode(line) as Json));
        } on Object {
          // A line cut short by a crash is skipped.
        }
      }
    }
    return result;
  }

  /// Appends a closed segment to the file of the day it starts on.
  Future<void> appendUsage(UsageSegment s) async {
    await _usageDir.create(recursive: true);
    await _usageFile(s.start).writeAsString(
      '${jsonEncode(usageSegmentToJson(s))}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<OpenSegment?> loadOpen() async {
    final j = await _readJson('open.json');
    return j == null ? null : OpenSegment.fromJson(j);
  }

  Future<void> saveOpen(OpenSegment s) => _writeJson('open.json', s.toJson());

  Future<void> clearOpen() async {
    final f = _file('open.json');
    if (await f.exists()) await f.delete();
  }
}

/// Splits a segment at each midnight it crosses.
Iterable<UsageSegment> splitByDay(UsageSegment s) sync* {
  var from = s.start;
  while (s.end.isAfter(from)) {
    final midnight = addDays(dayOf(from), 1);
    final to = s.end.isAfter(midnight) ? midnight : s.end;
    yield s.injectedTarget != null
        ? UsageSegment.injected(
            childId: s.childId,
            injectedTarget: s.injectedTarget!,
            start: from,
            end: to,
          )
        : UsageSegment.device(
            childId: s.childId,
            deviceId: s.deviceId!,
            appId: s.appId!,
            start: from,
            end: to,
          );
    from = to;
  }
}
