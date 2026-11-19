import 'dart:async';

import 'job_record.dart';

/// Supported reactions to a terminal Job event. No reaction is an implicit
/// authorization to send notifications, execute workflows or wake an Agent.
enum JobEventAction { notify, workflow, wakeAgent }

/// Immutable event receipt. Stores opaque references, not messages or secrets.
final class JobCompletionEvent {
  JobCompletionEvent({required this.record, required this.emittedAt}) {
    if (!record.isTerminal) {
      throw ArgumentError('Only terminal jobs can emit completion events');
    }
    if (emittedAt.toUtc().isBefore(record.updatedAt)) {
      throw ArgumentError('Event timestamp predates job state');
    }
  }

  final JobRecord record;
  final DateTime emittedAt;

  String get eventId => '${record.jobId}:${record.state.wireName}';
}

/// Explicit, bounded, side-effect-free subscription policy.
final class JobEventSubscription {
  JobEventSubscription({
    required this.id,
    required this.ownerId,
    required Set<JobEventAction> actions,
    this.maxAgentWakes = 0,
  }) : actions = Set.unmodifiable(actions) {
    if (!RegExp(r'^[a-zA-Z0-9_.:-]{1,120}$').hasMatch(id) ||
        !RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$').hasMatch(ownerId)) {
      throw ArgumentError('Invalid opaque subscription identity');
    }
    if (maxAgentWakes < 0 || maxAgentWakes > 32) {
      throw ArgumentError('Invalid Agent wake budget');
    }
    if (actions.contains(JobEventAction.wakeAgent) && maxAgentWakes == 0) {
      throw ArgumentError('Agent wake requires an explicit nonzero budget');
    }
  }

  final String id;
  final String ownerId;
  final Set<JobEventAction> actions;
  final int maxAgentWakes;
}

final class JobEventDelivery {
  const JobEventDelivery({
    required this.eventId,
    required this.subscriptionId,
    required this.action,
  });

  final String eventId;
  final String subscriptionId;
  final JobEventAction action;
}

/// Deterministic mock event router. It does not call host notification,
/// workflows or Agent APIs. Delivery receipts are advisory pending a durable
/// outbox, actor authorization and actual delivery acknowledgements.
final class JobEventRouter {
  final Map<String, JobEventSubscription> _subscriptions = {};
  final Set<String> _seenEvents = {};
  final Map<String, int> _wakeCounts = {};
  final StreamController<JobEventDelivery> _events =
      StreamController<JobEventDelivery>.broadcast(sync: true);

  Stream<JobEventDelivery> get deliveries => _events.stream;

  void subscribe(JobEventSubscription subscription) {
    if (_subscriptions.containsKey(subscription.id)) {
      throw StateError('Subscription ID already exists');
    }
    _subscriptions[subscription.id] = subscription;
  }

  void unsubscribe(String subscriptionId) {
    _subscriptions.remove(subscriptionId);
  }

  int wakeCount(String subscriptionId) => _wakeCounts[subscriptionId] ?? 0;

  /// Routes each terminal event exactly once per in-memory router lifetime.
  ///
  /// This is NOT an exactly-once delivery guarantee across restarts.
  List<JobEventDelivery> publish(JobCompletionEvent event) {
    if (!_seenEvents.add(event.eventId)) return const [];
    final messages = <JobEventDelivery>[];
    for (final subscription in _subscriptions.values) {
      if (subscription.ownerId != event.record.ownerId) continue;
      for (final action in subscription.actions) {
        if (action == JobEventAction.wakeAgent) {
          final used = wakeCount(subscription.id);
          if (used >= subscription.maxAgentWakes) continue;
          _wakeCounts[subscription.id] = used + 1;
        }
        final message = JobEventDelivery(
          eventId: event.eventId,
          subscriptionId: subscription.id,
          action: action,
        );
        messages.add(message);
        _events.add(message);
      }
    }
    return List.unmodifiable(messages);
  }

  Future<void> dispose() => _events.close();
}
