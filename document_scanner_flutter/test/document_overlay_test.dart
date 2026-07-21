import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders and lets a corner handle move in normalized coordinates',
    (WidgetTester tester) async {
      List<ScannerPoint>? changed;
      const List<ScannerPoint> corners = <ScannerPoint>[
        ScannerPoint(.1, .1),
        ScannerPoint(.9, .1),
        ScannerPoint(.9, .9),
        ScannerPoint(.1, .9),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: DocumentOverlay(
                corners: corners,
                sourceSize: const Size(100, 200),
                onCornersChanged: (List<ScannerPoint> value) => changed = value,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);

      final Offset overlayOrigin = tester.getTopLeft(
        find.byType(DocumentOverlay),
      );
      await tester.dragFrom(
        overlayOrigin + const Offset(70, 40),
        const Offset(20, 20),
      );
      await tester.pump();
      expect(changed, isNotNull);
      expect(changed!.first.x, closeTo(.2, .03));
      expect(changed!.first.y, closeTo(.15, .03));
    },
  );
}
