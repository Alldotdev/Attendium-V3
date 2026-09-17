import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/academic_term.dart';
import '../../domain/entities/attendance_policy.dart';
import '../../domain/entities/classroom.dart';
import '../../domain/entities/course_session.dart';
import '../../domain/entities/student.dart';
import 'database_providers.dart';

const String currentUserId = 'usr_lead';

/// All academic terms for the local user
final termsProvider = FutureProvider<List<AcademicTermEntity>>((ref) async {
  final dao = ref.watch(classroomDaoProvider);
  final result = await dao.getTerms(currentUserId);
  final terms = result.successOrNull ?? [];
  if (terms.isNotEmpty) {
    final currentSelected = ref.read(selectedTermIdProvider);
    if (currentSelected == null || !terms.any((t) => t.id == currentSelected)) {
      Future.microtask(() {
        ref.read(selectedTermIdProvider.notifier).state = terms.first.id;
      });
    }
  }
  return terms;
});

/// Currently selected academic term
final selectedTermIdProvider = StateProvider<String?>((ref) => null);

/// All classrooms for the currently selected academic term
final classroomsProvider = FutureProvider<List<ClassroomEntity>>((ref) async {
  var termId = ref.watch(selectedTermIdProvider);
  final dao = ref.watch(classroomDaoProvider);
  if (termId == null) {
    final termsRes = await dao.getTerms(currentUserId);
    final terms = termsRes.successOrNull ?? [];
    if (terms.isNotEmpty) {
      termId = terms.first.id;
    }
  }
  if (termId == null) return [];
  final result = await dao.getClassroomsForTerm(termId);
  final classrooms = result.successOrNull ?? [];
  if (classrooms.isNotEmpty) {
    final currentSelected = ref.read(selectedClassroomIdProvider);
    if (currentSelected == null || !classrooms.any((c) => c.id == currentSelected)) {
      Future.microtask(() {
        ref.read(selectedClassroomIdProvider.notifier).state = classrooms.first.id;
      });
    }
  }
  return classrooms;
});

/// Currently selected active classroom ID
final selectedClassroomIdProvider = StateProvider<String?>((ref) => null);

/// Active Classroom Entity
final activeClassroomProvider = FutureProvider<ClassroomEntity?>((ref) async {
  var classroomId = ref.watch(selectedClassroomIdProvider);
  final dao = ref.watch(classroomDaoProvider);
  if (classroomId == null) {
    final classrooms = await ref.watch(classroomsProvider.future);
    if (classrooms.isNotEmpty) {
      classroomId = classrooms.first.id;
    }
  }
  if (classroomId == null) return null;
  final result = await dao.getClassroomById(classroomId);
  return result.successOrNull;
});

/// Attendance Policy for active classroom
final activePolicyProvider = FutureProvider<AttendancePolicyEntity>((ref) async {
  var classroomId = ref.watch(selectedClassroomIdProvider);
  if (classroomId == null) {
    final classrooms = await ref.watch(classroomsProvider.future);
    if (classrooms.isNotEmpty) {
      classroomId = classrooms.first.id;
    }
  }
  if (classroomId == null) {
    return AttendancePolicyEntity(
      id: 'default',
      classroomId: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
  final dao = ref.watch(attendanceDaoProvider);
  final res = await dao.getPolicyForClassroom(classroomId);
  return res.successOrNull ?? AttendancePolicyEntity(
    id: 'default_$classroomId',
    classroomId: classroomId,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
});

/// Student roster for active classroom
final rosterProvider = FutureProvider<List<StudentEntity>>((ref) async {
  var classroomId = ref.watch(selectedClassroomIdProvider);
  if (classroomId == null) {
    final classrooms = await ref.watch(classroomsProvider.future);
    if (classrooms.isNotEmpty) {
      classroomId = classrooms.first.id;
    }
  }
  if (classroomId == null) return [];
  final dao = ref.watch(studentDaoProvider);
  final result = await dao.getStudentsForClassroom(classroomId);
  return result.successOrNull ?? [];
});

/// Sessions conducted in active classroom
final sessionsProvider = FutureProvider<List<CourseSessionEntity>>((ref) async {
  var classroomId = ref.watch(selectedClassroomIdProvider);
  if (classroomId == null) {
    final classrooms = await ref.watch(classroomsProvider.future);
    if (classrooms.isNotEmpty) {
      classroomId = classrooms.first.id;
    }
  }
  if (classroomId == null) return [];
  final dao = ref.watch(sessionDaoProvider);
  final result = await dao.getSessionsForClassroom(classroomId);
  final sessions = result.successOrNull ?? [];
  if (sessions.isNotEmpty) {
    final currentSession = ref.read(activeSessionIdProvider);
    if (currentSession == null || !sessions.any((s) => s.id == currentSession)) {
      Future.microtask(() {
        ref.read(activeSessionIdProvider.notifier).state = sessions.first.id;
      });
    }
  }
  return sessions;
});

/// Currently selected session ID for taking or editing attendance
final activeSessionIdProvider = StateProvider<String?>((ref) => null);
