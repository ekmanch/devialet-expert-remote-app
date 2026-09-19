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
  final StreamController<UdpDatagram> _incoming = StreamController<UdpDatagram>.broadcast();
  bool closed = false;

  @override
  Future<void> sendTwice(Uint8List first, Uint8List second, String host, int port) async {
    sentPairs.add(SentPair(first, second, host, port));
  }

  @override
  Stream<UdpDatagram> bindAndListen(int port) => _incoming.stream;

  /// Pushes one datagram as if received from [from] (TEST-NET-1 by default
  /// so a fixture can never name real hardware, checklist item 27).
  void emitIncoming(Uint8List data, {String from = '192.0.2.22'}) =>
      _incoming.add((data: data, senderAddress: from));

  @override
  void close() {
    closed = true;
  }
}
