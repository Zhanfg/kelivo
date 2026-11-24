import 'dart:async';
import 'dart:io';

import 'package:Kelivo/core/services/network/public_fetch_request.dart';

// The fetch evidence supplies its own closed network via HttpOverrides.
// Let it dial its reserved names without resolving them on the host OS.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  const hosts = {
    'source.test',
    'child.source.test',
    'public.test',
    'other.test',
  };
  PublicFetchRequest.fixtureClient = (uri) =>
      uri.isScheme('http') &&
          hosts.contains(uri.host) &&
          HttpOverrides.current != Zone.root.run(() => HttpOverrides.current)
      ? HttpClient()
      : null;
  await testMain();
}
