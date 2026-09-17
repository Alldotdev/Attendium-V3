import '../../core/result/result.dart';
import '../../core/errors/failures.dart';
import '../entities/attendance_policy.dart';
import '../entities/attendance_record.dart';

/// Contract for attendance taking, historical editing, and policy configuration.
abstract class AttendanceRepository {
  Future<Result<List<AttendanceRecordEntity>, Failure>> getRecordsForSession(String sessionId);
  Future<Result<List<AttendanceRecordEntity>, Failure>> getRecordsForStudent(String studentId, String classroomId);
  Future<Result<List<AttendanceRecordEntity>, Failure>> getAllRecordsForClassroom(String classroomId);

  Future<Result<void, Failure>> recordBatchAttendance({
    required String sessionId,
    required List<AttendanceRecordEntity> records,
    required String source,
  });

  Future<Result<void, Failure>> updateSingleAttendanceRecord({
    required AttendanceRecordEntity updatedRecord,
    required String reason,
    required String userId,
  });

  Future<Result<AttendancePolicyEntity, Failure>> getPolicyForClassroom(String classroomId);
  Future<Result<void, Failure>> savePolicy(AttendancePolicyEntity policy);
}
