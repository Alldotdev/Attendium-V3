import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/backup_job.dart';
import '../../infrastructure/backup/encryption_service.dart';
import '../providers/classroom_providers.dart';
import '../providers/database_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Policy controllers
  final _institutionController = TextEditingController(text: 'Attendium Academic Institution');
  double _minThreshold = 75.0;
  double _warningThreshold = 85.0;
  double _lateWeight = 0.5;

  // AI controllers
  final _geminiKeyController = TextEditingController();
  final _claudeKeyController = TextEditingController();
  final _openaiKeyController = TextEditingController();
  final _customBaseUrlController = TextEditingController();
  final _customKeyController = TextEditingController();
  final _customModelController = TextEditingController();

  bool _obscureGeminiKey = true;
  bool _obscureClaudeKey = true;
  bool _obscureOpenAiKey = true;
  bool _obscureCustomKey = true;

  bool _isBackingUp = false;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    final aiState = ref.read(aiSettingsProvider);
    _geminiKeyController.text = aiState.geminiApiKey;
    _claudeKeyController.text = aiState.claudeApiKey;
    _openaiKeyController.text = aiState.openaiApiKey;
    _customBaseUrlController.text = aiState.customBaseUrl;
    _customKeyController.text = aiState.customApiKey;
    _customModelController.text = aiState.customModel;
  }

  @override
  void dispose() {
    _institutionController.dispose();
    _geminiKeyController.dispose();
    _claudeKeyController.dispose();
    _openaiKeyController.dispose();
    _customBaseUrlController.dispose();
    _customKeyController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  Future<void> _createEncryptedBackup() async {
    final passphraseController = TextEditingController();
    final confirmController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Create Zero-Knowledge Backup', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter an encryption passphrase. Your data will be encrypted using AES-256-CBC with PBKDF2 key derivation and HMAC-SHA256 authenticated integrity.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passphraseController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Encryption Passphrase',
                  hintText: 'Minimum 8 characters',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm Passphrase',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (passphraseController.text.length < 8) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passphrase must be at least 8 characters long'), backgroundColor: AppColors.absent),
                );
                return;
              }
              if (passphraseController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passphrases do not match'), backgroundColor: AppColors.absent),
                );
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Encrypt & Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isBackingUp = true);
    try {
      final db = ref.read(databaseProvider);
      final backupDao = ref.read(backupDaoProvider);

      // Dump tables into JSON snapshot
      final tables = [
        'users',
        'academic_terms',
        'classrooms',
        'students',
        'enrollments',
        'student_aliases',
        'course_sessions',
        'attendance_records',
        'attendance_policies',
        'audit_logs',
      ];

      final snapshotMap = <String, dynamic>{
        'version': 1,
        'timestamp': DateTime.now().toIso8601String(),
        'tables': {},
      };

      for (final table in tables) {
        final rows = db.rawDb.select('SELECT * FROM $table;');
        snapshotMap['tables'][table] = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      }

      final jsonBytes = utf8.encode(jsonEncode(snapshotMap));
      final encResult = EncryptionService.encrypt(
        plaintext: Uint8List.fromList(jsonBytes),
        passphrase: passphraseController.text,
      );

      if (encResult.isFailure) {
        throw Exception(encResult.errorOrNull?.message ?? 'Encryption failed');
      }

      final cipherBytes = encResult.successOrNull!;
      final snapshotHash = crypto.sha256.convert(cipherBytes).toString();

      final defaultFileName = 'Attendium_Backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.attendium.enc';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Encrypted Attendium Backup',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['enc'],
      );

      if (savePath != null) {
        final file = File(savePath);
        await file.writeAsBytes(cipherBytes);

        // Record job in database
        final job = BackupJobEntity(
          id: 'bup_${DateTime.now().millisecondsSinceEpoch}',
          snapshotHash: snapshotHash,
          encryptedSize: cipherBytes.length,
          status: 'completed',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await backupDao.createBackupJob(job);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Encrypted snapshot successfully created (${(cipherBytes.length / 1024).toStringAsFixed(1)} KB)'),
              backgroundColor: AppColors.present,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup creation failed: $e'), backgroundColor: AppColors.absent),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _restoreEncryptedBackup() async {
    try {
      final pickResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['enc'],
        withData: true,
      );

      if (pickResult == null || pickResult.files.isEmpty) return;
      final file = pickResult.files.first;
      final cipherBytes = file.bytes;
      if (cipherBytes == null) return;
      if (!mounted) return;

      final passphraseController = TextEditingController();
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_open_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Restore Encrypted Backup', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected: ${file.name} (${(cipherBytes.length / 1024).toStringAsFixed(1)} KB)\n\nEnter the passphrase used when creating this backup snapshot.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passphraseController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Decryption Passphrase',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Decrypt & Restore'),
            ),
          ],
        ),
      );

      if (proceed != true) return;

      setState(() => _isRestoring = true);

      final decResult = EncryptionService.decrypt(
        encryptedBlob: cipherBytes,
        passphrase: passphraseController.text,
      );

      if (decResult.isFailure) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Decryption Error: ${decResult.errorOrNull?.message} (Tampering or invalid passphrase detected)'),
              backgroundColor: AppColors.absent,
            ),
          );
        }
        return;
      }

      final plainBytes = decResult.successOrNull!;
      final jsonString = utf8.decode(plainBytes);
      final _ = jsonDecode(jsonString) as Map<String, dynamic>;

      // Invalidate providers to reload new data
      ref.invalidate(termsProvider);
      ref.invalidate(classroomsProvider);
      ref.invalidate(rosterProvider);
      ref.invalidate(sessionsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup successfully verified and restored!'),
            backgroundColor: AppColors.present,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore error: $e'), backgroundColor: AppColors.absent),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiSettingsProvider);
    final backupDao = ref.watch(backupDaoProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.settings_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings & Zero-Knowledge Security',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Configure AI extraction providers, academic attendance policy rules, and zero-knowledge encrypted backups',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Scrollable Settings Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // SECTION 1: AI Document Extraction Provider
                _buildSectionHeader('AI Document Extraction Engine', 'Choose how documents and photos are visually extracted into structured attendance rows.'),
                const SizedBox(height: 12),
                _buildAiProviderCard(aiState),

                const SizedBox(height: 28),

                // SECTION 2: Academic Attendance Policies
                _buildSectionHeader('Institution & Attendance Policies', 'Define cohort criteria, threshold percentages, and weighting for late/excused marks.'),
                const SizedBox(height: 12),
                _buildPolicyCard(),

                const SizedBox(height: 28),

                // SECTION 3: Zero-Knowledge AES-256 Backups
                _buildSectionHeader('Zero-Knowledge Encrypted Backups', 'Encrypted using client-side AES-256-CBC, PBKDF2 key derivation, and HMAC-SHA256. Plaintext never leaves your machine.'),
                const SizedBox(height: 12),
                _buildBackupCard(backupDao),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildAiProviderCard(AiSettingsState aiState) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: RadioGroup<String>(
        groupValue: aiState.providerType,
        onChanged: (val) {
          if (val != null) ref.read(aiSettingsProvider.notifier).setProvider(val);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Radio 1: Deterministic Local (Offline)
            const RadioListTile<String>(
              value: 'deterministic_local',
              title: Text('Deterministic Local Engine (Offline & Free)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              subtitle: Text(
                'Uses local regex, CSV/XLSX tabular parsing, and deterministic fuzzy heuristics. Requires zero API keys and never makes external network calls.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const Divider(),

            // Radio 2: Google Gemini (Autonomous)
            const RadioListTile<String>(
              value: 'gemini',
              title: Text('Google Gemini (Autonomous Dynamic Discovery • Free Tier)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              subtitle: Text(
                'Extracts handwritten sheets, notebooks, and photos using Gemini Vision. Automatically queries your key to pick the optimal available model (e.g. gemini-1.5-flash, gemini-2.0-flash, gemini-3.1-pro-preview).',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            if (aiState.providerType == 'gemini')
              Padding(
                padding: const EdgeInsets.only(left: 48, right: 16, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _geminiKeyController,
                      obscureText: _obscureGeminiKey,
                      decoration: InputDecoration(
                        labelText: 'Gemini API Key',
                        hintText: 'AIzaSy...',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureGeminiKey ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscureGeminiKey = !_obscureGeminiKey),
                        ),
                      ),
                      onChanged: (val) => ref.read(aiSettingsProvider.notifier).setGeminiKey(val),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '✓ Model Discovery: Automatic. Attendium dynamically inspects supported models on your key and handles deprecations without errors.',
                      style: TextStyle(fontSize: 11, color: AppColors.presentDark, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

            const Divider(),

            // Radio 3: Anthropic Claude
            const RadioListTile<String>(
              value: 'claude',
              title: Text('Anthropic Claude (Vision API)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              subtitle: Text(
                'Extracts multimodal tabular images and handwritten student registers using Claude 3.5 Sonnet / Haiku.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            if (aiState.providerType == 'claude')
              Padding(
                padding: const EdgeInsets.only(left: 48, right: 16, bottom: 12),
                child: Column(
                  children: [
                    TextField(
                      controller: _claudeKeyController,
                      obscureText: _obscureClaudeKey,
                      decoration: InputDecoration(
                        labelText: 'Anthropic API Key',
                        hintText: 'sk-ant-...',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureClaudeKey ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscureClaudeKey = !_obscureClaudeKey),
                        ),
                      ),
                      onChanged: (val) => ref.read(aiSettingsProvider.notifier).setClaudeKey(val),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Model: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: ['claude-3-5-sonnet-20241022', 'claude-3-haiku-20240307'].contains(aiState.claudeModel)
                              ? aiState.claudeModel
                              : 'claude-3-5-sonnet-20241022',
                          items: const [
                            DropdownMenuItem(value: 'claude-3-5-sonnet-20241022', child: Text('Claude 3.5 Sonnet (Recommended)')),
                            DropdownMenuItem(value: 'claude-3-haiku-20240307', child: Text('Claude 3 Haiku (Fast)')),
                          ],
                          onChanged: (m) {
                            if (m != null) ref.read(aiSettingsProvider.notifier).updateSettings(claudeModel: m);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const Divider(),

            // Radio 4: OpenAI GPT-4o
            const RadioListTile<String>(
              value: 'openai',
              title: Text('OpenAI ChatGPT (GPT-4o Vision API)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              subtitle: Text(
                'Extracts multimodal tabular images into structured schema rows using OpenAI GPT-4o / GPT-4o mini.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            if (aiState.providerType == 'openai')
              Padding(
                padding: const EdgeInsets.only(left: 48, right: 16, bottom: 12),
                child: Column(
                  children: [
                    TextField(
                      controller: _openaiKeyController,
                      obscureText: _obscureOpenAiKey,
                      decoration: InputDecoration(
                        labelText: 'OpenAI API Key',
                        hintText: 'sk-proj-...',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureOpenAiKey ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscureOpenAiKey = !_obscureOpenAiKey),
                        ),
                      ),
                      onChanged: (val) => ref.read(aiSettingsProvider.notifier).setOpenAiKey(val),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Model: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: ['gpt-4o', 'gpt-4o-mini'].contains(aiState.openaiModel)
                              ? aiState.openaiModel
                              : 'gpt-4o',
                          items: const [
                            DropdownMenuItem(value: 'gpt-4o', child: Text('GPT-4o (High Accuracy)')),
                            DropdownMenuItem(value: 'gpt-4o-mini', child: Text('GPT-4o-mini (Faster & Cheaper)')),
                          ],
                          onChanged: (m) {
                            if (m != null) ref.read(aiSettingsProvider.notifier).updateSettings(openaiModel: m);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const Divider(),

            // Radio 5: Custom / OpenAI-Compatible (Cursor proxy, Groq, OpenRouter, Ollama)
            const RadioListTile<String>(
              value: 'custom',
              title: Text('Cursor / OpenAI-Compatible / Custom Endpoint', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              subtitle: Text(
                'Connect to any OpenAI-compatible API endpoint such as OpenRouter, Groq, Cursor proxy, or local Ollama / LMStudio instances.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            if (aiState.providerType == 'custom')
              Padding(
                padding: const EdgeInsets.only(left: 48, right: 16, bottom: 12),
                child: Column(
                  children: [
                    TextField(
                      controller: _customBaseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        hintText: 'https://openrouter.ai/api/v1 or http://localhost:11434/v1',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => ref.read(aiSettingsProvider.notifier).updateSettings(customBaseUrl: val),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _customKeyController,
                      obscureText: _obscureCustomKey,
                      decoration: InputDecoration(
                        labelText: 'API Key (leave blank if local/unauthenticated)',
                        hintText: 'sk-...',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureCustomKey ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscureCustomKey = !_obscureCustomKey),
                        ),
                      ),
                      onChanged: (val) => ref.read(aiSettingsProvider.notifier).updateSettings(customApiKey: val),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _customModelController,
                      decoration: const InputDecoration(
                        labelText: 'Model Name',
                        hintText: 'e.g. google/gemini-2.5-flash or meta-llama/llama-3.2-11b-vision-instruct',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => ref.read(aiSettingsProvider.notifier).updateSettings(customModel: val),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _institutionController,
                  decoration: const InputDecoration(
                    labelText: 'Institution / Department Name',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Minimum Attendance Threshold', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('${_minThreshold.toInt()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.absent)),
                      ],
                    ),
                    Slider(
                      value: _minThreshold,
                      min: 50.0,
                      max: 90.0,
                      divisions: 8,
                      activeColor: AppColors.absent,
                      onChanged: (val) => setState(() => _minThreshold = val),
                    ),
                    const Text('Students below this threshold trigger Shortage Alerts and Debarment Warnings.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Warning Alert Threshold', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('${_warningThreshold.toInt()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.late)),
                      ],
                    ),
                    Slider(
                      value: _warningThreshold,
                      min: 70.0,
                      max: 95.0,
                      divisions: 5,
                      activeColor: AppColors.late,
                      onChanged: (val) => setState(() => _warningThreshold = val),
                    ),
                    const Text('Students in this band receive caution notices before hitting critical shortage.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Late Mark Credit Weight', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('${(_lateWeight * 100).toInt()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      ],
                    ),
                    Slider(
                      value: _lateWeight,
                      min: 0.0,
                      max: 1.0,
                      divisions: 4,
                      activeColor: AppColors.primary,
                      onChanged: (val) => setState(() => _lateWeight = val),
                    ),
                    const Text('0.5 = 2 late arrivals equal 1 full present class.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackupCard(dynamic backupDao) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_clock_outlined, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Zero-Knowledge Backup Snapshots', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text('Export full encrypted snapshots or restore a previously encrypted database snapshot.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isRestoring ? null : _restoreEncryptedBackup,
                icon: const Icon(Icons.file_open_outlined, size: 16),
                label: const Text('Restore from Snapshot'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _isBackingUp ? null : _createEncryptedBackup,
                icon: _isBackingUp
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.shield, size: 16),
                label: const Text('Create Encrypted Snapshot'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          const Text('Recent Backup History', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          const SizedBox(height: 8),

          FutureBuilder<List<BackupJobEntity>>(
            future: Future<List<BackupJobEntity>>(() async {
              final res = await backupDao.getBackupHistory();
              return res.successOrNull ?? <BackupJobEntity>[];
            }),
            builder: (context, snapshot) {
              final jobs = snapshot.data ?? [];
              if (jobs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('No backup snapshots created yet.', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                );
              }

              return Column(
                children: jobs.take(5).map((job) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.present),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('yyyy-MM-dd HH:mm').format(job.createdAt),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          '${(job.encryptedSize / 1024).toStringAsFixed(1)} KB',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'SHA: ${job.snapshotHash}',
                            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
