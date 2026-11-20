import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/agent/orchestration/agent_mailbox.dart';

void main() {
  final now = DateTime.utc(2026, 11, 20);
  AgentMail mail(
    String id,
    String from,
    String to,
    AgentMailKind kind, {
    String? reply,
    String correlation = 'c1',
  }) => AgentMail(
    messageId: id,
    correlationId: correlation,
    senderId: from,
    recipientId: to,
    kind: kind,
    payloadRef: 'artifact:1',
    replyToId: reply,
    createdAt: now,
  );

  test('roundtrip strict schema and UTC time', () {
    final original = mail('m1', 'p', 'c', AgentMailKind.delegate);
    final parsed = AgentMail.fromJson(original.toJson());
    expect(parsed.toJson(), original.toJson());
    expect(
      () => AgentMail.fromJson({...original.toJson(), 'extra': 1}),
      throwsFormatException,
    );
    expect(
      () => AgentMail.fromJson({...original.toJson(), 'kind': 'bad'}),
      throwsFormatException,
    );
  });

  test('opaque reference validation forbids self and unsafe values', () {
    expect(
      () => mail('bad id', 'p', 'c', AgentMailKind.delegate),
      throwsArgumentError,
    );
    expect(
      () => mail('m', 'p', 'p', AgentMailKind.delegate),
      throwsArgumentError,
    );
    expect(
      () => mail('m', 'p', 'c', AgentMailKind.delegate, reply: 'm'),
      throwsArgumentError,
    );
  });

  test('bounded FIFO collect and duplicate replay prevention', () {
    final box = AgentMailbox(maxPending: 2);
    box.register('p');
    box.register('c', parentId: 'p');
    box.send(mail('m1', 'p', 'c', AgentMailKind.delegate));
    box.send(mail('m2', 'p', 'c', AgentMailKind.delegate));
    expect(
      () => box.send(mail('m3', 'p', 'c', AgentMailKind.delegate)),
      throwsStateError,
    );
    expect(box.collect('c', limit: 1).map((m) => m.messageId), ['m1']);
    expect(box.collect('c').map((m) => m.messageId), ['m2']);
    expect(
      () => box.send(mail('m1', 'p', 'c', AgentMailKind.delegate)),
      throwsStateError,
    );
  });

  test('reply chain must match correlated inverse route', () {
    final box = AgentMailbox();
    box.register('p');
    box.register('c', parentId: 'p');
    box.send(mail('m1', 'p', 'c', AgentMailKind.delegate));
    expect(
      () => box.send(
        mail(
          'wrong',
          'c',
          'p',
          AgentMailKind.result,
          reply: 'm1',
          correlation: 'bad',
        ),
      ),
      throwsStateError,
    );
    box.send(mail('m2', 'c', 'p', AgentMailKind.result, reply: 'm1'));
    expect(box.collect('p').single.messageId, 'm2');
  });

  test('unrelated sessions cannot exchange messages', () {
    final box = AgentMailbox();
    box.register('p');
    box.register('a', parentId: 'p');
    box.register('b', parentId: 'p');
    expect(
      () => box.send(mail('m', 'a', 'b', AgentMailKind.result)),
      throwsStateError,
    );
    expect(
      () => box.send(mail('m2', 'a', 'p', AgentMailKind.delegate)),
      throwsStateError,
    );
  });

  test('depth bounds and missing parent are rejected', () {
    final box = AgentMailbox(maxDepth: 2);
    expect(() => box.register('b', parentId: 'missing'), throwsStateError);
    box.register('root');
    box.register('child', parentId: 'root');
    expect(
      () => box.register('grandchild', parentId: 'child'),
      throwsStateError,
    );
    expect(() => box.register('root', parentId: 'child'), throwsStateError);
  });

  test('retirement purges queued traffic and prevents reuse', () {
    final box = AgentMailbox();
    box.register('p');
    box.register('c', parentId: 'p');
    box.send(mail('m1', 'p', 'c', AgentMailKind.cancel));
    expect(() => box.retire('p'), throwsStateError);
    box.retire('c');
    expect(box.pendingCount, 0);
    expect(() => box.collect('c'), throwsStateError);
    expect(() => box.register('c', parentId: 'p'), throwsStateError);
  });
}
