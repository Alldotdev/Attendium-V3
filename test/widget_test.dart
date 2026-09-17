import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendium/infrastructure/database/app_database.dart';
import 'package:attendium/presentation/providers/database_providers.dart';
import 'package:attendium/presentation/shell/app_shell.dart';
import 'package:attendium/main.dart';

void main() {
  testWidgets('Attendium App Launches into AppShell', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final db = AppDatabase.inMemory();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
        child: const AttendiumApp(),
      ),
    );

    // Initial frame
    await tester.pump();

    // Verify AppShell elements render
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('Attendium'), findsOneWidget);
    expect(find.text('Academic Edition'), findsOneWidget);

    db.close();
  });
}
