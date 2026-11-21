import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/phone/root_action_allowlist.dart';

void main() {
  RootActionRequest req(
    String id, {
    bool consent = true,
    String scope = 'task:one',
    RootPhoneAction action = RootPhoneAction.readSystemVersion,
  }) => RootActionRequest(
    taskId: id,
    action: action,
    explicitConsent: consent,
    policyScope: scope,
  );

  test('fails closed without explicit consent or approved action', () {
    final policy = RootActionAllowlist(taskScope: 'task:one');
    expect(policy.authorize(req('a')), RootPolicyOutcome.denied);
    final approved = RootActionAllowlist(
      taskScope: 'task:one',
      approved: {RootPhoneAction.readSystemVersion},
    );
    expect(
      approved.authorize(req('b', consent: false)),
      RootPolicyOutcome.denied,
    );
    expect(
      approved.authorize(req('c', action: RootPhoneAction.readBatteryHealth)),
      RootPolicyOutcome.denied,
    );
  });
  test('allows one scoped, consented read-only action', () {
    final policy = RootActionAllowlist(
      taskScope: 'task:one',
      approved: {RootPhoneAction.readSystemVersion},
    );
    expect(policy.authorize(req('a')), RootPolicyOutcome.allowed);
    expect(policy.authorize(req('a')), RootPolicyOutcome.denied);
    expect(
      policy.authorize(req('b', scope: 'task:other')),
      RootPolicyOutcome.denied,
    );
  });
  test('invalid task identifiers refused', () {
    expect(() => req('../escape'), throwsArgumentError);
    expect(() => req('ok', scope: 'bad scope'), throwsArgumentError);
  });
  test('approved set is immutable and no arbitrary shell action exists', () {
    final policy = RootActionAllowlist(
      taskScope: 't',
      approved: {RootPhoneAction.readDeviceProperties},
    );
    expect(
      () => policy.approved.add(RootPhoneAction.readBatteryHealth),
      throwsUnsupportedError,
    );
    expect(
      RootPhoneAction.values.map((e) => e.name),
      isNot(contains('executeShell')),
    );
  });
}
