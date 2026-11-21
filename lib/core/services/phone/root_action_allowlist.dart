/// Conservative Phone Use Root action policy. NEVER executes `su` or shell.
enum RootPhoneAction {
  readSystemVersion,
  readBatteryHealth,
  readDeviceProperties,
}

enum RootPolicyOutcome { allowed, denied }

final class RootActionRequest {
  RootActionRequest({
    required this.taskId,
    required this.action,
    required this.explicitConsent,
    required this.policyScope,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9_.:-]{1,128}$').hasMatch(taskId) ||
        !RegExp(r'^[a-zA-Z0-9_.:-]{1,128}$').hasMatch(policyScope)) {
      throw ArgumentError('Invalid task or policy scope');
    }
  }
  final String taskId;
  final RootPhoneAction action;
  final String policyScope;
  final bool explicitConsent;
}

final class RootActionAllowlist {
  RootActionAllowlist({
    required this.taskScope,
    Set<RootPhoneAction> approved = const {},
  }) : approved = Set.unmodifiable(approved);
  final String taskScope;
  final Set<RootPhoneAction> approved;
  final Set<String> _consumed = {};

  RootPolicyOutcome authorize(RootActionRequest request) {
    if (!_consumed.add('${request.taskId}:${request.action.name}')) {
      return RootPolicyOutcome.denied;
    }
    if (!request.explicitConsent ||
        request.policyScope != taskScope ||
        !approved.contains(request.action)) {
      return RootPolicyOutcome.denied;
    }
    return RootPolicyOutcome.allowed;
  }
}
