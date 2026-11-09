import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/log.dart';
import 'src/monitor.dart';
import 'src/store.dart';
import 'src/strings.dart';

/// Entry point of the interface.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  S.windows = Platform.isWindows;
  startLog('ui');
  _logErrors();
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
  startLog('monitor');
  _logErrors();
  final monitor = Monitor(await LocalStore.open());
  await monitor.start();
}

/// Errors nothing caught go to the log too (a file on Windows), with their
/// stack, rather than only to a debugger.
void _logErrors() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint(
      'Flutter error: ${details.exceptionAsString()}\n${details.stack}',
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true;
  };
}
