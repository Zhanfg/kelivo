import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/jobs/executors/http_download_executor.dart';
import 'package:Kelivo/core/services/jobs/job_record.dart';

/// #32 integration evidence for the *current* single-connection adapter.
/// It deliberately does not claim HTTP Range resume is implemented.
void main() {
  late HttpServer server;
  late Directory directory;
  late HttpDownloadJobAdapter adapter;

  JobRecord queued(String suffix) {
    final now = DateTime.utc(2026, 11, 21);
    return JobRecord(
      jobId: 'job_resume_$suffix',
      kind: 'http_download',
      ownerId: 'owner:test',
      state: JobState.queued,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    directory = await Directory.systemTemp.createTemp('wave12_download_');
    adapter = HttpDownloadJobAdapter();
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });
  Uri endpoint(String path) =>
      Uri.parse('http://127.0.0.1:${server.port}$path');

  test('HTTP 200 writes exact bytes and atomically publishes result', () async {
    final bytes = List<int>.generate(256, (i) => i);
    server.listen((request) async {
      expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
      request.response.headers.contentType = ContentType.binary;
      request.response.add(bytes);
      await request.response.close();
    });
    final target = File('${directory.path}/complete.bin');
    final receipt = await adapter.start(
      record: queued('complete_1'),
      url: endpoint('/data'),
      destination: target,
      artifactId: 'artifact:one',
    );
    expect(receipt.state, JobState.queued);
    await adapter.settle(receipt.jobId);
    expect(adapter.status(receipt.jobId)?.state, JobState.completed);
    expect(adapter.status(receipt.jobId)?.resultRef, 'artifact:one');
    expect(await target.readAsBytes(), bytes);
    expect(directory.listSync().map((e) => e.path), [target.path]);
  });

  test(
    'HTTP 206 is rejected, not mistaken for successful Range resume',
    () async {
      server.listen((request) async {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 5-9/10',
        );
        request.response.add([5, 6, 7, 8, 9]);
        await request.response.close();
      });
      final target = File('${directory.path}/unsafe.bin');
      final receipt = await adapter.start(
        record: queued('range_1'),
        url: endpoint('/resume'),
        destination: target,
        artifactId: 'artifact:two',
      );
      await adapter.settle(receipt.jobId);
      expect(adapter.status(receipt.jobId)?.state, JobState.failed);
      expect(await target.exists(), isFalse);
      expect(directory.listSync(), isEmpty);
    },
  );

  test('rejects existing destination without starting transfer', () async {
    final target = File('${directory.path}/preserve.bin');
    await target.writeAsBytes([8, 7, 6]);
    expect(
      () => adapter.start(
        record: queued('exists_1'),
        url: endpoint('/'),
        destination: target,
        artifactId: 'artifact:three',
      ),
      throwsStateError,
    );
    expect(await target.readAsBytes(), [8, 7, 6]);
  });

  test('real interruption and partial Range recovery remain unimplemented', () {
    // Existing adapter deletes temporary files after cancellation/failure and
    // accepts only HTTP 200. This is a tracked acceptance gap, not a pass.
  }, skip: 'NOT TESTED: Range resume requires an authorized executor change');
}
