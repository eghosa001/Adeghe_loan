/// The [Failure] type hierarchy used across the data and domain layers,
/// plus [Result] — a minimal Either-style wrapper so repositories and use
/// cases can return either a success value or a typed failure instead of
/// throwing raw exceptions across architectural layers.
///
/// Low-level exceptions (SqfliteException, PlatformException,
/// FormatException, etc.) should be caught inside repositories and
/// converted into one of the concrete [Failure] subclasses below before
/// they reach the domain or presentation layers — this keeps the UI free
/// of any dependency on `sqflite`, `dart:io`, or other data-layer types.
abstract class Failure {
  final String message;
  final String? code;
  final Object? cause;

  const Failure(this.message, {this.code, this.cause});

  @override
  String toString() => code != null ? '[$code] $message' : message;

  /// Equality intentionally ignores [cause] — two failures with the same
  /// [message]/[code] are treated as equal even if they wrap different
  /// underlying exception instances. That keeps this useful for simple
  /// state comparisons and tests without requiring exceptions to
  /// implement their own equality.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          code == other.code;

  @override
  int get hashCode => Object.hash(runtimeType, message, code);
}

/// Local database (SQLite) read/write problem.
class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message, {super.code, super.cause});
}

/// User-entered data failed validation (e.g. loan amount out of range,
/// invalid phone number, duplicate customer ID).
class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.code, super.cause});
}

/// The requested record does not exist.
class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message, {super.code, super.cause});
}

// ===========================================================================
// Result type
// ===========================================================================

/// A minimal Either-style wrapper so repository and use-case methods can
/// return `Result<T>` instead of throwing. Consuming code pattern-matches
/// with [when] or checks [isSuccess] / [isFailure].
///
/// ```dart
/// Future<Result<Customer>> getCustomer(String id) async {
///   try {
///     final row = await db.getById(AppConstants.tableCustomers, id);
///     if (row == null) {
///       return Result.failure(NotFoundFailure('Customer not found'));
///     }
///     return Result.success(Customer.fromMap(row));
///   } catch (e) {
///     return Result.failure(DatabaseFailure('Failed to load customer', cause: e));
///   }
/// }
/// ```
sealed class Result<T> {
  const Result();

  const factory Result.success(T data) = Success<T>;
  const factory Result.failure(Failure failure) = ResultError<T>;

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is ResultError<T>;

  /// The success value, or `null` if this is a failure.
  T? get dataOrNull => switch (this) {
        Success<T>(data: final d) => d,
        ResultError<T>() => null,
      };

  /// The failure, or `null` if this is a success.
  Failure? get failureOrNull => switch (this) {
        Success<T>() => null,
        ResultError<T>(failure: final f) => f,
      };

  /// Pattern-matches on the result, similar to `fold` in fp packages.
  R when<R>({
    required R Function(T data) success,
    required R Function(Failure failure) failure,
  }) =>
      switch (this) {
        Success<T>(data: final d) => success(d),
        ResultError<T>(failure: final f) => failure(f),
      };

  /// Transforms the success value, leaving a failure untouched.
  Result<R> map<R>(R Function(T data) transform) => switch (this) {
        Success<T>(data: final d) => Result.success(transform(d)),
        ResultError<T>(failure: final f) => Result.failure(f),
      };
}

final class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

final class ResultError<T> extends Result<T> {
  final Failure failure;
  const ResultError(this.failure);
}
