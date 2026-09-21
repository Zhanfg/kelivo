import '../../../core/services/json_blob_store.dart';

enum StoryActionSource { freeAction, quickReply, formalChoice }

enum StoryActionReceiptStatus { pending, resolved, failed }

final class StoryActionReceipt {
  const StoryActionReceipt({
    required this.id,
    required this.conversationId,
    required this.source,
    required this.label,
    required this.submitText,
    required this.createdAt,
    this.status = StoryActionReceiptStatus.pending,
    this.resultSummary,
    this.assistantMessageId,
    this.resolvedAt,
  });

  final String id;
  final String conversationId;
  final StoryActionSource source;
  final String label;
  final String submitText;
  final DateTime createdAt;
  final StoryActionReceiptStatus status;
  final String? resultSummary;
  final String? assistantMessageId;
  final DateTime? resolvedAt;

  StoryActionReceipt copyWith({
    StoryActionReceiptStatus? status,
    String? resultSummary,
    String? assistantMessageId,
    DateTime? resolvedAt,
    bool clearResultSummary = false,
  }) => StoryActionReceipt(
    id: id,
    conversationId: conversationId,
    source: source,
    label: label,
    submitText: submitText,
    createdAt: createdAt,
    status: status ?? this.status,
    resultSummary: clearResultSummary
        ? null
        : (resultSummary ?? this.resultSummary),
    assistantMessageId: assistantMessageId ?? this.assistantMessageId,
    resolvedAt: resolvedAt ?? this.resolvedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'conversationId': conversationId,
    'source': source.name,
    'label': label,
    'submitText': submitText,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status.name,
    if (resultSummary != null) 'resultSummary': resultSummary,
    if (assistantMessageId != null) 'assistantMessageId': assistantMessageId,
    if (resolvedAt != null) 'resolvedAt': resolvedAt!.toUtc().toIso8601String(),
  };

  factory StoryActionReceipt.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json['id'], 'id');
    final conversationId = _requiredString(
      json['conversationId'],
      'conversationId',
    );
    return StoryActionReceipt(
      id: id,
      conversationId: conversationId,
      source: StoryActionSource.values.firstWhere(
        (value) => value.name == json['source'],
        orElse: () => StoryActionSource.freeAction,
      ),
      label: _requiredString(json['label'], 'label'),
      submitText: _requiredString(json['submitText'], 'submitText'),
      createdAt: DateTime.parse(
        _requiredString(json['createdAt'], 'createdAt'),
      ).toUtc(),
      status: StoryActionReceiptStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => StoryActionReceiptStatus.pending,
      ),
      resultSummary: _optionalString(json['resultSummary']),
      assistantMessageId: _optionalString(json['assistantMessageId']),
      resolvedAt: _optionalString(json['resolvedAt']) == null
          ? null
          : DateTime.parse(json['resolvedAt'] as String).toUtc(),
    );
  }
}

final class StoryActionReceiptStore extends JsonBlobStore<StoryActionReceipt> {
  StoryActionReceiptStore(super.preferences);

  static const String key = 'story_action_receipts_v1';

  @override
  String get storageKey => key;

  @override
  StoryActionReceipt decodeItem(Map<String, dynamic> json) =>
      StoryActionReceipt.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryActionReceipt item) => item.toJson();

  Future<StoryActionReceipt> begin({
    required String conversationId,
    required StoryActionSource source,
    required String label,
    required String submitText,
  }) async {
    final conversation = conversationId.trim();
    final normalizedText = submitText.trim();
    final normalizedLabel = label.trim();
    if (conversation.isEmpty) {
      throw ArgumentError.value(conversationId, 'conversationId');
    }
    if (normalizedText.isEmpty) {
      throw ArgumentError.value(submitText, 'submitText');
    }
    final now = DateTime.now().toUtc();
    final receipt = StoryActionReceipt(
      id: 'action_${now.microsecondsSinceEpoch}',
      conversationId: conversation,
      source: source,
      label: normalizedLabel.isEmpty ? normalizedText : normalizedLabel,
      submitText: normalizedText,
      createdAt: now,
    );
    await _upsert(receipt);
    return receipt;
  }

  Future<StoryActionReceipt?> latestForConversation(
    String conversationId, {
    StoryActionReceiptStatus? status,
  }) async {
    final id = conversationId.trim();
    StoryActionReceipt? latest;
    for (final item in await readAll()) {
      if (item.conversationId != id) continue;
      if (status != null && item.status != status) continue;
      if (latest == null || item.createdAt.isAfter(latest.createdAt)) {
        latest = item;
      }
    }
    return latest;
  }

  Future<void> resolveLatestPending({
    required String conversationId,
    required String assistantMessageId,
    String? resultSummary,
  }) async {
    final receipt = await latestForConversation(
      conversationId,
      status: StoryActionReceiptStatus.pending,
    );
    if (receipt == null) return;
    await _upsert(
      receipt.copyWith(
        status: StoryActionReceiptStatus.resolved,
        resultSummary: resultSummary?.trim(),
        assistantMessageId: assistantMessageId,
        resolvedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> failLatestPending({
    required String conversationId,
    String? resultSummary,
  }) async {
    final receipt = await latestForConversation(
      conversationId,
      status: StoryActionReceiptStatus.pending,
    );
    if (receipt == null) return;
    await _upsert(
      receipt.copyWith(
        status: StoryActionReceiptStatus.failed,
        resultSummary: resultSummary?.trim(),
        resolvedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _upsert(StoryActionReceipt receipt) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StoryActionReceipt>[];
      var replaced = false;
      for (final item in items) {
        if (item.id == receipt.id) {
          if (!replaced) {
            next.add(receipt);
            replaced = true;
          }
        } else {
          next.add(item);
        }
      }
      if (!replaced) next.add(receipt);
      next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (next.length > 200) {
        next.removeRange(0, next.length - 200);
      }
      await writeAll(next);
    });
  }
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('invalid_story_action_receipt_$field');
  }
  return value.trim();
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
