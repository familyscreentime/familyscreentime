/// The use of apps written out for other software: CSV (spreadsheets,
/// statistics tools) or ActivityWatch's import format.
library;

import 'dart:convert';

import 'package:screentime_engine/screentime_engine.dart';

/// Names used in an export.
class ExportNames {
  final String Function(String childId) child;
  final String Function(String deviceId) device;
  final String Function(String package) app;

  const ExportNames({
    required this.child,
    required this.device,
    required this.app,
  });
}

/// The segments of [history] to export: those of [children] (all when
/// `null`) within [from] to [to], clipped to it; time entered by hand
/// and apps in [exclude] (system components) left out. Oldest first.
List<UsageSegment> exportedSegments(
  List<UsageSegment> history, {
  Set<String>? children,
  DateTime? from,
  DateTime? to,
  Set<String> exclude = const {},
}) {
  final out = <UsageSegment>[];
  for (final s in history) {
    if (s.isInjected || s.appId == null || exclude.contains(s.appId)) continue;
    if (children != null && !children.contains(s.childId)) continue;
    final part = s.clip(
      from ?? DateTime.fromMillisecondsSinceEpoch(0),
      to ?? DateTime(9999),
    );
    if (part != null && part.end.isAfter(part.start)) {
      out.add(withTimes(s, part.start, part.end));
    }
  }
  return out..sort((a, b) => a.start.compareTo(b.start));
}

/// Device segment [s] from [start] to [end].
UsageSegment withTimes(UsageSegment s, DateTime start, DateTime end) =>
    UsageSegment.device(
      childId: s.childId,
      deviceId: s.deviceId ?? '',
      appId: s.appId!,
      start: start,
      end: end,
    );

/// [t] in ISO 8601 local time with its offset (`2026-10-24T15:04:05+02:00`).
String isoLocal(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = t.toLocal();
  final o = l.timeZoneOffset;
  final sign = o.isNegative ? '-' : '+';
  final m = o.inMinutes.abs();
  return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)}'
      'T${two(l.hour)}:${two(l.minute)}:${two(l.second)}'
      '$sign${two(m ~/ 60)}:${two(m % 60)}';
}

String _csvField(String v) =>
    v.contains(RegExp('[",\n\r]')) ? '"${v.replaceAll('"', '""')}"' : v;

/// One line per stretch of use: child, device, app, package, start, end
/// (local time with offset) and seconds. UTF-8 with a byte order mark, so
/// that spreadsheets read the accents.
String usageCsv(List<UsageSegment> segments, ExportNames names) {
  final b = StringBuffer('﻿child,device,app,package,start,end,seconds\r\n');
  for (final s in segments) {
    b
      ..writeAll([
        _csvField(names.child(s.childId)),
        _csvField(names.device(s.deviceId ?? '')),
        _csvField(names.app(s.appId!)),
        _csvField(s.appId!),
        isoLocal(s.start),
        isoLocal(s.end),
        s.length.inSeconds,
      ], ',')
      ..write('\r\n');
  }
  return b.toString();
}

/// A name usable in an ActivityWatch bucket id.
String _slug(String s) {
  final slug = s
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'device' : slug;
}

/// What ActivityWatch imports (Raw Data › Import, or `POST /api/0/import`):
/// `{"buckets": {id: bucket}}`, one bucket per device, of type
/// `currentwindow`, whose events say the app (`app`, `title`), its
/// `package` and the `child`.
String activityWatchJson(
  List<UsageSegment> segments,
  ExportNames names, {
  DateTime? created,
}) {
  final byDevice = <String, List<UsageSegment>>{};
  for (final s in segments) {
    byDevice.putIfAbsent(s.deviceId ?? '', () => []).add(s);
  }
  final ids = <String>{};
  final buckets = <String, Object?>{};
  for (final e in byDevice.entries) {
    final host = names.device(e.key);
    var id = 'aw-watcher-familyscreentime_${_slug(host)}';
    // Two devices of the same name.
    if (!ids.add(id)) {
      final tail = _slug(e.key);
      id = '${id}_${tail.length > 6 ? tail.substring(0, 6) : tail}';
      ids.add(id);
    }
    buckets[id] = {
      'id': id,
      'created': (created ?? e.value.first.start).toUtc().toIso8601String(),
      'type': 'currentwindow',
      'client': 'family-screen-time',
      'hostname': host,
      'data': const <String, Object?>{},
      'events': [
        for (final s in e.value)
          {
            'timestamp': s.start.toUtc().toIso8601String(),
            'duration': s.length.inMilliseconds / 1000,
            'data': {
              'app': names.app(s.appId!),
              'title': names.app(s.appId!),
              'package': s.appId,
              'child': names.child(s.childId),
            },
          },
      ],
    };
  }
  return const JsonEncoder.withIndent(' ').convert({'buckets': buckets});
}
