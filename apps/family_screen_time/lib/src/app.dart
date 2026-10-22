/// Root of the interface.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controller.dart';
import 'platform.dart';
import 'strings.dart';
import 'ui/child_home.dart';
import 'ui/setup.dart';

class FamilyScreenTimeApp extends StatefulWidget {
  const FamilyScreenTimeApp({super.key});

  @override
  State<FamilyScreenTimeApp> createState() => _FamilyScreenTimeAppState();
}

class _FamilyScreenTimeAppState extends State<FamilyScreenTimeApp> {
  AppController? _controller;

  @override
  void initState() {
    super.initState();
    AppController.load().then((c) {
      // "Leave parent mode" from the notification.
      PlatformApi.listen(onLeaveParentMode: c.leaveParentMode);
      setState(() => _controller = c);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => MaterialApp(
        title: 'Family Screen Time',
        navigatorKey: controller.navigatorKey,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF3A5BA0)),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF3A5BA0),
          brightness: Brightness.dark,
        ),
        locale: Locale(controller.s.language),
        supportedLocales: [for (final l in supportedLanguages) Locale(l)],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // Every touch keeps parent mode open.
        builder: (context, child) =>
            Listener(onPointerDown: (_) => controller.touch(), child: child),
        home: controller.settings.setupDone
            ? ChildHome(controller: controller)
            : SetupFlow(controller: controller),
      ),
    );
  }
}
