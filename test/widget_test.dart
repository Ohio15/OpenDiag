// Basic Flutter widget test for OpenDiag

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_diag/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: OpenDiagApp()));

    // Verify that the app starts and shows the title
    expect(find.text('OpenDiag'), findsOneWidget);
  });
}
