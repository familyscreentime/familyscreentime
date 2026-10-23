/// Frames over WebSockets (dart:io), for the local network.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'session.dart';

/// Path the sync server answers on.
const syncPath = '/fst/v1';

class WebSocketFrameChannel implements FrameChannel {
  final WebSocket socket;

  WebSocketFrameChannel(this.socket);

  @override
  Stream<List<int>> get frames =>
      socket.where((m) => m is List<int>).map((m) => m as List<int>);

  @override
  void send(List<int> frame) => socket.add(Uint8List.fromList(frame));

  @override
  Future<void> close() => socket.close();
}

/// Listens for devices on [port] (0: any free port); [onChannel] gets each
/// connection.
Future<HttpServer> serveFrames({
  required void Function(FrameChannel channel) onChannel,
  int port = 0,
  InternetAddress? address,
}) async {
  final server = await HttpServer.bind(
    address ?? InternetAddress.anyIPv4,
    port,
  );
  server.listen((request) async {
    if (request.uri.path != syncPath ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.pingInterval = const Duration(seconds: 20);
    onChannel(WebSocketFrameChannel(socket));
  });
  return server;
}

/// Connects to the device at [host]:[port].
Future<FrameChannel> connectFrames(String host, int port) async {
  final socket = await WebSocket.connect(
    'ws://$host:$port$syncPath',
  ).timeout(const Duration(seconds: 10));
  socket.pingInterval = const Duration(seconds: 20);
  return WebSocketFrameChannel(socket);
}
