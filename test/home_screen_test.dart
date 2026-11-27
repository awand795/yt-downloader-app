import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/main.dart';

void main() {
  testWidgets('link field accepts a pasted URL and can be cleared', (tester) async {
    await tester.pumpWidget(const TubeGrabApp());
    await tester.pump();

    expect(find.text('Belum ada unduhan'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'https://youtu.be/0wemf5SZkW4');
    await tester.pump();

    expect(find.text('https://youtu.be/0wemf5SZkW4'), findsOneWidget);
    // The paste button is replaced by a clear button once there is text.
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.text('Tempel'), findsNothing);
  });

  testWidgets('invalid link shows a hint instead of navigating', (tester) async {
    await tester.pumpWidget(const TubeGrabApp());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'bukan tautan');
    await tester.tap(find.text('Analisa tautan'));
    await tester.pump();

    expect(find.text('Tempel tautan video YouTube yang valid'), findsOneWidget);
  });
}
