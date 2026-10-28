import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/monitor.dart';
import 'src/store.dart';
import 'src/strings.dart';

/// Entry point of the interface.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  S.windows = Platform.isWindows;
  runApp(const FamilyScreenTimeApp());
}

/// Entry point of the monitor, in a Flutter engine without interface:
/// started by the Android foreground service, or on Windows by
/// `FamilyScreenTime.exe --monitor` at each sign-in.
@pragma('vm:entry-point')
Future<void> monitorMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  S.windows = Platform.isWindows;
  DartPluginRegistrant.ensureInitialized();
  final monitor = Monitor(await LocalStore.open());
  await monitor.start();
}
