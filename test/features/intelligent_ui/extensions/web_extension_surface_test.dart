import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/extension_manifest.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/web_extension_surface.dart';

void main() {
  UiExtensionManifest manifest({
    bool allowed = false,
    UiExtensionRuntime runtime = UiExtensionRuntime.sandboxedWeb,
  }) => UiExtensionManifest(
    packageId: 'sample.widget',
    version: '1.0.0',
    runtime: runtime,
    requestedCapabilities: allowed ? {'network.fetch'} : {},
    components: [
      UiExtensionComponent(
        name: 'Preview',
        properties: {'label': UiExtensionValueType.string},
      ),
    ],
  );
  WebExtensionSurface surface({bool allowed = false}) => WebExtensionSurface(
    manifest: manifest(allowed: allowed),
    allowedOrigins: [Uri.parse('https://assets.example.org')],
  );

  test('only sandboxed Web runtime is accepted', () {
    expect(
      () => WebExtensionSurface(
        manifest: manifest(runtime: UiExtensionRuntime.compiledFlutter),
        allowedOrigins: const [],
      ),
      throwsArgumentError,
    );
  });

  test('lifecycle forbids navigation while suspended or disposed', () {
    final view = surface(allowed: true);
    final address = Uri.parse('https://assets.example.org/image.png');
    expect(view.permitsNavigation(address), isFalse);
    view.activate();
    expect(view.permitsNavigation(address), isTrue);
    view.suspend();
    expect(view.permitsNavigation(address), isFalse);
    view.activate();
    view.dispose();
    expect(view.permitsNavigation(address), isFalse);
    expect(() => view.activate(), throwsStateError);
    view.dispose();
  });

  test('manifest request cannot grant host bridge', () {
    final view = surface(allowed: true)..activate();
    expect(view.permitsArbitraryHostTools, isFalse);
  });

  test('manifest without network request cannot navigate', () {
    final view = surface()..activate();
    expect(
      view.permitsNavigation(Uri.parse('https://assets.example.org/a')),
      isFalse,
    );
  });

  test('blocks credential URL, unapproved host, and unsafe schemes', () {
    final view = surface(allowed: true)..activate();
    for (final url in [
      'https://other.example.org/x',
      'http://assets.example.org/x',
      'file:///etc/passwd',
      'javascript:alert(1)',
      'data:text/html,hello',
      'https://user:pw@assets.example.org/x',
      'https://assets.example.org/x#fragment',
      'https://assets.example.org:8443/x',
    ]) {
      expect(
        view.permitsNavigation(Uri.parse(url)),
        isFalse,
        reason: 'Must reject $url',
      );
    }
  });

  test('rejects origin with credentials, path, and unsupported scheme', () {
    for (final url in [
      'http://example.org',
      'https://example.org/unsafe',
      'https://user:pw@example.org',
      'https://example.org?q=1',
    ]) {
      expect(
        () => WebExtensionSurface(
          manifest: manifest(allowed: true),
          allowedOrigins: [Uri.parse(url)],
        ),
        throwsArgumentError,
      );
    }
  });

  test('cannot double-activate or suspend before activation', () {
    final view = surface();
    expect(() => view.suspend(), throwsStateError);
    view.activate();
    expect(() => view.activate(), throwsStateError);
  });
}
