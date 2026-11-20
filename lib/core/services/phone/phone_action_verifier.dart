import 'phone_observation_adapter.dart';

/// Verification never executes or retries a Phone Use action.
/// A host must independently obtain the before/after observations.
enum PhoneActionVerdict { verified, unchanged, unknown }

final class PhoneActionReceipt {
  PhoneActionReceipt({
    required this.actionId,
    required this.before,
    required this.after,
    required this.verdict,
    required this.reason,
  });

  final String actionId;
  final PhoneObservation before;
  final PhoneObservation? after;
  final PhoneActionVerdict verdict;
  final String reason;
  bool get mayAutoReplay => false;
}

/// Conservative, read-only before/after observation comparator.
/// A change in an observation is evidence of change, not of intent success;
/// the caller supplies a trusted expected after-state predicate.
final class PhoneActionVerifier {
  final Set<String> _consumedActions = {};

  PhoneActionReceipt verify({
    required String actionId,
    required PhoneObservation before,
    required PhoneObservation? after,
    required bool Function(PhoneObservation) expectedAfter,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$').hasMatch(actionId)) {
      throw ArgumentError('Invalid action ID');
    }
    if (!_consumedActions.add(actionId)) {
      throw StateError('Repeated action receipt is not safe to replay');
    }
    if (after == null) {
      return PhoneActionReceipt(
        actionId: actionId,
        before: before,
        after: null,
        verdict: PhoneActionVerdict.unknown,
        reason: 'Missing after observation',
      );
    }
    if (before.deviceRef != after.deviceRef ||
        before.windowRef != after.windowRef ||
        after.capturedAt.isBefore(before.capturedAt)) {
      return PhoneActionReceipt(
        actionId: actionId,
        before: before,
        after: after,
        verdict: PhoneActionVerdict.unknown,
        reason: 'Observation identity or time mismatch',
      );
    }
    if (_signature(before) == _signature(after)) {
      return PhoneActionReceipt(
        actionId: actionId,
        before: before,
        after: after,
        verdict: PhoneActionVerdict.unchanged,
        reason: 'No observable difference',
      );
    }
    return PhoneActionReceipt(
      actionId: actionId,
      before: before,
      after: after,
      verdict: expectedAfter(after)
          ? PhoneActionVerdict.verified
          : PhoneActionVerdict.unknown,
      reason: 'Expected after-state validation',
    );
  }

  String _signature(PhoneObservation observation) {
    final nodeData = observation.nodes
        .map(
          (n) =>
              '${n.id}|${n.parentId}|${n.bounds.toJson()}|${n.label}|${n.sensitive}',
        )
        .join(';');
    return '${observation.source.name}|${observation.screenshotRef}|$nodeData';
  }
}
