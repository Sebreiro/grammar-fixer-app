import 'dart:async';

/// Wraps a stream so that cancelling a subscription to it can be made to
/// reject on demand.
///
/// Port fakes need this because a `StreamController` cannot express it: a
/// broadcast controller runs its `onCancel` callback guarded and sends a
/// throw to the zone as an *uncaught* error rather than to the future
/// `cancel()` returned, so the one thing under test — a controller's
/// `dispose()` surviving a rejected subscription cancel (AD-4) — is
/// unreachable through the controller's own hooks.
///
/// [errorOf] is read at cancel time, so a test can arm and disarm it around
/// the call.
final class CancelFailingStream<T> extends StreamView<T> {
  CancelFailingStream(super.stream, this.errorOf);

  final Object? Function() errorOf;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _CancelFailingSubscription<T>(
      super.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      ),
      errorOf,
    );
  }
}

/// Delegates everything to the real subscription except [cancel], which
/// rejects while the fake is armed. The inner subscription is deliberately
/// left live in that case: a teardown that failed did not happen.
final class _CancelFailingSubscription<T> implements StreamSubscription<T> {
  _CancelFailingSubscription(this._inner, this._errorOf);

  final StreamSubscription<T> _inner;
  final Object? Function() _errorOf;

  @override
  Future<void> cancel() {
    final error = _errorOf();
    if (error != null) {
      return Future<void>.error(error);
    }
    return _inner.cancel();
  }

  @override
  void onData(void Function(T data)? handleData) => _inner.onData(handleData);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();

  @override
  bool get isPaused => _inner.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);
}
