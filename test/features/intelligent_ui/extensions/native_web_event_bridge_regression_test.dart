import 'package:Kelivo/features/intelligent_ui/extensions/extension_event_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

/// #65: in-memory bridge admission only, not a live WebView-to-Flutter channel.
void main() {
  ExtensionEvent message(
    int seq, {
    String namespace = 'widget',
    String instance = 'instance:1',
    ExtensionEventKind kind = ExtensionEventKind.event,
    ExtensionOrigin origin = ExtensionOrigin.extension,
    Map<String, Object?> payload = const {'selected': 'safe'},
  }) => ExtensionEvent(
    namespace: namespace,
    instanceId: instance,
    sequence: seq,
    kind: kind,
    origin: origin,
    payload: payload,
  );

  test('host props and extension events share scoped ordered queue', () {
    final bridge = ExtensionEventBridge(
      namespace: 'widget',
      instanceId: 'instance:1',
      maxOutstanding: 2,
    );
    bridge.receive(
      message(1, kind: ExtensionEventKind.props, origin: ExtensionOrigin.host),
    );
    bridge.receive(message(2));
    expect(bridge.peek()!.kind, ExtensionEventKind.props);
    expect(bridge.outstandingCount, 2);
    bridge.receive(message(1, kind: ExtensionEventKind.acknowledgement));
    expect(bridge.peek()!.sequence, 2);
  });

  test(
    'host-scope forgery, cross-instance dispatch and replay are rejected',
    () {
      final bridge = ExtensionEventBridge(
        namespace: 'widget',
        instanceId: 'instance:1',
      );
      expect(
        () => bridge.receive(message(1, kind: ExtensionEventKind.props)),
        throwsStateError,
      );
      expect(
        () => bridge.receive(message(1, namespace: 'other')),
        throwsStateError,
      );
      expect(
        () => bridge.receive(message(1, instance: 'instance:other')),
        throwsStateError,
      );
      bridge.receive(message(1));
      bridge.acknowledge(1);
      expect(() => bridge.receive(message(1)), throwsStateError);
    },
  );

  test(
    'queue saturation cannot reorder or silently drop accepted receipts',
    () {
      final bridge = ExtensionEventBridge(
        namespace: 'widget',
        instanceId: 'instance:1',
        maxOutstanding: 1,
      );
      bridge.receive(message(1));
      expect(() => bridge.receive(message(2)), throwsStateError);
      expect(bridge.peek()!.sequence, 1);
      bridge.acknowledge(1);
      bridge.receive(message(2));
      expect(bridge.peek()!.sequence, 2);
      bridge.clear();
      expect(() => bridge.receive(message(2)), throwsStateError);
    },
  );

  test('payloads cannot smuggle executable objects or prototype keys', () {
    expect(
      () => message(1, payload: {'__proto__': 'injected'}),
      throwsArgumentError,
    );
    expect(
      () => message(1, payload: {'v': double.infinity}),
      throwsArgumentError,
    );
    expect(() => message(1, payload: {'v': Object()}), throwsArgumentError);
    // A string describing a command is only data; the bridge never executes it.
    final bridge = ExtensionEventBridge(
      namespace: 'widget',
      instanceId: 'instance:1',
    );
    bridge.receive(message(1, payload: {'shell': 'rm -rf /'}));
    expect(bridge.peek()!.payload['shell'], 'rm -rf /');
  });
}
