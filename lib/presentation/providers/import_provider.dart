import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/attendance_record.dart';
import '../../domain/entities/extraction_row.dart';
import '../../domain/entities/import_job.dart';
import '../../domain/enums/attendance_status.dart';
import '../../domain/enums/import_status.dart';
import '../../domain/enums/match_confidence_band.dart';
import '../../domain/services/fuzzy_matcher.dart';
import '../../infrastructure/document/document_hasher.dart';
import 'database_providers.dart';

class ImportState {
  final ImportJobEntity? currentJob;
  final List<ExtractionRowEntity> rows;
  final bool isProcessing;
  final String? errorMessage;
  final String? duplicateWarning;
  final Uint8List? documentBytes;
  final String? filename;

  const ImportState({
    this.currentJob,
    this.rows = const [],
    this.isProcessing = false,
    this.errorMessage,
    this.duplicateWarning,
    this.documentBytes,
    this.filename,
  });

  ImportState copyWith({
    ImportJobEntity? currentJob,
    List<ExtractionRowEntity>? rows,
    bool? isProcessing,
    String? errorMessage,
    String? duplicateWarning,
    Uint8List? documentBytes,
    String? filename,
  }) {
    return ImportState(
      currentJob: currentJob ?? this.currentJob,
      rows: rows ?? this.rows,
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: errorMessage,
      duplicateWarning: duplicateWarning,
      documentBytes: documentBytes ?? this.documentBytes,
      filename: filename ?? this.filename,
    );
  }

  int get matchedCount => rows.where((r) => r.reviewState == RowReviewState.matched).length;
  int get reviewRequiredCount => rows.where((r) => r.reviewState == RowReviewState.reviewRequired).length;
  int get unmatchedCount => rows.where((r) => r.reviewState == RowReviewState.unmatched).length;
  int get rejectedCount => rows.where((r) => r.reviewState == RowReviewState.rejected).length;
}

class ImportNotifier extends StateNotifier<ImportState> {
  final Ref ref;

  ImportNotifier(this.ref) : super(const ImportState());

