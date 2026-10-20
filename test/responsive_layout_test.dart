import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_language/responsive_layout.dart';

void main() {
  for (final width in [360.0, 768.0, 1920.0]) {
    testWidgets('Menu stays compact at width $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Size? viewport;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppViewport(child: child!),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                viewport = MediaQuery.sizeOf(context);
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    ResponsiveMenuGrid(
                      columnCount: 2,
                      children: List.generate(
                        3,
                        (index) => ColoredBox(
                          key: ValueKey('tile-$index'),
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(
                      key: ValueKey('following-section'),
                      height: 140,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      final first = tester.getRect(find.byKey(const ValueKey('tile-0')));
      final second = tester.getRect(find.byKey(const ValueKey('tile-1')));
      final third = tester.getRect(find.byKey(const ValueKey('tile-2')));
      expect(viewport!.width, width > 1000 ? 1000 : width);
      expect(second.left - first.right, closeTo(18, 0.01));
      expect(first.height, lessThanOrEqualTo(200));
      expect(third.top - first.bottom, closeTo(18, 0.01));
      final backdrop = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(AppViewport),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(tester.getSize(find.byWidget(backdrop)).width, width);
      final gradient =
          (backdrop.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors, [Colors.white, const Color(0xFF39D2C0)]);
      expect(
        tester.getRect(find.byKey(const ValueKey('following-section'))).bottom,
        lessThan(900),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
