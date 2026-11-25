import 'dart:io';

import 'package:Kelivo/core/services/network/public_fetch_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final uri = Uri.parse('http://fixture.example/');
  final public = InternetAddress('8.8.8.8');

  for (final mixed in [true, false]) {
    test(
      mixed ? 'rejects mixed DNS answers' : 'dials the validated IP',
      () async {
        final peers = <Object>[];
        var lookups = 0;
        await IOOverrides.runZoned(
          () async {
            Future<void> connect() async {
              final task = await connectPublicFetch(
                uri,
                () {},
                lookup: (_) async {
                  lookups++;
                  return [public, if (mixed) InternetAddress.loopbackIPv4];
                },
              );
              await task.socket;
            }

            await expectLater(connect(), throwsA(isA<SocketException>()));
          },
          socketStartConnect:
              (peer, port, {sourceAddress, sourcePort = 0}) async {
                peers.add(peer);
                throw const SocketException(
                  'Recorded without opening a socket',
                );
              },
        );
        expect(lookups, 1);
        expect(peers, mixed ? isEmpty : [same(public)]);
      },
    );
  }
}
