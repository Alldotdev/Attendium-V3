import '../../core/result/result.dart';
import '../../core/errors/failures.dart';
import '../entities/extraction_row.dart';
import '../entities/import_job.dart';

/// Contract for document import job management and human verification rows.
abstract class ImportRepository {
  Future<Result<ImportJobEntity, Failure>> createImportJob(ImportJobEntity job);
  Future<Result<ImportJobEntity?, Failure>> getImportJobByHash(String fileHash);
  Future<Result<ImportJobEntity?, Failure>> getImportJobById(String jobId);
  Future<Result<void, Failure>> updateImportJob(ImportJobEntity job);

  Future<Result<List<ExtractionRowEntity>, Failure>> getExtractionRows(String importJobId);
  Future<Result<void, Failure>> saveExtractionRows(List<ExtractionRowEntity> rows);
  Future<Result<void, Failure>> updateExtractionRow(ExtractionRowEntity row);
}
