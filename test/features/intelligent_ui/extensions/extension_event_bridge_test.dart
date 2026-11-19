import 'package:Kelivo/features/intelligent_ui/extensions/extension_event_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

ExtensionEvent _event(
  int sequence, {
  String namespace = 'viewer',
  String instance = 'instance:1',
  ExtensionEventKind kind = ExtensionEventKind.event,
  ExtensionOrigin origin = ExtensionOrigin.extension,
  Map<String, Object?> payload = const {'selected': 1},
}) => ExtensionEvent(
  namespace: namespace,
  instanceId: instance,
  sequence: sequence,
  kind: kind,
  origin: origin,
  payload: payload,
);

void main() {
  late ExtensionEventBridge bridge;
  setUp(
    () => bridge = ExtensionEventBridge(
      namespace: 'viewer',
      instanceId: 'instance:1',
      maxOutstanding: 2,
    ),
  );

  test('accepts scoped events in increasing sequence', () {
    bridge.receive(_event(1));
    bridge.receive(_event(2));
    expect(bridge.outstandingCount, 2);
    expect(bridge.peek()!.sequence, 1);
    bridge.acknowledge(1);
    expect(bridge.peek()!.sequence, 2);
    bridge.acknowledge(2);
    expect(bridge.outstandingCount, 0);
  });

  test(
    'rejects duplicates, out-of-order and replay even after acknowledgement',
    () {
      bridge.receive(_event(2));
      bridge.acknowledge(2);
      expect(() => bridge.receive(_event(2)), throwsStateError);
      expect(() => bridge.receive(_event(1)), throwsStateError);
      bridge.receive(_event(3));
    },
  );

  test('bounded backpressure does not drop admitted events', () {
    bridge.receive(_event(1));
    bridge.receive(_event(2));
    expect(() => bridge.receive(_event(3)), throwsStateError);
    expect(bridge.peek()!.sequence, 1);
    bridge.acknowledge(1);
    bridge.receive(_event(3));
  });

  test('denies cross-namespace and cross-instance messages', () {
    expect(
      () => bridge.receive(_event(1, namespace: 'other')),
      throwsStateError,
    );
    expect(
      () => bridge.receive(_event(1, instance: 'instance:2')),
      throwsStateError,
    );
    expect(bridge.outstandingCount, 0);
  });

  test('extension cannot forge host props', () {
    expect(
      () => bridge.receive(_event(1, kind: ExtensionEventKind.props)),
      throwsStateError,
    );
    bridge.receive(
      _event(1, kind: ExtensionEventKind.props, origin: ExtensionOrigin.host),
    );
    expect(bridge.outstandingCount, 1);
  });

  test('acknowledgements must be in queue order', () {
    bridge.receive(_event(1));
    bridge.receive(_event(2));
    expect(() => bridge.acknowledge(2), throwsStateError);
    bridge.receive(_event(1, kind: ExtensionEventKind.acknowledgement));
    expect(bridge.peek()!.sequence, 2);
  });

  test('rejects nonfinite and overly deep payloads', () {
    expect(() => _event(1, payload: {'x': double.nan}), throwsArgumentError);
    expect(() => _event(1, payload: {'__proto__': 4}), throwsArgumentError);
    expect(() => _event(1, payload: {'x': 'z' * 4097}), throwsArgumentError);
  });

  test('clear removes receipts without re-enabling replay', () {
    bridge.receive(_event(1));
    bridge.clear();
    expect(bridge.peek(), isNull);
    expect(() => bridge.receive(_event(1)), throwsStateError);
  });
}
