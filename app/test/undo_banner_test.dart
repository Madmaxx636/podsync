import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podsync/core/library.dart';
import 'package:podsync/ui/common.dart';

void main() {
  testWidgets('the "Up Next cleared / Undo" banner goes away by itself', (
    tester,
  ) async {
    final lib = Library();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showQueueUndo(context, lib, 'Up Next cleared'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Up Next cleared'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('Up Next cleared'), findsNothing);
  });
}
