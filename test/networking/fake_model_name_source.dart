import 'dart:async';

import 'package:devialet_expert_remote_app/networking/model_name_source.dart';

/// Hand-written stand-in for the platform mDNS / Bonjour browser (mirrors
/// `FakeUdpTransport`). Tests push hits with [emit] and a terminal failure
/// with [fail]; [browseCalls] / [activeSubscriptions] pin session
/// open/close. TEST-NET addresses only (checklist 27).
class FakeModelNameSource implements ModelNameSource {
  final StreamController<ModelNameHit> _controller = StreamController<ModelNameHit>.broadcast();
  int browseCalls = 0;
  int activeSubscriptions = 0;

  /// When set, every subscription fails at once with this error.
  Object? failOnSubscribe;

  @override
  Stream<ModelNameHit> browse() {
    browseCalls++;
    late StreamController<ModelNameHit> out;
    StreamSubscription<ModelNameHit>? inner;
    out = StreamController<ModelNameHit>(
      onListen: () {
        activeSubscriptions++;
        final error = failOnSubscribe;
        if (error != null) {
          out.addError(error);
          out.close();
          return;
        }
        inner = _controller.stream.listen(out.add, onError: out.addError, onDone: out.close);
      },
      onCancel: () {
        activeSubscriptions--;
        return inner?.cancel();
      },
    );
    return out.stream;
  }

  void emit(String hostname, {String ip = '192.0.2.22'}) => _controller.add((hostname: hostname, ip: ip));

  /// The source cannot run: one error, then closed.
  void fail(Object error) {
    _controller.addError(error);
    _controller.close();
  }
}

class FakeMulticastLock implements MulticastLock {
  int acquired = 0;
  int released = 0;
  Object? failAcquire;

  @override
  Future<void> acquire() async {
    acquired++;
    final e = failAcquire;
    if (e != null) throw e;
  }

  @override
  Future<void> release() async => released++;
}