  /// Ingests a document, checks duplicates, runs AI / tabular extraction, and fuzzy matches against roster.
  Future<void> ingestDocument({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required String classroomId,
  }) async {
    state = state.copyWith(isProcessing: true, errorMessage: null, duplicateWarning: null);

    try {
      final importDao = ref.read(importDaoProvider);
      final studentDao = ref.read(studentDaoProvider);
      final ai = ref.read(activeAiProvider);

      // 1. Check duplicate via SHA-256 hash (Section 46)
      final hash = DocumentHasher.hashBytes(bytes);
      final existingJobRes = await importDao.getImportJobByHash(hash);
      String? duplicateWarn;
      if (existingJobRes.successOrNull != null) {
        final prev = existingJobRes.successOrNull!;
        duplicateWarn = 'Warning: This document was already imported on ${prev.createdAt.toIso8601String().split('T')[0]}.';
      }

      // 2. Fetch classroom roster for fuzzy matching
      final rosterRes = await studentDao.getStudentsForClassroom(classroomId);
      final roster = rosterRes.successOrNull ?? [];

      final candidates = <StudentMatchCandidate>[];
      for (final s in roster) {
        final aliasesRes = await studentDao.getAliasesForStudent(s.id);
        final aliases = (aliasesRes.successOrNull ?? []).map((a) => a.alias).toList();
        candidates.add(StudentMatchCandidate(
          id: s.id,
          rollNumber: s.rollNumber,
          fullName: s.fullName,
          normalizedName: s.normalizedName,
          aliases: aliases,
          isEnrolledInClassroom: true,
        ));
      }

      // 3. Run AI or Tabular Extraction
      final aiRes = await ai.extractAttendance(documentBytes: bytes, mimeType: mimeType);
      if (aiRes.isFailure) {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: aiRes.errorOrNull?.message ?? 'Extraction failed',
        );
        return;
      }

      final payload = aiRes.successOrNull!;
      final now = DateTime.now();
      final jobId = 'job_${now.millisecondsSinceEpoch}';

      final job = ImportJobEntity(
        id: jobId,
        classroomId: classroomId,
        filename: filename,
        mimeType: mimeType,
        fileHash: hash,
        sourceType: mimeType.split('/').last,
        processingStatus: ImportJobStatus.reviewReady,
        rawExtractionJson: payload.rawResponseJson,
        createdAt: now,
        updatedAt: now,
      );

      await importDao.createImportJob(job);

      // 4. Deterministic Fuzzy Matching (Section 15 & 47)
      const matcher = FuzzyMatcher();
      final extractionRows = <ExtractionRowEntity>[];

      for (final extracted in payload.rows) {
        final matches = matcher.match(
          rawRoll: extracted.rawRoll,
          rawName: extracted.rawName,
          candidates: candidates,
        );

        MatchResult? bestMatch = matches.isNotEmpty ? matches.first : null;
        RowReviewState reviewState;
        String? matchedStudentId;
        double matchScore = 0.0;

        if (bestMatch != null && bestMatch.band == MatchConfidenceBand.autoAccept) {
          reviewState = RowReviewState.matched;
          matchedStudentId = bestMatch.candidate?.id;
          matchScore = bestMatch.finalScore;
        } else if (bestMatch != null && bestMatch.isMatched) {
          reviewState = RowReviewState.reviewRequired;
          matchedStudentId = bestMatch.candidate?.id;
          matchScore = bestMatch.finalScore;
        } else {
          reviewState = RowReviewState.unmatched;
          matchScore = bestMatch?.finalScore ?? 0.0;
        }

        final rowId = '${jobId}_row_${extracted.rowIndex}';
        extractionRows.add(ExtractionRowEntity(
          id: rowId,
          importJobId: jobId,
          rowIndex: extracted.rowIndex,
          rawRoll: extracted.rawRoll,
          rawName: extracted.rawName,
          rawAttendance: extracted.rawAttendance,
          normalizedRoll: extracted.rawRoll?.replaceAll(RegExp(r'[\s\-_]'), '').toUpperCase(),
          normalizedName: extracted.rawName?.toLowerCase().trim(),
          matchedStudentId: matchedStudentId,
          matchScore: matchScore,
          aiConfidence: extracted.visualConfidence,
          reviewState: reviewState,
          evidenceJson: extracted.evidence,
          sourceRegion: extracted.sourceRegion,
          createdAt: now,
          updatedAt: now,
        ));
      }

      await importDao.saveExtractionRows(extractionRows);

      state = ImportState(
        currentJob: job,
        rows: extractionRows,
        isProcessing: false,
        duplicateWarning: duplicateWarn,
        documentBytes: bytes,
        filename: filename,
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Import error: $e',
      );
    }
  }

  /// Bulk approves all safe matches (Score >= 0.95)
  void bulkApproveSafe() {
    final updatedRows = <ExtractionRowEntity>[];
    for (final r in state.rows) {
      if (r.reviewState == RowReviewState.reviewRequired && r.matchScore >= 0.95 && r.matchedStudentId != null) {
        updatedRows.add(r.copyWith(reviewState: RowReviewState.matched));
      } else {
        updatedRows.add(r);
      }
    }
    state = state.copyWith(rows: updatedRows);
    final importDao = ref.read(importDaoProvider);
    importDao.saveExtractionRows(updatedRows);
  }

  /// Updates decision or matched student for an individual row
  void updateRowDecision({
    required String rowId,
    required RowReviewState newState,
    String? assignedStudentId,
    String? attendanceStatus,
  }) {
    final updatedRows = <ExtractionRowEntity>[];
    for (final r in state.rows) {
      if (r.id == rowId) {
        final updated = r.copyWith(
          reviewState: newState,
          matchedStudentId: assignedStudentId ?? r.matchedStudentId,
          rawAttendance: attendanceStatus ?? r.rawAttendance,
        );
        updatedRows.add(updated);
      } else {
        updatedRows.add(r);
      }
    }
    state = state.copyWith(rows: updatedRows);
    final importDao = ref.read(importDaoProvider);
    importDao.saveExtractionRows(updatedRows);
  }

  /// Commits verified rows to attendance records transactionally in SQLite
  Future<bool> commitToAttendance({
    required String sessionId,
    required String classroomId,
  }) async {
    if (state.currentJob == null) return false;

    state = state.copyWith(isProcessing: true);
    final attendanceDao = ref.read(attendanceDaoProvider);
    final importDao = ref.read(importDaoProvider);

    final records = <AttendanceRecordEntity>[];
    final now = DateTime.now();

    for (final r in state.rows) {
      if (r.reviewState == RowReviewState.matched && r.matchedStudentId != null) {
        final status = AttendanceStatus.fromString(r.rawAttendance);
        records.add(AttendanceRecordEntity(
          id: '${sessionId}_${r.matchedStudentId}',
          sessionId: sessionId,
          studentId: r.matchedStudentId!,
          status: status,
          source: 'ai_import',
          confidenceScore: r.matchScore,
          notes: 'Ingested from ${state.filename} (Row ${r.rowIndex})',
          createdAt: now,
          updatedAt: now,
        ));
      }
    }

    final res = await attendanceDao.recordBatchAttendance(
      sessionId: sessionId,
      records: records,
      source: 'ai_import',
    );

    if (res.isSuccess) {
      // Mark job as committed
      final updatedJob = state.currentJob!.copyWith(processingStatus: ImportJobStatus.committed);
      await importDao.updateImportJob(updatedJob);

      // Update rows to COMMITTED
      final committedRows = state.rows.map((r) {
        if (r.reviewState == RowReviewState.matched) {
          return r.copyWith(reviewState: RowReviewState.committed);
        }
        return r;
      }).toList();

      await importDao.saveExtractionRows(committedRows);

      state = state.copyWith(
        isProcessing: false,
        currentJob: updatedJob,
        rows: committedRows,
      );
      return true;
    } else {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: res.errorOrNull?.message ?? 'Commit failed',
      );
      return false;
    }
  }
}

final importProvider = StateNotifierProvider<ImportNotifier, ImportState>((ref) {
  return ImportNotifier(ref);
});
