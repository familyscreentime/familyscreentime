/// On Windows, a log per process: %LOCALAPPDATA%\FamilyScreenTime\logs\
/// ui.log or monitor.log, which the native side starts (and where it notes
/// a crash). Each line is written to the file at once, so that what went
/// before a crash is kept.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

String? _path;

/// Sends [debugPrint] to the log too, on Windows.
void startLog(String name) {
  if (!Platform.isWindows) return;
  final local = Platform.environment['LOCALAPPDATA'];
  if (local == null) return;
  try {
    final dir = Directory('$local\\FamilyScreenTime\\logs')
      ..createSync(recursive: true);
    _path = '${dir.path}\\$name.log';
  } on Object {
    return;
  }
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    previous(message, wrapWidth: wrapWidth);
    writeLog(message ?? '');
  };
}

/// Adds [line] to the log, with the time.
void writeLog(String line) {
  final path = _path;
  if (path == null) return;
  final time = DateTime.now().toIso8601String().substring(11, 23);
  try {
    File(path)
        .writeAsStringSync('$time $line\n', mode: FileMode.append, flush: true);
  } on Object {
    // The log never stops the app.
  }
}
