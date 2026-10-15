import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/agent/providers/agent_settings_provider.dart';

void main() {
  test('read-only Agent mode forbids direct shell execution', () {
    expect(AgentPermissionMode.readOnly.allowsDirectShell, isFalse);
    expect(AgentPermissionMode.ask.allowsDirectShell, isTrue);
    expect(AgentPermissionMode.planFirst.allowsDirectShell, isTrue);
    expect(AgentPermissionMode.auto.allowsDirectShell, isTrue);
  });
}
