import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../infrastructure/ai/ai_provider.dart';
import '../../infrastructure/ai/claude_provider.dart';
import '../../infrastructure/ai/deterministic_local_provider.dart';
import '../../infrastructure/ai/gemini_provider.dart';
import '../../infrastructure/ai/openai_provider.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/daos/attendance_dao.dart';
import '../../infrastructure/database/daos/audit_dao.dart';
import '../../infrastructure/database/daos/backup_dao.dart';
import '../../infrastructure/database/daos/classroom_dao.dart';
import '../../infrastructure/database/daos/import_dao.dart';
import '../../infrastructure/database/daos/session_dao.dart';
import '../../infrastructure/database/daos/student_dao.dart';

/// AppDatabase provider (overridden in main.dart with initialized persistent database).
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be initialized in main');
});

final classroomDaoProvider = Provider<ClassroomDao>((ref) {
  final db = ref.watch(databaseProvider);
  return ClassroomDao(db);
});

final studentDaoProvider = Provider<StudentDao>((ref) {
  final db = ref.watch(databaseProvider);
  return StudentDao(db);
});

final sessionDaoProvider = Provider<SessionDao>((ref) {
  final db = ref.watch(databaseProvider);
  return SessionDao(db);
});

final auditDaoProvider = Provider<AuditDao>((ref) {
  final db = ref.watch(databaseProvider);
  return AuditDao(db);
});

final attendanceDaoProvider = Provider<AttendanceDao>((ref) {
  final db = ref.watch(databaseProvider);
  final audit = ref.watch(auditDaoProvider);
  return AttendanceDao(db, audit);
});

final importDaoProvider = Provider<ImportDao>((ref) {
  final db = ref.watch(databaseProvider);
  return ImportDao(db);
});

final backupDaoProvider = Provider<BackupDao>((ref) {
  final db = ref.watch(databaseProvider);
  return BackupDao(db);
});

/// Settings state for AI Provider configuration
class AiSettingsState {
  final String providerType; // 'gemini', 'claude', 'openai', 'custom', 'deterministic_local'
  final String geminiApiKey;
  final String geminiModel;
  final String claudeApiKey;
  final String claudeModel;
  final String openaiApiKey;
  final String openaiModel;
  final String customBaseUrl;
  final String customApiKey;
  final String customModel;

  const AiSettingsState({
    this.providerType = 'gemini',
    this.geminiApiKey = '',
    this.geminiModel = 'auto',
    this.claudeApiKey = '',
    this.claudeModel = 'claude-3-5-sonnet-20241022',
    this.openaiApiKey = '',
    this.openaiModel = 'gpt-4o',
    this.customBaseUrl = 'https://openrouter.ai/api/v1',
    this.customApiKey = '',
    this.customModel = 'google/gemini-2.5-flash',
  });

  AiSettingsState copyWith({
    String? providerType,
    String? geminiApiKey,
    String? geminiModel,
    String? claudeApiKey,
    String? claudeModel,
    String? openaiApiKey,
    String? openaiModel,
    String? customBaseUrl,
    String? customApiKey,
    String? customModel,
  }) {
    return AiSettingsState(
      providerType: providerType ?? this.providerType,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      geminiModel: geminiModel ?? this.geminiModel,
      claudeApiKey: claudeApiKey ?? this.claudeApiKey,
      claudeModel: claudeModel ?? this.claudeModel,
      openaiApiKey: openaiApiKey ?? this.openaiApiKey,
      openaiModel: openaiModel ?? this.openaiModel,
      customBaseUrl: customBaseUrl ?? this.customBaseUrl,
      customApiKey: customApiKey ?? this.customApiKey,
      customModel: customModel ?? this.customModel,
    );
  }

  Map<String, dynamic> toJson() => {
    'providerType': providerType,
    'geminiApiKey': geminiApiKey,
    'geminiModel': geminiModel,
    'claudeApiKey': claudeApiKey,
    'claudeModel': claudeModel,
    'openaiApiKey': openaiApiKey,
    'openaiModel': openaiModel,
    'customBaseUrl': customBaseUrl,
    'customApiKey': customApiKey,
    'customModel': customModel,
  };

