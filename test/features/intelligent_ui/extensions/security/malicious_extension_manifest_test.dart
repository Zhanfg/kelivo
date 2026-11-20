import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/extension_manifest.dart';

/// Regression fixtures only. These malicious manifests must never be loaded
/// into an executable WebView or granted any real host capabilities.
void main() {
  UiExtensionManifest benign({Set<String> capabilities = const {}}) =>
      UiExtensionManifest(
        packageId: 'sample.widget',
        version: '1.0.0',
        runtime: UiExtensionRuntime.sandboxedWeb,
        requestedCapabilities: capabilities,
        components: [
          UiExtensionComponent(
            name: 'Preview',
            properties: {'title': UiExtensionValueType.string},
            requiredProperties: {'title'},
          ),
        ],
      );

  test(
    'host execution, root, filesystem escape, and unrestricted MCP forbidden',
    () {
      for (final request in [
        'shell.execute',
        'root',
        'file.read',
        'file.write',
        'host.call',
        'mcp.unrestricted',
        'network.unrestricted',
        '../private',
        'artifact.read/../../secret',
      ]) {
        expect(
          () => benign(capabilities: {request}),
          throwsArgumentError,
          reason: 'must reject $request',
        );
      }
    },
  );

  test('approved capability requests are not implicit permission grants', () {
    final value = benign(
      capabilities: {'artifact.read', 'network.fetch', 'clipboard.write'},
    );
    expect(value.requestedCapabilities.length, 3);
    expect(value.toJson()['requestedCapabilities'], [
      'artifact.read',
      'clipboard.write',
      'network.fetch',
    ]);
  });

  test('wire format rejects malformed and duplicate requested permissions', () {
    final source = benign().toJson();
    for (final permissions in [
      ['root'],
      ['network.fetch', 'network.fetch'],
      [1],
    ]) {
      expect(
        () => UiExtensionManifest.fromJson({
          ...source,
          'requestedCapabilities': permissions,
        }),
        throwsFormatException,
      );
    }
  });

  test('package path traversal and malformed identifiers rejected', () {
    for (final id in [
      '../escape',
      '/absolute',
      'file:///etc',
      'foo..bar',
      'bad/package',
      'A.B',
    ]) {
      final wire = benign().toJson()..['packageId'] = id;
      expect(
        () => UiExtensionManifest.fromJson(wire),
        throwsFormatException,
        reason: 'must reject package $id',
      );
    }
  });

  test('unknown runtime and schema cannot bypass security gate', () {
    final source = benign().toJson();
    expect(
      () => UiExtensionManifest.fromJson({...source, 'runtime': 'host_native'}),
      throwsFormatException,
    );
    expect(
      () => UiExtensionManifest.fromJson({...source, 'schemaVersion': 999}),
      throwsFormatException,
    );
  });

  test('resource exhaustion through component count is rejected', () {
    expect(
      () => UiExtensionManifest(
        packageId: 'sample.widget',
        version: '1.0.0',
        runtime: UiExtensionRuntime.sandboxedWeb,
        components: [
          for (var i = 0; i < 65; i++)
            UiExtensionComponent(
              name: 'Widget$i',
              properties: {'text': UiExtensionValueType.string},
            ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('oversized component property set is rejected', () {
    expect(
      () => UiExtensionComponent(
        name: 'Widget',
        properties: {
          for (var i = 0; i < 49; i++) 'field$i': UiExtensionValueType.string,
        },
      ),
      throwsArgumentError,
    );
  });

  test('duplicate component names cannot shadow approved descriptors', () {
    final component = UiExtensionComponent(
      name: 'Preview',
      properties: {'title': UiExtensionValueType.string},
    );
    expect(
      () => UiExtensionManifest(
        packageId: 'sample.widget',
        version: '1.0.0',
        runtime: UiExtensionRuntime.sandboxedWeb,
        components: [component, component],
      ),
      throwsArgumentError,
    );
  });
}
