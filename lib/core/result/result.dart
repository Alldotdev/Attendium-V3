/// Result monad for deterministic, robust error handling without throwing exceptions.
sealed class Result<S, F> {
  const Result();

  bool get isSuccess => this is Success<S, F>;
  bool get isFailure => this is Err<S, F>;
  bool get isError => this is Err<S, F>;

  S? get successOrNull => isSuccess ? (this as Success<S, F>).data : null;
  F? get errorOrNull => isFailure ? (this as Err<S, F>).error : null;
  F? get failureOrNull => errorOrNull;

  R fold<R>(R Function(S data) onSuccess, R Function(F error) onFailure) {
    if (this is Success<S, F>) {
      return onSuccess((this as Success<S, F>).data);
    } else {
      return onFailure((this as Err<S, F>).error);
    }
  }

  Result<R, F> map<R>(R Function(S data) transform) {
    if (this is Success<S, F>) {
      return Success(transform((this as Success<S, F>).data));
    }
    return Err((this as Err<S, F>).error);
  }

  Result<S, R> mapFailure<R>(R Function(F error) transform) {
    if (this is Err<S, F>) {
      return Err(transform((this as Err<S, F>).error));
    }
    return Success((this as Success<S, F>).data);
  }
}

final class Success<S, F> extends Result<S, F> {
  final S data;
  const Success(this.data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Success<S, F> && other.data == data);

  @override
  int get hashCode => data.hashCode;

  @override
  String toString() => 'Success($data)';
}

final class Err<S, F> extends Result<S, F> {
  final F error;
  const Err(this.error);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Err<S, F> && other.error == error);

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Err($error)';
}
