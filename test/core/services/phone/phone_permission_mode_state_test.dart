import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/phone/phone_permission_mode_state.dart';

void main() {
  test('defaults to human owned standard mode', () {
    final s = PhonePermissionModeState();
    expect(s.owner, PhoneControlOwner.human);
    expect(s.mode, PhonePermissionMode.standard);
    expect(s.paused, isFalse);
  });
  test('privileged modes denied without explicit authorization', () {
    final s = PhonePermissionModeState();
    expect(
      s.requestMode(
        PhonePermissionMode.root,
        explicitUserConsent: false,
        runtimeAvailable: true,
        taskAuthorized: true,
      ),
      PhoneModeDecision.denied,
    );
    expect(
      s.requestMode(
        PhonePermissionMode.lsposed,
        explicitUserConsent: true,
        runtimeAvailable: false,
        taskAuthorized: true,
      ),
      PhoneModeDecision.denied,
    );
    expect(s.mode, PhonePermissionMode.standard);
  });
  test('authorized mode still drops to standard on human takeover', () {
    final s = PhonePermissionModeState();
    expect(
      s.requestMode(
        PhonePermissionMode.root,
        explicitUserConsent: true,
        runtimeAvailable: true,
        taskAuthorized: true,
      ),
      PhoneModeDecision.granted,
    );
    s.handToAgent(userApproved: true);
    s.takeOver();
    expect(s.owner, PhoneControlOwner.human);
    expect(s.mode, PhonePermissionMode.standard);
    expect(s.paused, isTrue);
    expect(
      s.requestMode(
        PhonePermissionMode.root,
        explicitUserConsent: true,
        runtimeAvailable: true,
        taskAuthorized: true,
      ),
      PhoneModeDecision.denied,
    );
    s.resume(userApproved: true);
    expect(s.paused, isFalse);
  });
  test('agent cannot grant itself higher privilege', () {
    final s = PhonePermissionModeState();
    s.handToAgent(userApproved: true);
    expect(
      s.requestMode(
        PhonePermissionMode.lsposed,
        explicitUserConsent: true,
        runtimeAvailable: true,
        taskAuthorized: true,
      ),
      PhoneModeDecision.denied,
    );
    expect(() => s.resume(userApproved: false), throwsStateError);
  });
  test('audit history is immutable and contains no secrets', () {
    final s = PhonePermissionModeState();
    s.takeOver();
    expect(s.auditEvents, ['owner:human-takeover']);
    expect(() => s.auditEvents.add('bad'), throwsUnsupportedError);
  });
}
