import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  // The monitor's lines go to the diagnostic log too (see Diag.kt), and so
  // do the errors nothing caught.
  const channel = MethodChannel('org.familyscreentime/monitor');
  final print = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    print(message, wrapWidth: wrapWidth);
    if (message != null) channel.invokeMethod<void>('log', message).ignore();
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };
  final monitor = Monitor(await LocalStore.open());
  await monitor.start();
}
