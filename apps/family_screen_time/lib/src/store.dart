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

import 'family.dart' show usageHistoryDays;
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

  /// A parent's device: it shows and changes the family's settings, and
  /// limits nothing itself.
  final bool parentDevice;

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
    this.parentDevice = false,
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
    bool? parentDevice,
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
    parentDevice: parentDevice ?? this.parentDevice,
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
    if (parentDevice) 'parentDevice': true,
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
    parentDevice: j['parentDevice'] as bool? ?? false,
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

  /// Breaks to look into the distance, on by default.
  final EyeBreakPolicy eyeBreak;

  const Child({
    required this.id,
    required this.name,
    this.presets = defaultPresets,
    this.volumeHeadphones,
    this.volumeSpeaker,
    this.eyeBreak = const EyeBreakPolicy(),
  });

  Child withPresets(List<int> presets) => Child(
    id: id,
    name: name,
    presets: presets,
    volumeHeadphones: volumeHeadphones,
    volumeSpeaker: volumeSpeaker,
    eyeBreak: eyeBreak,
  );

  /// The same child with new volume caps (`null`: no cap).
  Child withVolume({int? headphones, int? speaker}) => Child(
    id: id,
    name: name,
    presets: presets,
    volumeHeadphones: headphones,
    volumeSpeaker: speaker,
    eyeBreak: eyeBreak,
  );

  /// The same child with new eye-break settings.
  Child withEyeBreak(EyeBreakPolicy policy) => Child(
    id: id,
    name: name,
    presets: presets,
    volumeHeadphones: volumeHeadphones,
    volumeSpeaker: volumeSpeaker,
    eyeBreak: policy,
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'presets': presets,
    'volumeHeadphones': ?volumeHeadphones,
    'volumeSpeaker': ?volumeSpeaker,
    'eyeBreak': eyeBreak.toJson(),
  };

  factory Child.fromJson(Json j) => Child(
    id: j['id'] as String,
    name: j['name'] as String,
    presets: j['presets'] == null
        ? defaultPresets
        : [for (final m in j['presets'] as List<Object?>) (m as num).toInt()],
    volumeHeadphones: (j['volumeHeadphones'] as num?)?.toInt(),
    volumeSpeaker: (j['volumeSpeaker'] as num?)?.toInt(),
    eyeBreak: j['eyeBreak'] == null
        ? const EyeBreakPolicy()
        : EyeBreakPolicy.fromJson(j['eyeBreak'] as Json),
  );
}

/// Family data: children, configuration, rules and modifiers (not usage).
class FamilyData {
  final List<Child> children;
  final FamilyConfig config;
  final FamilyState state;

  /// Display names of the app groups, by group id.
  final Map<String, String> groupNames;

  /// The child each group of apps belongs to, by group id: every child has
  /// their own groups, edited in their settings (see [ownGroups]).
  final Map<String, String> groupOwners;

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

  /// Days the use of apps is kept on each device, for the statistics; 0:
  /// for good. The rules look at [usageHistoryDays] at most.
  final int usageKeptDays;

  const FamilyData({
    this.children = const [],
    this.config = const FamilyConfig(),
    this.state = const FamilyState(),
    this.groupNames = const {},
    this.groupOwners = const {},
    this.appNames = const {},
    this.graceReminderMinutes = 1,
    this.injected = const [],
    this.selfLimitLog = const [],
    this.outOfTime = OutOfTime.settings,
    this.settingsParentOnly = false,
    this.usageKeptDays = defaultUsageKeptDays,
  });

