import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/attendance_record.dart';
import '../../domain/entities/student.dart';
import '../../domain/enums/attendance_status.dart';
import 'database_providers.dart';

class AttendanceGridState {
  final Map<String, AttendanceStatus> statuses;
  final int focusedIndex;
  final Set<String> selectedStudentIds;
  final List<Map<String, AttendanceStatus>> undoStack;
  final List<Map<String, AttendanceStatus>> redoStack;
  final bool isSaving;
  final bool hasUnsavedChanges;

  const AttendanceGridState({
    this.statuses = const {},
    this.focusedIndex = 0,
    this.selectedStudentIds = const {},
    this.undoStack = const [],
    this.redoStack = const [],
    this.isSaving = false,
    this.hasUnsavedChanges = false,
  });

  AttendanceGridState copyWith({
    Map<String, AttendanceStatus>? statuses,
    int? focusedIndex,
    Set<String>? selectedStudentIds,
    List<Map<String, AttendanceStatus>>? undoStack,
    List<Map<String, AttendanceStatus>>? redoStack,
    bool? isSaving,
    bool? hasUnsavedChanges,
  }) {
    return AttendanceGridState(
      statuses: statuses ?? this.statuses,
      focusedIndex: focusedIndex ?? this.focusedIndex,
      selectedStudentIds: selectedStudentIds ?? this.selectedStudentIds,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      isSaving: isSaving ?? this.isSaving,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
    );
  }

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;
}

class AttendanceGridNotifier extends StateNotifier<AttendanceGridState> {
  final Ref ref;

  AttendanceGridNotifier(this.ref) : super(const AttendanceGridState());

  /// Initializes grid for a session
  Future<void> initializeForSession({
    required String sessionId,
    required List<StudentEntity> roster,
  }) async {
    final dao = ref.read(attendanceDaoProvider);
    final recordsRes = await dao.getRecordsForSession(sessionId);
    final existingRecords = recordsRes.successOrNull ?? [];

    final statusMap = <String, AttendanceStatus>{};
    for (final s in roster) {
      statusMap[s.id] = AttendanceStatus.unmarked;
    }
    for (final r in existingRecords) {
      statusMap[r.studentId] = r.status;
    }

    state = AttendanceGridState(
      statuses: statusMap,
      focusedIndex: 0,
      selectedStudentIds: {},
      undoStack: [],
      redoStack: [],
      hasUnsavedChanges: false,
    );
  }

  void setFocusIndex(int index, int maxCount) {
    if (index >= 0 && index < maxCount) {
      state = state.copyWith(focusedIndex: index);
    }
  }

  void moveFocusUp() {
    if (state.focusedIndex > 0) {
      state = state.copyWith(focusedIndex: state.focusedIndex - 1);
    }
  }

  void moveFocusDown(int totalStudents) {
    if (state.focusedIndex < totalStudents - 1) {
      state = state.copyWith(focusedIndex: state.focusedIndex + 1);
    }
  }

  /// Sets status for currently focused student (or multi-selected students) and advances focus
  void applyStatus(AttendanceStatus newStatus, List<StudentEntity> roster) {
    if (roster.isEmpty) return;

    final targetIds = state.selectedStudentIds.isNotEmpty
        ? state.selectedStudentIds
        : {roster[state.focusedIndex].id};

    final newStatuses = Map<String, AttendanceStatus>.from(state.statuses);
    for (final id in targetIds) {
      newStatuses[id] = newStatus;
    }

    // Push previous to undo stack
    final newUndo = List<Map<String, AttendanceStatus>>.from(state.undoStack)..add(state.statuses);

    // Auto-advance focus if single student
    int nextFocus = state.focusedIndex;
    if (state.selectedStudentIds.isEmpty && state.focusedIndex < roster.length - 1) {
      nextFocus++;
    }

    state = state.copyWith(
      statuses: newStatuses,
      focusedIndex: nextFocus,
      undoStack: newUndo,
      redoStack: [], // Clear redo on new action
      hasUnsavedChanges: true,
    );
  }

  void markAll(AttendanceStatus status, List<StudentEntity> roster) {
    if (roster.isEmpty) return;
    final newStatuses = <String, AttendanceStatus>{};
    for (final s in roster) {
      newStatuses[s.id] = status;
    }
    final newUndo = List<Map<String, AttendanceStatus>>.from(state.undoStack)..add(state.statuses);

    state = state.copyWith(
      statuses: newStatuses,
      undoStack: newUndo,
      redoStack: [],
      hasUnsavedChanges: true,
    );
  }

  /// Applies batch attendance updates from document/text scan
  void applyScannedBatch(Map<String, AttendanceStatus> updates) {
    if (updates.isEmpty) return;
    final newStatuses = Map<String, AttendanceStatus>.from(state.statuses)..addAll(updates);
    final newUndo = List<Map<String, AttendanceStatus>>.from(state.undoStack)..add(state.statuses);
    state = state.copyWith(
      statuses: newStatuses,
      undoStack: newUndo,
      redoStack: [],
      hasUnsavedChanges: true,
    );
  }


  void toggleStudentSelection(String studentId) {
    final newSet = Set<String>.from(state.selectedStudentIds);
    if (newSet.contains(studentId)) {
      newSet.remove(studentId);
    } else {
      newSet.add(studentId);
    }
    state = state.copyWith(selectedStudentIds: newSet);
  }

  void clearSelection() {
    state = state.copyWith(selectedStudentIds: {});
  }

  void undo() {
    if (!state.canUndo) return;
    final newUndo = List<Map<String, AttendanceStatus>>.from(state.undoStack);
    final previous = newUndo.removeLast();
    final newRedo = List<Map<String, AttendanceStatus>>.from(state.redoStack)..add(state.statuses);

    state = state.copyWith(
      statuses: previous,
      undoStack: newUndo,
      redoStack: newRedo,
      hasUnsavedChanges: true,
    );
  }

  void redo() {
    if (!state.canRedo) return;
    final newRedo = List<Map<String, AttendanceStatus>>.from(state.redoStack);
    final next = newRedo.removeLast();
    final newUndo = List<Map<String, AttendanceStatus>>.from(state.undoStack)..add(state.statuses);

    state = state.copyWith(
      statuses: next,
      undoStack: newUndo,
      redoStack: newRedo,
      hasUnsavedChanges: true,
    );
  }

  /// Instantly and transactionally saves current state to local SQLite database
  Future<bool> commitAttendance(String sessionId) async {
    state = state.copyWith(isSaving: true);
    final dao = ref.read(attendanceDaoProvider);

    final records = <AttendanceRecordEntity>[];
    final now = DateTime.now();

    state.statuses.forEach((studentId, status) {
      records.add(AttendanceRecordEntity(
        id: '${sessionId}_$studentId',
        sessionId: sessionId,
        studentId: studentId,
        status: status,
        source: 'manual_grid',
        createdAt: now,
        updatedAt: now,
      ));
    });

    final result = await dao.recordBatchAttendance(
      sessionId: sessionId,
      records: records,
      source: 'manual_grid',
    );

    state = state.copyWith(
      isSaving: false,
      hasUnsavedChanges: result.isFailure,
    );

    return result.isSuccess;
  }
}

final attendanceGridProvider = StateNotifierProvider<AttendanceGridNotifier, AttendanceGridState>((ref) {
  return AttendanceGridNotifier(ref);
});
