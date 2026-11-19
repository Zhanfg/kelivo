import 'dart:io';

import 'package:Kelivo/core/services/jobs/executors/http_download_executor.dart';
import 'package:Kelivo/core/services/jobs/job_record.dart';
import 'package:flutter_test/flutter_test.dart';

JobRecord _record(String id) {
  final now = DateTime.utc(2026, 11, 20);
  return JobRecord(
    jobId: 'job_${id.padLeft(8, '0')}',
    kind: 'http_download',
    ownerId: 'owner:test',
    state: JobState.queued,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late HttpServer server;
  late Directory directory;
  late HttpDownloadJobAdapter adapter;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    directory = await Directory.systemTemp.createTemp('w08_');
    adapter = HttpDownloadJobAdapter();
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  Uri endpoint(String path) =>
      Uri.parse('http://127.0.0.1:${server.port}$path');

  test('downloads real bytes and returns opaque artifact handle', () async {
    server.listen((request) async {
      request.response.headers.contentLength = 5;
      request.response.write('hello');
      await request.response.close();
    });
    final target = File('${directory.path}/payload.bin');
    final accepted = await adapter.start(
      record: _record('1'),
      url: endpoint('/file'),
      destination: target,
      artifactId: 'artifact:download1',
    );
    expect(accepted.state, JobState.queued);
    await adapter.settle(accepted.jobId);
    expect(adapter.status(accepted.jobId)?.state, JobState.completed);
    expect(adapter.status(accepted.jobId)?.resultRef, 'artifact:download1');
    expect(adapter.progress(accepted.jobId)?.receivedBytes, 5);
    expect(adapter.progress(accepted.jobId)?.totalBytes, 5);
    expect(await target.readAsString(), 'hello');
    expect(adapter.list(ownerId: 'owner:test'), hasLength(1));
  });

  test('HTTP error fails without a partial artifact', () async {
    server.listen((request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    final target = File('${directory.path}/missing.bin');
    final accepted = await adapter.start(
      record: _record('2'),
      url: endpoint('/missing'),
      destination: target,
      artifactId: 'artifact:download2',
    );
    await adapter.settle(accepted.jobId);
    expect(adapter.status(accepted.jobId)?.state, JobState.failed);
    expect(adapter.status(accepted.jobId)?.errorCode, 'download_failed');
    expect(await target.exists(), isFalse);
    expect(
      await File('${target.path}.part.${accepted.jobId}').exists(),
      isFalse,
    );
  });

  test('cancellation prevents publication of an artifact', () async {
    server.listen((request) async {
      request.response.write('first');
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        request.response.write('second');
        await request.response.close();
      } catch (_) {}
    });
    final target = File('${directory.path}/cancel.bin');
    final accepted = await adapter.start(
      record: _record('3'),
      url: endpoint('/slow'),
      destination: target,
      artifactId: 'artifact:download3',
    );
    final cancelled = await adapter.cancel(accepted.jobId);
    expect(cancelled.state, JobState.cancelled);
    expect(await adapter.cancel(accepted.jobId), same(cancelled));
    await adapter.settle(accepted.jobId);
    expect(adapter.status(accepted.jobId)?.state, JobState.cancelled);
    expect(await target.exists(), isFalse);
  });

  test('invalid schemes and embedded credentials are rejected', () async {
    for (final url in [
      Uri.parse('file:///tmp/unsafe'),
      Uri.parse('http://user:password@localhost/file'),
    ]) {
      await expectLater(
        adapter.start(
          record: _record('4'),
          url: url,
          destination: File('${directory.path}/bad.bin'),
          artifactId: 'artifact:bad',
        ),
        throwsArgumentError,
      );
    }
    expect(adapter.list(), isEmpty);
  });

  test('existing output is never overwritten', () async {
    final target = File('${directory.path}/exists.bin');
    await target.writeAsString('original');
    await expectLater(
      adapter.start(
        record: _record('5'),
        url: endpoint('/unused'),
        destination: target,
        artifactId: 'artifact:download5',
      ),
      throwsStateError,
    );
    expect(await target.readAsString(), 'original');
    expect(adapter.list(), isEmpty);
  });
}
