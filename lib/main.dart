import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_constants.dart';
import 'infrastructure/database/app_database.dart';
import 'presentation/providers/database_providers.dart';
import 'presentation/shell/app_shell.dart';
import 'presentation/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize authoritative persistent SQLite database with WAL pragma
  final db = await AppDatabase.openPersistent();

  // Ensure default user profile exists without seeding any dummy data
  await _ensureDefaultUser(db);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: const AttendiumApp(),
    ),
  );
}

class AttendiumApp extends StatelessWidget {
  const AttendiumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const AppShell(),
    );
  }
}

/// Ensures local user profile exists for SQLite relational integrity without inserting any dummy or sample data.
Future<void> _ensureDefaultUser(AppDatabase db) async {
  final now = DateTime.now();
  db.rawDb.execute(
    'INSERT OR IGNORE INTO users (id, google_subject, email, display_name, institution_name, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?);',
    ['usr_lead', 'sub_lead', 'instructor@attendium.edu', 'Lead Faculty', 'Academic Institution', now.millisecondsSinceEpoch, now.millisecondsSinceEpoch],
  );
}
