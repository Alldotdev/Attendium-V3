import '../../core/result/result.dart';
import '../../core/errors/failures.dart';
import '../entities/student.dart';
import '../entities/student_alias.dart';

/// Contract for student roster, alias, and candidate search management.
abstract class StudentRepository {
  Future<Result<List<StudentEntity>, Failure>> getStudentsForClassroom(String classroomId);
  Future<Result<StudentEntity?, Failure>> getStudentById(String studentId);
  Future<Result<StudentEntity?, Failure>> getStudentByRoll(String classroomId, String rollNumber);
  Future<Result<StudentEntity, Failure>> createStudent(StudentEntity student);
  Future<Result<void, Failure>> updateStudent(StudentEntity student);
  Future<Result<void, Failure>> enrollStudentInClassroom(String studentId, String classroomId, String rollNumber);
  Future<Result<void, Failure>> withdrawStudentFromClassroom(String studentId, String classroomId);
  Future<Result<void, Failure>> removeStudentFromClassroom(String studentId, String classroomId);
  Future<Result<void, Failure>> deleteStudent(String studentId);

  Future<Result<List<StudentAliasEntity>, Failure>> getAliasesForStudent(String studentId);
  Future<Result<StudentAliasEntity, Failure>> addAlias(String studentId, String alias, String source);
}
