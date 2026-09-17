/// Base failure class and specific application failure variants.
abstract class Failure {
  final String message;
  final String? code;
  final dynamic details;

  const Failure(this.message, {this.code, this.details});

  @override
  String toString() => 'Failure(code: $code, message: $message, details: $details)';
}

class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message, {super.code, super.details});
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.code, super.details});
}

class AiExtractionFailure extends Failure {
  const AiExtractionFailure(super.message, {super.code, super.details});
}

class MatchingFailure extends Failure {
  const MatchingFailure(super.message, {super.code, super.details});
}

class ImportFailure extends Failure {
  const ImportFailure(super.message, {super.code, super.details});
}

class ExportFailure extends Failure {
  const ExportFailure(super.message, {super.code, super.details});
}

class BackupFailure extends Failure {
  const BackupFailure(super.message, {super.code, super.details});
}

class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message, {super.code, super.details});
}
