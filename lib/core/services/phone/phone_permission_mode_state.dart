/// #60 Phone Use mode and takeover state contract. No privileged action runs.
enum PhonePermissionMode { standard, root, lsposed }

enum PhoneControlOwner { agent, human }

enum PhoneModeDecision { granted, denied }

final class PhonePermissionModeState {
  PhonePermissionModeState()
    : _mode = PhonePermissionMode.standard,
      _owner = PhoneControlOwner.human;

  PhonePermissionMode _mode;
  PhoneControlOwner _owner;
  PhonePermissionMode get mode => _mode;
  PhoneControlOwner get owner => _owner;
  bool _paused = false;
  bool get paused => _paused;
  final List<String> _audit = [];
  List<String> get auditEvents => List.unmodifiable(_audit);

  PhoneModeDecision requestMode(
    PhonePermissionMode desired, {
    required bool explicitUserConsent,
    required bool runtimeAvailable,
    required bool taskAuthorized,
  }) {
    if (_paused ||
        _owner != PhoneControlOwner.human ||
        !taskAuthorized ||
        !runtimeAvailable ||
        desired != PhonePermissionMode.standard && !explicitUserConsent) {
      _audit.add('mode-denied:${desired.name}');
      return PhoneModeDecision.denied;
    }
    _mode = desired;
    _audit.add('mode:${desired.name}');
    return PhoneModeDecision.granted;
  }

  void handToAgent({required bool userApproved}) {
    if (!userApproved || _paused) {
      throw StateError('User takeover/approval required');
    }
    _owner = PhoneControlOwner.agent;
    _audit.add('owner:agent');
  }

  /// Manual takeover always succeeds, disables autonomous work, and drops
  /// all privileged modes without waiting for the agent to acknowledge.
  void takeOver() {
    _owner = PhoneControlOwner.human;
    _paused = true;
    _mode = PhonePermissionMode.standard;
    _audit.add('owner:human-takeover');
  }

  void resume({required bool userApproved}) {
    if (!userApproved || _owner != PhoneControlOwner.human) {
      throw StateError('Explicit human approval required');
    }
    _paused = false;
    _audit.add('owner:human-resume');
  }
}
