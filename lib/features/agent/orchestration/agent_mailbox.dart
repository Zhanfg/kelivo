/// A bounded, in-memory parent/child Agent mailbox contract.
///
/// Messages carry opaque references only. No prompts, credentials or tool
/// responses are persisted here. Host routing and authorization are external.
enum AgentMailKind { delegate, progress, result, failure, cancel }

final class AgentMail {
  AgentMail({
    required this.messageId,
    required this.correlationId,
    required this.senderId,
    required this.recipientId,
    required this.kind,
    required this.payloadRef,
    required DateTime createdAt,
    this.replyToId,
  }) : createdAt = createdAt.toUtc() {
    for (final ref in [
      messageId,
      correlationId,
      senderId,
      recipientId,
      payloadRef,
      if (replyToId != null) replyToId!,
    ]) {
      if (!RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$').hasMatch(ref)) {
        throw ArgumentError('Invalid opaque mail reference');
      }
    }
    if (senderId == recipientId) throw ArgumentError('Self-routing forbidden');
    if (replyToId == messageId) throw ArgumentError('Self-reference forbidden');
  }

  static const schemaVersion = 1;
  final String messageId;
  final String correlationId;
  final String senderId;
  final String recipientId;
  final AgentMailKind kind;
  final String payloadRef;
  final String? replyToId;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'messageId': messageId,
    'correlationId': correlationId,
    'senderId': senderId,
    'recipientId': recipientId,
    'kind': kind.name,
    'payloadRef': payloadRef,
    'replyToId': replyToId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory AgentMail.fromJson(Map<String, Object?> json) {
    const keys = {
      'schemaVersion',
      'messageId',
      'correlationId',
      'senderId',
      'recipientId',
      'kind',
      'payloadRef',
      'replyToId',
      'createdAt',
    };
    if (json['schemaVersion'] != schemaVersion ||
        json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unsupported Agent mail schema');
    }
    String requiredText(String key) {
      final value = json[key];
      if (value is! String) throw FormatException('Invalid $key');
      return value;
    }

    final kind = AgentMailKind.values.where(
      (value) => value.name == json['kind'],
    );
    if (kind.length != 1) throw const FormatException('Invalid mail kind');
    final reply = json['replyToId'];
    if (reply != null && reply is! String) {
      throw const FormatException('Invalid reply reference');
    }
    final stamp = requiredText('createdAt');
    final time = DateTime.tryParse(stamp);
    if (time == null || !time.isUtc || !stamp.endsWith('Z')) {
      throw const FormatException('Invalid UTC timestamp');
    }
    try {
      return AgentMail(
        messageId: requiredText('messageId'),
        correlationId: requiredText('correlationId'),
        senderId: requiredText('senderId'),
        recipientId: requiredText('recipientId'),
        kind: kind.single,
        payloadRef: requiredText('payloadRef'),
        replyToId: reply as String?,
        createdAt: time,
      );
    } on ArgumentError {
      throw const FormatException('Unsafe mail record');
    }
  }
}

/// One-shot FIFO delivery with explicit parent-child routing and cycle checks.
/// This is not a durable queue and cannot guarantee delivery across restarts.
final class AgentMailbox {
  AgentMailbox({this.maxPending = 128, this.maxDepth = 16}) {
    if (maxPending <= 0 || maxDepth <= 0) {
      throw ArgumentError('Mailbox limits must be positive');
    }
  }

  final int maxPending;
  final int maxDepth;
  final Map<String, String?> _parents = {};
  final Map<String, AgentMail> _seen = {};
  final List<AgentMail> _pending = [];
  final Set<String> _retired = {};

  int get pendingCount => _pending.length;

  /// Register a parent before its child; never connect two existing trees.
  void register(String sessionId, {String? parentId}) {
    _checkRef(sessionId);
    if (parentId != null) _checkRef(parentId);
    if (_parents.containsKey(sessionId) || _retired.contains(sessionId)) {
      throw StateError('Session already registered or retired');
    }
    if (parentId != null && !_parents.containsKey(parentId)) {
      throw StateError('Unknown parent');
    }
    var ancestor = parentId;
    var depth = 1;
    while (ancestor != null) {
      if (ancestor == sessionId) throw StateError('Session cycle');
      if (++depth > maxDepth) throw StateError('Session depth exceeded');
      ancestor = _parents[ancestor];
    }
    _parents[sessionId] = parentId;
  }

  /// Retire a leaf only, dropping undelivered messages for that recipient.
  void retire(String sessionId) {
    if (!_parents.containsKey(sessionId)) throw StateError('Unknown session');
    if (_parents.values.contains(sessionId)) {
      throw StateError('Retire children before parent');
    }
    _parents.remove(sessionId);
    _retired.add(sessionId);
    _pending.removeWhere(
      (m) => m.senderId == sessionId || m.recipientId == sessionId,
    );
  }

  /// Queue a new message. Duplicate IDs cannot be replayed after collection.
  void send(AgentMail message) {
    if (_seen.containsKey(message.messageId)) {
      throw StateError('Duplicate message ID');
    }
    if (!_parents.containsKey(message.senderId) ||
        !_parents.containsKey(message.recipientId)) {
      throw StateError('Unavailable Agent session');
    }
    if (_parents[message.senderId] != message.recipientId &&
        _parents[message.recipientId] != message.senderId) {
      throw StateError('Only direct parent-child messages are permitted');
    }
    if (message.kind == AgentMailKind.delegate &&
        _parents[message.recipientId] != message.senderId) {
      throw StateError('Delegate requires a direct child');
    }
    if (message.replyToId != null) {
      final original = _seen[message.replyToId];
      if (original == null ||
          original.correlationId != message.correlationId ||
          original.senderId != message.recipientId ||
          original.recipientId != message.senderId) {
        throw StateError('Invalid reply chain');
      }
    }
    if (_pending.length >= maxPending) throw StateError('Mailbox full');
    _seen[message.messageId] = message;
    _pending.add(message);
  }

  /// Consume at most [limit] messages addressed to one registered session.
  List<AgentMail> collect(String recipientId, {int limit = 32}) {
    if (!_parents.containsKey(recipientId)) {
      throw StateError('Unavailable Agent session');
    }
    if (limit <= 0) {
      throw ArgumentError('Invalid collection bound');
    }
    final result = <AgentMail>[];
    _pending.removeWhere((mail) {
      if (mail.recipientId != recipientId || result.length >= limit) {
        return false;
      }
      result.add(mail);
      return true;
    });
    return List.unmodifiable(result);
  }

  static void _checkRef(String ref) {
    if (!RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$').hasMatch(ref)) {
      throw ArgumentError('Invalid session reference');
    }
  }
}
