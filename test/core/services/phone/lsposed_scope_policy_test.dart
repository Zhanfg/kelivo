import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/phone/lsposed_scope_policy.dart';

void main() {
  LsposedTarget target({
    String name = 'org.example.app',
    String process = 'org.example.app',
    String version = '1.2.3',
  }) => LsposedTarget(
    packageName: name,
    processName: process,
    moduleVersion: version,
  );

  test('requires exact package, module version and explicit user consent', () {
    final p = LsposedScopePolicy(
      allowedPackage: 'org.example.app',
      requiredVersion: '1.2.3',
    );
    expect(
      p.evaluate(target(), userApproved: true, moduleHealthy: true),
      LsposedScopeDecision.allow,
    );
    expect(
      p.evaluate(target(), userApproved: false, moduleHealthy: true),
      LsposedScopeDecision.deny,
    );
    expect(
      p.evaluate(
        target(name: 'org.example.other', process: 'org.example.other'),
        userApproved: true,
        moduleHealthy: true,
      ),
      LsposedScopeDecision.deny,
    );
    expect(
      p.evaluate(
        target(version: '1.2.4'),
        userApproved: true,
        moduleHealthy: true,
      ),
      LsposedScopeDecision.deny,
    );
  });
  test('crashed module fail-closed and manual fallback disables use', () {
    final p = LsposedScopePolicy(
      allowedPackage: 'org.example.app',
      requiredVersion: '1.2.3',
    );
    expect(
      p.evaluate(target(), userApproved: true, moduleHealthy: false),
      LsposedScopeDecision.deny,
    );
    p.disable();
    expect(p.enabled, isFalse);
    expect(
      p.evaluate(target(), userApproved: true, moduleHealthy: true),
      LsposedScopeDecision.deny,
    );
  });
  test('rejects malformed names, foreign processes and invalid version', () {
    expect(() => target(name: '../escape'), throwsArgumentError);
    expect(() => target(process: 'org.other.app'), throwsArgumentError);
    expect(() => target(version: 'latest'), throwsArgumentError);
    expect(
      target(process: 'org.example.app:renderer').processName,
      'org.example.app:renderer',
    );
  });
}
