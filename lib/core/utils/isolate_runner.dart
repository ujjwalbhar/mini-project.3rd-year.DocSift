import 'dart:async';
import 'dart:isolate';

/// A generic message sent from the spawned isolate back to the main thread.
class IsolateMessage<T> {
  const IsolateMessage({this.result, this.progress, this.error});

  /// The final result when the task completes.
  final T? result;

  /// Intermediate progress (0.0 – 1.0).
  final double? progress;

  /// Error message if the task failed.
  final String? error;

  bool get isProgress => progress != null;
  bool get isResult => result != null;
  bool get isError => error != null;
}

/// Payload sent INTO the spawned isolate.
class IsolatePayload<T> {
  const IsolatePayload({required this.sendPort, required this.data});

  final SendPort sendPort;
  final T data;
}

/// Runs a function in a new [Isolate] and returns a stream of
/// [IsolateMessage]s (progress updates + final result).
///
/// Usage:
/// ```dart
/// final stream = IsolateRunner.run<String, MyInput>(
///   entryPoint: _myIsolateEntry,
///   data: myInput,
/// );
/// await for (final msg in stream) {
///   if (msg.isProgress) print('${msg.progress}');
///   if (msg.isResult)   print('Done: ${msg.result}');
///   if (msg.isError)    print('Error: ${msg.error}');
/// }
/// ```
class IsolateRunner {
  static Stream<IsolateMessage<R>> run<R, D>({
    required void Function(IsolatePayload<D>) entryPoint,
    required D data,
  }) {
    final controller = StreamController<IsolateMessage<R>>();
    final receivePort = ReceivePort();

    Isolate.spawn(
      entryPoint,
      IsolatePayload<D>(sendPort: receivePort.sendPort, data: data),
    ).then((isolate) {
      receivePort.listen(
        (message) {
          if (message is IsolateMessage<R>) {
            controller.add(message);
            if (message.isResult || message.isError) {
              receivePort.close();
              controller.close();
              isolate.kill(priority: Isolate.immediate);
            }
          }
        },
        onDone: () {
          if (!controller.isClosed) controller.close();
        },
      );
    }).catchError((e) {
      controller.addError(e);
      controller.close();
    });

    return controller.stream;
  }
}
