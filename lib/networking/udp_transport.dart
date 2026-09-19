import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// One received datagram with its sender. The sender's address is what
/// keys the discovery map and decides which broadcast may touch live
/// control state (`docs/protocol.md`, "Multi-amp discovery"); it is a
/// plain string so nothing above the transport needs `dart:io`.
typedef UdpDatagram = ({Uint8List data, String senderAddress});

/// Abstraction over the UDP socket operations the protocol layer needs, so
/// [DevialetClient] can be unit-tested with a fake instead of a real socket.
abstract class UdpTransport {
  /// Sends [first] then [second] to [host]:[port] over a single socket,
  /// closed afterward. Mirrors the original app's `sendTwice()`: one
  /// `DatagramSocket` opened and closed per logical command, reused for
  /// both back-to-back sends (see `docs/protocol.md`, "Socket lifetime,
  /// commands").
  Future<void> sendTwice(Uint8List first, Uint8List second, String host, int port);

  /// Binds to [port] and returns a stream of raw datagrams with their
  /// sender address. The
  /// original app never sets a read timeout and just keeps looping on
  /// transient errors — the returned stream should behave the same way
  /// (stay open across errors) rather than closing on the first hiccup.
  Stream<UdpDatagram> bindAndListen(int port);

  /// Releases the listening socket opened by [bindAndListen], if any.
  void close();
}

/// Real `dart:io`-backed implementation. Deliberately has no Flutter
/// dependency, per CLAUDE.md's networking isolation requirement.
class DevialetUdpTransport implements UdpTransport {
  RawDatagramSocket? _listenSocket;

  @override
  Future<void> sendTwice(Uint8List first, Uint8List second, String host, int port) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      final address = InternetAddress(host);
      socket.send(first, address, port);
      socket.send(second, address, port);
    } finally {
      socket.close();
    }
  }

  @override
  Stream<UdpDatagram> bindAndListen(int port) {
    final controller = StreamController<UdpDatagram>();

    RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true)
        .then((socket) {
          _listenSocket = socket;
          socket.broadcastEnabled = true;
          socket.listen(
            (event) {
              if (event != RawSocketEvent.read) return;
              final datagram = socket.receive();
              if (datagram != null) {
                controller.add((data: datagram.data, senderAddress: datagram.address.address));
              }
              // A `null` receive() or any other transient hiccup is simply
              // ignored and the loop continues, matching the original app's
              // "receive() throws -> loop continues" behavior.
            },
            onError: controller.addError,
            onDone: controller.close,
          );
        })
        .catchError((Object error, StackTrace stackTrace) {
          // Bind/setup failure: the app loses live status but direct control
          // commands still work since they don't depend on this listener.
          controller.addError(error, stackTrace);
          controller.close();
        });

    return controller.stream;
  }

  @override
  void close() {
    _listenSocket?.close();
    _listenSocket = null;
  }
}
