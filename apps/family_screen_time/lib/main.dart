import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/monitor.dart';
import 'src/store.dart';

/// Entry point of the interface.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FamilyScreenTimeApp());
}

/// Entry point of the monitor, started by the Android foreground service in
/// a Flutter engine without interface.
@pragma('vm:entry-point')
Future<void> monitorMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final monitor = Monitor(await LocalStore.open());
  await monitor.start();
}
