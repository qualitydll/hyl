import 'dart:async';

Future<T> awaitWithTimeout<T>(
  Future<T> operation, {
  required Duration timeout,
  required String description,
}) {
  return operation.timeout(
    timeout,
    onTimeout: () => throw TimeoutException(
      '$description timed out after ${timeout.inSeconds} seconds.',
      timeout,
    ),
  );
}
