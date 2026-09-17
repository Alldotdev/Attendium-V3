import '../../core/result/result.dart';
import '../../core/errors/failures.dart';
import '../entities/academic_term.dart';
import '../entities/classroom.dart';

/// Contract for academic terms and classroom management.
abstract class ClassroomRepository {
  Future<Result<List<AcademicTermEntity>, Failure>> getTerms(String userId);
  Future<Result<AcademicTermEntity, Failure>> createTerm(AcademicTermEntity term);
  Future<Result<void, Failure>> updateTerm(AcademicTermEntity term);
  Future<Result<void, Failure>> deleteTerm(String termId);

  Future<Result<List<ClassroomEntity>, Failure>> getClassroomsForTerm(String termId);
  Future<Result<ClassroomEntity?, Failure>> getClassroomById(String classroomId);
  Future<Result<ClassroomEntity, Failure>> createClassroom(ClassroomEntity classroom);
  Future<Result<void, Failure>> updateClassroom(ClassroomEntity classroom);
  Future<Result<void, Failure>> deleteClassroom(String classroomId);
}
