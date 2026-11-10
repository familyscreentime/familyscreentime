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
  /// Loads the settings and the family: from this device's storage, or
  /// the demonstration's made-up family.
  final Future<AppController> Function() load;

  const FamilyScreenTimeApp({super.key, this.load = AppController.load});

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
    widget.load().then((c) {
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
      builder: (context, _) {
        // Parent mode on a child's device: nothing is limited here, so the
        // whole interface changes colour and says so.
        final parentHere =
            controller.parentMode && !controller.settings.parentDevice;
        final seed = parentHere ? parentModeColor : appColor;
        return MaterialApp(
          title: 'Family Screen Time',
          navigatorKey: controller.navigatorKey,
          theme: ThemeData(colorSchemeSeed: seed),
          darkTheme: ThemeData(
            colorSchemeSeed: seed,
            brightness: Brightness.dark,
          ),
          locale: Locale(controller.s.language),
          supportedLocales: [for (final l in supportedLanguages) Locale(l)],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          // Every touch keeps parent mode open.
          builder: (context, child) => Listener(
            onPointerDown: (_) => controller.touch(),
            child: SystemBarsInset(
              child: parentHere
                  ? ParentModeFrame(controller: controller, child: child!)
                  : child!,
            ),
          ),
          home: !controller.settings.setupDone
              ? SetupFlow(controller: controller)
              : controller.settings.parentDevice
              ? ParentDeviceHome(controller: controller)
              : ChildHome(controller: controller),
        );
      },
    );
  }
}

/// The interface's colour.
const appColor = Color(0xFF3A5BA0);

/// Its colour in parent mode on a child's device.
const parentModeColor = Color(0xFFC25A16);

/// Parent mode on a child's device: a band above every screen says that
/// nothing is limited, with the way out.
class ParentModeFrame extends StatelessWidget {
  final AppController controller;
  final Widget child;

  const ParentModeFrame({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Material(
          color: scheme.primary,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.lock_open, color: scheme.onPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      controller.s.t('parentModeBanner'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onPrimary,
                    ),
                    onPressed: controller.leaveParentMode,
                    child: Text(controller.s.t('parentModeLeave')),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
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
