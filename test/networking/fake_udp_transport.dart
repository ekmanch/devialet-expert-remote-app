import 'dart:async';
import 'dart:typed_data';

import 'package:devialet_expert_remote_app/networking/udp_transport.dart';

class SentPair {
  SentPair(this.first, this.second, this.host, this.port);
  final Uint8List first;
  final Uint8List second;
  final String host;
  final int port;
}

/// Records every [sendTwice] call and lets tests push synthetic incoming
/// datagrams through [emitIncoming] without a real socket.
class FakeUdpTransport implements UdpTransport {
  final List<SentPair> sentPairs = [];
  final StreamController<Uint8List> _incoming = StreamController<Uint8List>.broadcast();
  bool closed = false;

  @override
  Future<void> sendTwice(Uint8List first, Uint8List second, String host, int port) async {
    sentPairs.add(SentPair(first, second, host, port));
  }

  @override
  Stream<Uint8List> bindAndListen(int port) => _incoming.stream;

  void emitIncoming(Uint8List data) => _incoming.add(data);

  @override
  void close() {
    closed = true;
  }
}