  factory AiSettingsState.fromJson(Map<String, dynamic> json) => AiSettingsState(
    providerType: json['providerType'] as String? ?? 'gemini',
    geminiApiKey: json['geminiApiKey'] as String? ?? '',
    geminiModel: json['geminiModel'] as String? ?? 'auto',
    claudeApiKey: json['claudeApiKey'] as String? ?? '',
    claudeModel: json['claudeModel'] as String? ?? 'claude-3-5-sonnet-20241022',
    openaiApiKey: json['openaiApiKey'] as String? ?? '',
    openaiModel: json['openaiModel'] as String? ?? 'gpt-4o',
    customBaseUrl: json['customBaseUrl'] as String? ?? 'https://openrouter.ai/api/v1',
    customApiKey: json['customApiKey'] as String? ?? '',
    customModel: json['customModel'] as String? ?? 'google/gemini-2.5-flash',
  );
}

class AiSettingsNotifier extends StateNotifier<AiSettingsState> {
  AiSettingsNotifier() : super(const AiSettingsState()) {
    _loadFromDisk();
  }

  Future<File?> _getSettingsFile() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docDir.path, 'Attendium'));
      if (!await dir.exists()) await dir.create(recursive: true);
      return File(p.join(dir.path, 'ai_settings.json'));
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final file = await _getSettingsFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        state = AiSettingsState.fromJson(json);
      }
    } catch (_) {}
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _getSettingsFile();
      if (file != null) {
        await file.writeAsString(jsonEncode(state.toJson()));
      }
    } catch (_) {}
  }

  void updateSettings({
    String? providerType,
    String? geminiApiKey,
    String? geminiModel,
    String? claudeApiKey,
    String? claudeModel,
    String? openaiApiKey,
    String? openaiModel,
    String? customBaseUrl,
    String? customApiKey,
    String? customModel,
  }) {
    state = state.copyWith(
      providerType: providerType,
      geminiApiKey: geminiApiKey,
      geminiModel: geminiModel,
      claudeApiKey: claudeApiKey,
      claudeModel: claudeModel,
      openaiApiKey: openaiApiKey,
      openaiModel: openaiModel,
      customBaseUrl: customBaseUrl,
      customApiKey: customApiKey,
      customModel: customModel,
    );
    _saveToDisk();
  }

  void setProvider(String provider) {
    state = state.copyWith(providerType: provider);
    _saveToDisk();
  }

  void setGeminiKey(String key) {
    state = state.copyWith(geminiApiKey: key);
    _saveToDisk();
  }

  void setClaudeKey(String key) {
    state = state.copyWith(claudeApiKey: key);
    _saveToDisk();
  }

  void setOpenAiKey(String key) {
    state = state.copyWith(openaiApiKey: key);
    _saveToDisk();
  }

  void setCustomConfig({required String baseUrl, required String apiKey, required String model}) {
    state = state.copyWith(
      customBaseUrl: baseUrl,
      customApiKey: apiKey,
      customModel: model,
    );
    _saveToDisk();
  }
}

final aiSettingsProvider = StateNotifierProvider<AiSettingsNotifier, AiSettingsState>((ref) {
  return AiSettingsNotifier();
});

final activeAiProvider = Provider<AiProvider>((ref) {
  final settings = ref.watch(aiSettingsProvider);
  switch (settings.providerType) {
    case 'gemini':
      return GeminiProvider(
        apiKey: settings.geminiApiKey,
        modelName: settings.geminiModel,
      );
    case 'claude':
      return ClaudeProvider(
        apiKey: settings.claudeApiKey,
        modelName: settings.claudeModel,
      );
    case 'openai':
      return OpenAiProvider(
        apiKey: settings.openaiApiKey,
        modelName: settings.openaiModel,
      );
    case 'custom':
      return OpenAiProvider(
        apiKey: settings.customApiKey,
        modelName: settings.customModel,
        baseUrl: settings.customBaseUrl,
        providerName: 'custom',
      );
    case 'deterministic_local':
    default:
      return DeterministicLocalProvider();
  }
});
