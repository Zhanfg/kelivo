import 'dart:io';

import 'package:Kelivo/core/services/network/public_fetch_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic origin backed exclusively by this test's listener.
Uri mountFetchFixture(int port) {
  final origin = Uri(scheme: 'http', host: 'fixture.test', port: port);
  final previous = PublicFetchRequest.fixtureClient;
  PublicFetchRequest.fixtureClient = (uri) {
    if (uri.origin != origin.origin) return previous?.call(uri);
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (_, _, _) =>
        Socket.startConnect(InternetAddress.loopbackIPv4, port);
    return client;
  };
  addTearDown(() => PublicFetchRequest.fixtureClient = previous);
  return origin;
}
