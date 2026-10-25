import 'package:family_screen_time/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('screens end above the navigation bar, keyboard included', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late MediaQueryData inner;
    Future<void> show({double keyboard = 0}) => tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          viewPadding: const EdgeInsets.only(top: 24, bottom: 48),
          padding: EdgeInsets.only(top: 24, bottom: keyboard > 0 ? 0 : 48),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: MaterialApp(
          home: const SizedBox.expand(),
          builder: (context, child) => SystemBarsInset(
            child: Builder(
              builder: (context) {
                inner = MediaQuery.of(context);
                return child!;
              },
            ),
          ),
        ),
      ),
    );
    await show();
    // The status bar stays the app bar's; the bottom is taken care of.
    expect(inner.padding, const EdgeInsets.only(top: 24));
    expect(inner.viewPadding, const EdgeInsets.only(top: 24));
    expect(tester.getBottomLeft(find.byType(SizedBox).last).dy, 800 - 48);
    await show(keyboard: 300);
    expect(inner.viewInsets.bottom, 300 - 48);
  });
}
