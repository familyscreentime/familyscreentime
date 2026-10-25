/// Root of the interface.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controller.dart';
import 'platform.dart';
import 'strings.dart';
import 'ui/child_home.dart';
import 'ui/parent_device_home.dart';
import 'ui/setup.dart';

class FamilyScreenTimeApp extends StatefulWidget {
  const FamilyScreenTimeApp({super.key});

  @override
  State<FamilyScreenTimeApp> createState() => _FamilyScreenTimeAppState();
}

class _FamilyScreenTimeAppState extends State<FamilyScreenTimeApp>
    with WidgetsBindingObserver {
  AppController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppController.load().then((c) {
      // "Leave parent mode" from the notification.
      PlatformApi.listen(
        onLeaveParentMode: c.leaveParentMode,
        onFamilyChanged: c.reloadFamily,
      );
      setState(() => _controller = c);
    });
  }

  /// Back on screen: the relay is asked at once (the app may have slept
  /// for hours).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller?.resumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        builder: (context, child) => Listener(
          onPointerDown: (_) => controller.touch(),
          child: SystemBarsInset(child: child!),
        ),
        home: !controller.settings.setupDone
            ? SetupFlow(controller: controller)
            : controller.settings.parentDevice
            ? ParentDeviceHome(controller: controller)
            : ChildHome(controller: controller),
      ),
    );
  }
}

/// Keeps the screens clear of the navigation bar and of the sides' cutouts,
/// with the app drawn edge to edge (Android 15 and later): the screens'
/// background fills that space, and their content (lists, buttons) ends
/// above it. The status bar is the app bars' business.
class SystemBarsInset extends StatelessWidget {
  final Widget child;

  const SystemBarsInset({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final inset = EdgeInsets.fromLTRB(
      mq.viewPadding.left,
      0,
      mq.viewPadding.right,
      mq.viewPadding.bottom,
    );
    if (inset == EdgeInsets.zero) return child;
    EdgeInsets less(EdgeInsets e) => EdgeInsets.fromLTRB(
      (e.left - inset.left).clamp(0, double.infinity),
      e.top,
      (e.right - inset.right).clamp(0, double.infinity),
      (e.bottom - inset.bottom).clamp(0, double.infinity),
    );
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: inset,
        child: MediaQuery(
          data: mq.copyWith(
            padding: less(mq.padding),
            viewPadding: less(mq.viewPadding),
            // The keyboard rises from the bottom of the screen.
            viewInsets: less(mq.viewInsets),
          ),
          child: child,
        ),
      ),
    );
  }
}
