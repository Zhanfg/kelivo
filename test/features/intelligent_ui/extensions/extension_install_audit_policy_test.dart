import 'package:Kelivo/features/intelligent_ui/extensions/extension_install_audit_policy.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/extension_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UiExtensionManifest manifest({
    UiExtensionRuntime runtime = UiExtensionRuntime.sandboxedWeb,
  }) => UiExtensionManifest(
    packageId: 'example.widgets',
    version: '1.0.0',
    runtime: runtime,
    components: [
      UiExtensionComponent(
        name: 'Viewer',
        properties: {'name': UiExtensionValueType.string},
      ),
    ],
    requestedCapabilities: {'artifact.read'},
  );

  const policy = ExtensionInstallAuditPolicy();
  test(
    'allowed metadata is only eligible for review, not automatic installation',
    () {
      expect(
        policy.check(
          manifest(),
          ownerConsent: true,
          signatureVerified: true,
          dependenciesPinned: true,
          sandboxAvailable: true,
        ),
        ExtensionInstallDecision.allowForReview,
      );
    },
  );

  test('missing consent, signature, version lock or sandbox denies', () {
    for (var blocked = 0; blocked < 4; blocked++) {
      expect(
        policy.check(
          manifest(),
          ownerConsent: blocked != 0,
          signatureVerified: blocked != 1,
          dependenciesPinned: blocked != 2,
          sandboxAvailable: blocked != 3,
        ),
        ExtensionInstallDecision.deny,
      );
    }
  });

  test('Root, Shell, LSPosed and unbounded MCP capabilities always denied', () {
    for (final capability in [
      'shell.execute',
      'root.su',
      'lsposed.hook',
      'mcp.unrestricted',
      'filesystem.readAll',
    ]) {
      expect(
        policy.checkRawCapabilities([capability]),
        ExtensionInstallDecision.deny,
      );
      expect(
        () => UiExtensionManifest(
          packageId: 'example.widgets',
          version: '1.0.0',
          runtime: UiExtensionRuntime.sandboxedWeb,
          components: [
            UiExtensionComponent(
              name: 'Viewer',
              properties: {'name': UiExtensionValueType.string},
            ),
          ],
          requestedCapabilities: {capability},
        ),
        throwsArgumentError,
      );
    }
  });

  test('compiled Flutter runtime cannot be installed as sandboxed Web', () {
    expect(
      policy.check(
        manifest(runtime: UiExtensionRuntime.compiledFlutter),
        ownerConsent: true,
        signatureVerified: true,
        dependenciesPinned: true,
        sandboxAvailable: true,
      ),
      ExtensionInstallDecision.deny,
    );
  });
}
