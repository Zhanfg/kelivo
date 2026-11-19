import 'dart:async';
import 'dart:io';

import '../job_record.dart';

/// Single-connection HTTP download, isolated from the multi-threaded engine.
/// Caller is responsible for authorizing the URL and filesystem destination.
final class HttpDownloadJobAdapter {
  HttpDownloadJobAdapter({DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;
  final Map<String, JobRecord> _jobs = {};
  final Map<String, HttpClient> _clients = {};
  final Map<String, DownloadProgress> _progress = {};
  final Map<String, Future<void>> _tasks = {};

  JobRecord? status(String id) => _jobs[id];
  DownloadProgress? progress(String id) => _progress[id];
  List<JobRecord> list({String? ownerId}) => List.unmodifiable(
    _jobs.values.where((job) => ownerId == null || job.ownerId == ownerId),
  );

  /// Returns a queued receipt before transfer completion; no overwrites.
  Future<JobRecord> start({
    required JobRecord record,
    required Uri url,
    required File destination,
    required String artifactId,
  }) async {
    if (record.state != JobState.queued || record.kind != 'http_download') {
      throw ArgumentError('Expected queued http_download job');
    }
    if (!{'http', 'https'}.contains(url.scheme) ||
        url.userInfo.isNotEmpty ||
        url.host.isEmpty) {
      throw ArgumentError('Invalid HTTP(S) source');
    }
    if (!RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$').hasMatch(artifactId)) {
      throw ArgumentError('Invalid opaque artifact reference');
    }
    if (_jobs.containsKey(record.jobId)) throw StateError('Duplicate job ID');
    final partial = File('${destination.path}.part.${record.jobId}');
    if (await destination.exists() || await partial.exists()) {
      throw StateError('Refusing to overwrite an existing file');
    }
    _jobs[record.jobId] = record;
    _progress[record.jobId] = const DownloadProgress(0, null);
    _tasks[record.jobId] = _transfer(
      record,
      url,
      destination,
      partial,
      artifactId,
    );
    return record;
  }

  Future<JobRecord> cancel(String id) async {
    final current = _jobs[id];
    if (current == null) throw StateError('Unknown job');
    if (current.isTerminal) return current;
    if (current.state == JobState.outcomeUnknown) {
      throw StateError('Unknown outcome requires review');
    }
    final next = current.transition(JobState.cancelled, at: _at(current));
    _jobs[id] = next;
    _clients.remove(id)?.close(force: true);
    return next;
  }

  Future<void> settle(String id) async {
    final task = _tasks[id];
    if (task == null) throw StateError('Unknown job');
    await task;
  }

  Future<void> _transfer(
    JobRecord original,
    Uri url,
    File destination,
    File partial,
    String artifactId,
  ) async {
    final id = original.jobId;
    HttpClient? client;
    IOSink? sink;
    var committed = false;
    try {
      if (_jobs[id]?.state == JobState.cancelled) return;
      _jobs[id] = original.transition(JobState.running, at: _at(original));
      client = HttpClient();
      _clients[id] = client;
      final request = await client.getUrl(url);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP status ${response.statusCode}');
      }
      if (_jobs[id]?.state == JobState.cancelled) return;
      sink = partial.openWrite();
      final length = response.contentLength < 0 ? null : response.contentLength;
      var received = 0;
      await for (final bytes in response) {
        if (_jobs[id]?.state == JobState.cancelled) break;
        received += bytes.length;
        if (length != null && received > length) {
          throw const HttpException('Content length exceeded');
        }
        sink.add(bytes);
        _progress[id] = DownloadProgress(received, length);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (_jobs[id]?.state == JobState.cancelled) return;
      if (length != null && received != length) {
        throw const HttpException('Truncated download');
      }
      if (await destination.exists()) throw StateError('Destination exists');
      await partial.rename(destination.path);
      committed = true;
      final current = _jobs[id]!;
      if (current.state == JobState.cancelled) {
        await destination.delete();
        return;
      }
      _jobs[id] = current.transition(
        JobState.completed,
        at: _at(current),
        newResultRef: artifactId,
      );
    } catch (_) {
      final current = _jobs[id];
      if (current != null && current.state == JobState.running) {
        _jobs[id] = current.transition(
          JobState.failed,
          at: _at(current),
          newErrorCode: 'download_failed',
        );
      }
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client?.close(force: true);
      _clients.remove(id);
      if (!committed && await partial.exists()) await partial.delete();
    }
  }

  DateTime _at(JobRecord job) {
    final now = _clock().toUtc();
    return now.isBefore(job.updatedAt) ? job.updatedAt : now;
  }
}

final class DownloadProgress {
  const DownloadProgress(this.receivedBytes, this.totalBytes);
  final int receivedBytes;
  final int? totalBytes;
}
