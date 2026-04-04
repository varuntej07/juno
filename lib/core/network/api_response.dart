import '../errors/app_exception.dart';

sealed class Result<T> {
  const Result();

  const factory Result.success(T data) = Success<T>;
  const factory Result.failure(AppException error) = Failure<T>;

  R when<R>({
    required R Function(T data) success,
    required R Function(AppException error) failure,
  });

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get dataOrNull => isSuccess ? (this as Success<T>).data : null;
  AppException? get errorOrNull => isFailure ? (this as Failure<T>).error : null;
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);

  @override
  R when<R>({
    required R Function(T data) success,
    required R Function(AppException error) failure,
  }) =>
      success(data);

  @override
  String toString() => 'Success($data)';
}

class Failure<T> extends Result<T> {
  final AppException error;
  const Failure(this.error);

  @override
  R when<R>({
    required R Function(T data) success,
    required R Function(AppException error) failure,
  }) =>
      failure(error);

  @override
  String toString() => 'Failure(${error.code.name}: ${error.message})';
}
