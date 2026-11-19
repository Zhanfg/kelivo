import 'package:Kelivo/core/services/jobs/job_events.dart';
import 'package:Kelivo/core/services/jobs/job_record.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 11, 20);

JobRecord _record(
  String id, {
  String owner = 'owner:test',
  JobState state = JobState.completed,
}) => JobRecord(
  jobId: 'job_${id.padLeft(8, '0')}',
  kind: 'download',
  ownerId: owner,
  state: state,
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  late JobEventRouter router;

  setUp(() => router = JobEventRouter());
  tearDown(() async => router.dispose());

  test('terminal events only, with monotonic timestamps', () {
    expect(
      () => JobCompletionEvent(
        record: _record('1', state: JobState.running),
        emittedAt: _now,
      ),
      throwsArgumentError,
    );
    expect(
      () => JobCompletionEvent(
        record: _record('2'),
        emittedAt: _now.subtract(const Duration(seconds: 1)),
      ),
      throwsArgumentError,
    );
  });

  test('explicit subscriber receives only enabled actions', () {
    router.subscribe(
      JobEventSubscription(
        id: 'sub:one',
        ownerId: 'owner:test',
        actions: {JobEventAction.notify, JobEventAction.workflow},
      ),
    );
    final receipt = router.publish(
      JobCompletionEvent(record: _record('3'), emittedAt: _now),
    );
    expect(receipt.map((e) => e.action).toSet(), {
      JobEventAction.notify,
      JobEventAction.workflow,
    });
    expect(receipt.every((e) => e.subscriptionId == 'sub:one'), isTrue);
  });

  test('duplicate terminal event cannot redeliver or reawaken', () {
    router.subscribe(
      JobEventSubscription(
        id: 'sub:once',
        ownerId: 'owner:test',
        actions: {JobEventAction.wakeAgent},
        maxAgentWakes: 2,
      ),
    );
    final event = JobCompletionEvent(record: _record('4'), emittedAt: _now);
    expect(router.publish(event), hasLength(1));
    expect(router.publish(event), isEmpty);
    expect(router.wakeCount('sub:once'), 1);
  });

  test('wake budget is enforced across multiple completions', () {
    router.subscribe(
      JobEventSubscription(
        id: 'sub:bounded',
        ownerId: 'owner:test',
        actions: {JobEventAction.notify, JobEventAction.wakeAgent},
        maxAgentWakes: 2,
      ),
    );
    for (var i = 0; i < 5; i++) {
      router.publish(
        JobCompletionEvent(record: _record('bounded$i'), emittedAt: _now),
      );
    }
    expect(router.wakeCount('sub:bounded'), 2);
  });

  test('owner boundaries prevent cross-owner delivery', () {
    router.subscribe(
      JobEventSubscription(
        id: 'sub:private',
        ownerId: 'owner:other',
        actions: {JobEventAction.notify},
      ),
    );
    final messages = router.publish(
      JobCompletionEvent(record: _record('5'), emittedAt: _now),
    );
    expect(messages, isEmpty);
  });

  test('duplicate subscription IDs and unbounded wakes rejected', () {
    final subscription = JobEventSubscription(
      id: 'sub:exists',
      ownerId: 'owner:test',
      actions: {JobEventAction.notify},
    );
    router.subscribe(subscription);
    expect(() => router.subscribe(subscription), throwsStateError);
    expect(
      () => JobEventSubscription(
        id: 'sub:bad',
        ownerId: 'owner:test',
        actions: {JobEventAction.wakeAgent},
      ),
      throwsArgumentError,
    );
  });

  test('unsubscribe blocks subsequent event emission', () {
    router.subscribe(
      JobEventSubscription(
        id: 'sub:removed',
        ownerId: 'owner:test',
        actions: {JobEventAction.notify},
      ),
    );
    router.unsubscribe('sub:removed');
    expect(
      router.publish(JobCompletionEvent(record: _record('6'), emittedAt: _now)),
      isEmpty,
    );
  });

  test('delivery stream only contains routed receipts', () async {
    final items = <JobEventDelivery>[];
    final subscription = router.deliveries.listen(items.add);
    router.subscribe(
      JobEventSubscription(
        id: 'sub:stream',
        ownerId: 'owner:test',
        actions: {JobEventAction.notify},
      ),
    );
    router.publish(JobCompletionEvent(record: _record('7'), emittedAt: _now));
    expect(items, hasLength(1));
    expect(items.single.eventId, 'job_00000007:completed');
    await subscription.cancel();
  });
}
