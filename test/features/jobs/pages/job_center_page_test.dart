import 'package:Kelivo/core/services/jobs/job_record.dart';
import 'package:Kelivo/features/jobs/pages/job_center_page.dart';
// ignore_for_file: deprecated_member_use
// Flutter 3.47 compatibility: retain the stable Material import until
// the shared Build/CI owner migrates the application to material_ui.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _time = DateTime.utc(2026, 11, 20);
JobCenterEntry _entry(
  String id, {
  JobState state = JobState.running,
  double progress = 0.4,
  String? logRef,
}) => JobCenterEntry(
  record: JobRecord(
    jobId: 'job_${id.padLeft(8, '0')}',
    kind: 'download',
    ownerId: 'owner:test',
    state: state,
    createdAt: _time,
    updatedAt: _time,
  ),
  progress: progress,
  logRef: logRef,
);

void main() {
  test('read-only model is immutable and stable', () {
    final records = [_entry('a'), _entry('b')];
    final model = JobCenterReadOnlyModel(records);
    records.clear();
    expect(model.entries, hasLength(2));
    expect(() => model.entries.clear(), throwsUnsupportedError);
  });

  test('bounded pagination and state filtering', () {
    final model = JobCenterReadOnlyModel([
      _entry('a'),
      _entry('b', state: JobState.completed),
      _entry('c'),
    ]);
    expect(model.page(state: JobState.completed), hasLength(1));
    expect(
      model.page(offset: 1, limit: 1).single.record.state,
      JobState.completed,
    );
    expect(() => model.page(limit: 500), throwsArgumentError);
  });

  test('duplicate IDs and invalid progress are rejected', () {
    expect(
      () => JobCenterReadOnlyModel([_entry('a'), _entry('a')]),
      throwsArgumentError,
    );
    expect(() => _entry('a', progress: double.nan), throwsArgumentError);
    expect(() => _entry('a', progress: -0.1), throwsArgumentError);
    expect(() => _entry('a', logRef: '../private'), throwsArgumentError);
  });

  testWidgets('empty states are visible without actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: JobCenterPage(model: JobCenterReadOnlyModel([]))),
    );
    expect(find.text('No jobs'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('progress, status, and opaque log reference are displayed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: JobCenterPage(
          model: JobCenterReadOnlyModel([
            _entry('a', progress: 0.5, logRef: 'artifact:log'),
          ]),
        ),
      ),
    );
    expect(find.text('download'), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Progress: 50%'), findsOneWidget);
    expect(find.text('Log reference: artifact:log'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
