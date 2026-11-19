// ignore_for_file: deprecated_member_use
// Flutter 3.47 compatibility: retain the stable Material import until
// the shared Build/CI owner migrates the application to material_ui.
import 'package:flutter/material.dart';

import '../../../core/services/jobs/job_record.dart';

/// Read-only job details. Progress and log identifiers are caller-provided,
/// validated snapshots; the widget never reads host files or starts a job.
final class JobCenterEntry {
  JobCenterEntry({required this.record, required this.progress, this.logRef}) {
    if (!progress.isFinite || progress < 0 || progress > 1) {
      throw ArgumentError('Job progress must be between zero and one');
    }
    if (logRef != null &&
        !RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$').hasMatch(logRef!)) {
      throw ArgumentError('Log reference must be opaque');
    }
  }

  final JobRecord record;
  final double progress;
  final String? logRef;
}

final class JobCenterReadOnlyModel {
  JobCenterReadOnlyModel(Iterable<JobCenterEntry> records)
    : entries = List.unmodifiable(records) {
    if (entries.length > 5000 ||
        entries.map((entry) => entry.record.jobId).toSet().length !=
            entries.length) {
      throw ArgumentError('Duplicate or excessive job receipts');
    }
  }

  final List<JobCenterEntry> entries;

  List<JobCenterEntry> page({JobState? state, int offset = 0, int limit = 25}) {
    if (offset < 0 || limit < 1 || limit > 100) {
      throw ArgumentError('Invalid Job Center pagination');
    }
    final filtered = entries.where(
      (entry) => state == null || entry.record.state == state,
    );
    return List.unmodifiable(filtered.skip(offset).take(limit));
  }
}

/// No navigation or mutation of jobs; this page only renders snapshots.
class JobCenterPage extends StatelessWidget {
  const JobCenterPage({required this.model, super.key});

  final JobCenterReadOnlyModel model;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Job Center')),
    body: model.entries.isEmpty
        ? const Center(child: Text('No jobs'))
        : ListView.builder(
            itemCount: model.entries.length,
            itemBuilder: (context, index) {
              final entry = model.entries[index];
              return Card(
                child: ExpansionTile(
                  key: ValueKey(entry.record.jobId),
                  title: Text(entry.record.kind),
                  subtitle: Text(
                    '${entry.record.jobId} · ${entry.record.state.wireName}',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(value: entry.progress),
                          const SizedBox(height: 8),
                          Text('Progress: ${(entry.progress * 100).round()}%'),
                          Text('Owner: ${entry.record.ownerId}'),
                          if (entry.logRef != null)
                            Text('Log reference: ${entry.logRef}'),
                          if (entry.record.resultRef != null)
                            Text('Result: ${entry.record.resultRef}'),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
  );
}
