import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/demo.dart';

/// Entry point of the demonstration build: a parent's device with a
/// made-up family, linked to nothing, keeping nothing.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FamilyScreenTimeApp(load: loadDemo));
}

/// The demonstration limits nothing: should Android start the monitor
/// (after a restart, say), it stops at once.
@pragma('vm:entry-point')
Future<void> monitorMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await const MethodChannel('org.familyscreentime/monitor')
      .invokeMethod<void>('unwanted');
}