  FamilyData copyWith({
    List<Child>? children,
    FamilyConfig? config,
    FamilyState? state,
    Map<String, String>? groupNames,
    Map<String, String>? groupOwners,
    Map<String, String>? appNames,
    int? graceReminderMinutes,
    List<UsageSegment>? injected,
    List<SelfLimitEvent>? selfLimitLog,
    OutOfTime? outOfTime,
    bool? settingsParentOnly,
    int? usageKeptDays,
  }) => FamilyData(
    children: children ?? this.children,
    config: config ?? this.config,
    state: state ?? this.state,
    groupNames: groupNames ?? this.groupNames,
    groupOwners: groupOwners ?? this.groupOwners,
    appNames: appNames ?? this.appNames,
    graceReminderMinutes: graceReminderMinutes ?? this.graceReminderMinutes,
    injected: injected ?? this.injected,
    selfLimitLog: selfLimitLog ?? this.selfLimitLog,
    outOfTime: outOfTime ?? this.outOfTime,
    settingsParentOnly: settingsParentOnly ?? this.settingsParentOnly,
    usageKeptDays: usageKeptDays ?? this.usageKeptDays,
  );

  Child? child(String? id) {
    for (final c in children) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Every group id, named or not.
  Set<String> get groupIds => {...config.appGroups.keys, ...groupNames.keys};

  /// The groups of [childId], by id, with their names, by name.
  Map<String, String> groupsOf(String? childId) {
    final ids = [
      for (final id in groupIds)
        if (groupOwners[id] == childId) id,
    ];
    String name(String id) => groupNames[id] ?? id;
    ids.sort((a, b) => name(a).toLowerCase().compareTo(name(b).toLowerCase()));
    return {for (final id in ids) id: name(id)};
  }

  Json toJson() => {
    'children': [for (final c in children) c.toJson()],
    'config': familyConfigToJson(config),
    'state': familyStateToJson(state),
    'groupNames': groupNames,
    if (groupOwners.isNotEmpty) 'groupOwners': groupOwners,
    if (appNames.isNotEmpty) 'appNames': appNames,
    'graceReminderMinutes': graceReminderMinutes,
    if (injected.isNotEmpty)
      'injected': [for (final u in injected) usageSegmentToJson(u)],
    if (selfLimitLog.isNotEmpty)
      'selfLimitLog': [for (final e in selfLimitLog) e.toJson()],
    'outOfTime': outOfTime.name,
    if (settingsParentOnly) 'settingsParentOnly': true,
    'usageKeptDays': usageKeptDays,
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
    groupOwners: {
      for (final e in (j['groupOwners'] as Json? ?? const {}).entries)
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
    usageKeptDays:
        (j['usageKeptDays'] as num?)?.toInt() ?? defaultUsageKeptDays,
  );
}

/// Days the use of apps is kept by default (see [FamilyData.usageKeptDays]).
const defaultUsageKeptDays = 365;

/// Choices offered for [FamilyData.usageKeptDays].
const usageKeptChoices = [90, 180, 365, 730, 0];

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
    return j == null ? const FamilyData() : ownGroups(FamilyData.fromJson(j));
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

  /// Rewrites the usage held here, recorded and imported: [change] gives
  /// each segment as it becomes, or `null` to drop it.
  Future<void> rewriteUsage(UsageSegment? Function(UsageSegment) change) async {
    for (final dir in [_usageDir, _importedDir]) {
      if (!await dir.exists()) continue;
      await for (final f in dir.list()) {
        if (f is! File || !f.path.endsWith('.jsonl')) continue;
        final out = StringBuffer();
        for (final line in await f.readAsLines()) {
          if (line.trim().isEmpty) continue;
          try {
            final seg = change(usageSegmentFromJson(jsonDecode(line) as Json));
            if (seg != null) out.writeln(jsonEncode(usageSegmentToJson(seg)));
          } on Object {
            // A line cut short by a crash is dropped.
          }
        }
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(out.toString(), flush: true);
        await tmp.rename(f.path);
      }
    }
  }

  /// The day [pruneUsage] last ran in this process, with what it kept.
  static String? _pruned;

  /// Forgets the use of apps older than [keptDays] days (0: keeps it all),
  /// recorded and imported; at most once a day.
  Future<int> pruneUsage(int keptDays, {DateTime? now}) async {
    if (keptDays <= 0) return 0;
    final today = dayOf(now ?? DateTime.now());
    final note = '${dir.path}|${dayToJson(today)}|$keptDays';
    if (_pruned == note) return 0;
    _pruned = note;
    // Never less than the rules look at.
    final days = keptDays < usageHistoryDays ? usageHistoryDays : keptDays;
    final before = '${dayToJson(addDays(today, -days))}.jsonl';
    var removed = 0;
    for (final d in [_usageDir, _importedDir]) {
      if (!await d.exists()) continue;
      await for (final f in d.list()) {
        final name = f.uri.pathSegments.last;
        if (f is! File || !name.endsWith('.jsonl')) continue;
        if (name.compareTo(before) >= 0) continue;
        try {
          await f.delete();
          removed++;
        } on Object {
          // Tried again tomorrow.
        }
      }
    }
    return removed;
  }

  /// The first day with use of apps held here, recorded or imported.
  Future<DateTime?> firstUsageDay() async {
    String? first;
    for (final d in [_usageDir, _importedDir]) {
      if (!await d.exists()) continue;
      await for (final f in d.list()) {
        final name = f.uri.pathSegments.last;
        if (f is! File || !name.endsWith('.jsonl')) continue;
        if (first == null || name.compareTo(first) < 0) first = name;
      }
    }
    if (first == null) return null;
    return DateTime.tryParse(first.substring(0, first.length - 6));
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

/// [f] with every group of apps belonging to a child. Before 0.22.1 the
/// groups were the whole family's: each child now gets their own copy of
/// each, the first child keeping its id, the others `<id>.<child>`, and
/// their rules, extra time and blocks follow their copy. The same on every
/// device, so devices that have not exchanged it yet still agree.
FamilyData ownGroups(FamilyData f) {
  final shared = [
    for (final id in f.groupIds)
      if (!f.groupOwners.containsKey(id)) id,
  ]..sort();
  if (shared.isEmpty || f.children.isEmpty) return f;
  final first = f.children.first.id;
  String copyFor(String id, String child) => child == first ? id : '$id.$child';
  final groups = {...f.config.appGroups};
  final names = {...f.groupNames};
  final owners = {...f.groupOwners};
  for (final id in shared) {
    for (final c in f.children) {
      final copy = copyFor(id, c.id);
      owners[copy] = c.id;
      if (copy == id) continue;
      if (groups.containsKey(id)) groups[copy] = {...groups[id]!};
      if (names.containsKey(id)) names[copy] = names[id]!;
    }
  }
  final sharedIds = shared.toSet();
  AppTarget retarget(AppTarget t, String child) =>
      t.kind == TargetKind.group && sharedIds.contains(t.id)
      ? AppTarget.group(copyFor(t.id!, child))
      : t;
  final s = f.state;
  final rules = [
    for (final r in s.rules)
      ruleFromJson({
        ...ruleToJson(r),
        'appTarget': appTargetToJson(retarget(r.appTarget, r.childId)),
      }),
  ];
  final childOfRule = {for (final r in s.rules) r.id: r.childId};
  return f.copyWith(
    config: f.config.copyWith(appGroups: groups),
    groupNames: names,
    groupOwners: owners,
    state: s.copyWith(
      rules: rules,
      bonuses: [
        for (final b in s.bonuses)
          b.appTarget == null
              ? b
              : bonusFromJson({
                  ...bonusToJson(b),
                  'appTarget': appTargetToJson(
                    retarget(b.appTarget!, b.childId),
                  ),
                }),
      ],
      temporaryBlocks: [
        for (final b in s.temporaryBlocks)
          temporaryBlockFromJson({
            ...temporaryBlockToJson(b),
            'appTarget': appTargetToJson(retarget(b.appTarget, b.childId)),
          }),
      ],
    ),
    injected: [
      for (final u in f.injected)
        u.injectedTarget == null
            ? u
            : usageSegmentFromJson({
                ...usageSegmentToJson(u),
                'injectedTarget': appTargetToJson(
                  retarget(u.injectedTarget!, u.childId),
                ),
              }),
    ],
    selfLimitLog: [
      for (final e in f.selfLimitLog)
        switch (childOfRule[e.ruleId]) {
          final child? => SelfLimitEvent.fromJson({
            ...e.toJson(),
            'target': appTargetToJson(retarget(e.target, child)),
          }),
          null => e,
        },
    ],
  );
}
