import 'dart:async';
import 'dart:io';

import 'pinned_tls_socket.dart';
import 'public_internet_address.dart';

void validatePublicFetchUrl(Uri uri) {
  if (!(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty ||
      uri.port < 1 ||
      uri.port > 65535) {
    throw const FormatException('Invalid HTTP(S) fetch URL');
  }
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  final literal = InternetAddress.tryParse(host);
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      (literal != null && !isPublicInternetAddress(literal))) {
    throw const SocketException('Fetch requires a public address');
  }
}

/// Resolve once per connection. Only the validated address list can reach TCP;
/// the original URI remains authoritative for the Host header and TLS.
Future<ConnectionTask<Socket>> connectPublicFetch(
  Uri uri,
  void Function() checkActive, {
  Future<List<InternetAddress>> Function(String) lookup =
      InternetAddress.lookup,
}) async {
  checkActive();
  final literal = InternetAddress.tryParse(uri.host);
  final addresses = literal == null ? await lookup(uri.host) : [literal];
  checkActive();
  if (addresses.isEmpty || !addresses.every(isPublicInternetAddress)) {
    throw const SocketException('Fetch requires a public address');
  }

  ConnectionTask<Socket>? pending;
  var stopped = false;

  Future<Socket> connect() async {
    for (final address in addresses) {
      if (stopped) break;
      checkActive();
      try {
        final task = uri.isScheme('https')
            ? await startPinnedTlsSocket(address, uri.port, uri.host)
            : await Socket.startConnect(address, uri.port);
        pending = task;
        if (stopped) task.cancel();
        final socket = addresses.length == 1
            ? await task.socket
            : await task.socket.timeout(
                const Duration(seconds: 2),
                onTimeout: () {
                  task.socket
                      .then((lateSocket) => lateSocket.destroy())
                      .ignore();
                  task.cancel();
                  throw const SocketException('Connection timed out');
                },
              );
        if (!stopped) return socket;
        socket.destroy();
      } on IOException {
        if (address == addresses.last) rethrow;
      }
    }
    throw const SocketException('Fetch cancelled');
  }

  return ConnectionTask.fromSocket(connect(), () {
    if (stopped) return;
    stopped = true;
    pending?.cancel();
  });
}
