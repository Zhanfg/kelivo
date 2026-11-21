import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/extension_manifest.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/web_extension_surface.dart';

/// Cross-platform policy regression only. This does not start a WebView.
/// The real host sandbox/injected JS bridge/CSP/network interception remain
/// unverified until a platform WebView implementation is provided.
void main() {
  UiExtensionManifest manifest({bool requestNetwork = true}) =>
      UiExtensionManifest(
        packageId: 'audit.widget',
        version: '1.0.0',
        runtime: UiExtensionRuntime.sandboxedWeb,
        requestedCapabilities: requestNetwork ? {'network.fetch'} : {},
        components: [
          UiExtensionComponent(
            name: 'Audit',
            properties: {'title': UiExtensionValueType.string},
          ),
        ],
      );

  WebExtensionSurface surface({bool requestNetwork = true}) =>
      WebExtensionSurface(
        manifest: manifest(requestNetwork: requestNetwork),
        allowedOrigins: [Uri.parse('https://safe.example.org')],
      );

  test('navigation denied before activation and after suspension/dispose', () {
    final s = surface();
    final url = Uri.parse('https://safe.example.org/path');
    expect(s.permitsNavigation(url), isFalse);
    s.activate();
    expect(s.permitsNavigation(url), isTrue);
    s.suspend();
    expect(s.permitsNavigation(url), isFalse);
    s.dispose();
    expect(s.permitsNavigation(url), isFalse);
    expect(() => s.activate(), throwsStateError);
  });

  test('no network grant means denied at allowlisted origin', () {
    final s = surface(requestNetwork: false)..activate();
    expect(
      s.permitsNavigation(Uri.parse('https://safe.example.org/a')),
      isFalse,
    );
    expect(s.permitsArbitraryHostTools, isFalse);
  });

  test('unsafe schemes, userinfo, ports and sibling hosts are denied', () {
    final s = surface()..activate();
    for (final raw in <String>[
      'http://safe.example.org/a',
      'file:///data/local/tmp/x',
      'javascript:alert(1)',
      'data:text/html,test',
      'https://safe.example.org.attacker.test/a',
      'https://unsafe.example.org/a',
      'https://user:pw@safe.example.org/a',
      'https://safe.example.org:8443/a',
      'https://safe.example.org/a#fragment',
    ]) {
      expect(
        s.permitsNavigation(Uri.parse(raw)),
        isFalse,
        reason: 'Expected deny for $raw',
      );
    }
  });

  test('invalid allowlisted origins rejected before activation', () {
    for (final raw in <String>[
      'http://safe.example.org',
      'https://safe.example.org/unsafe',
      'https://safe.example.org:8443',
      'https://user@safe.example.org',
      'https://safe.example.org?x=y',
    ]) {
      expect(
        () => WebExtensionSurface(
          manifest: manifest(),
          allowedOrigins: [Uri.parse(raw)],
        ),
        throwsArgumentError,
        reason: 'Expected deny for $raw',
      );
    }
  });

  test('real Android/desktop WebView JS bridge and CSP isolation', () {
    fail('Requires host WebView integration and real platform evidence');
  }, skip: 'NOT TESTED: WebView host/CSP/JS bridge platform acceptance');
}
