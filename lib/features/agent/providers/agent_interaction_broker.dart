import 'dart:async';

import 'package:flutter/foundation.dart';

enum AgentInteractionMethod { select, confirm, input, editor }

class AgentInteractionRequest {
  const AgentInteractionRequest({
    required this.id,
    required this.taskId,
    required this.method,
    required this.title,
    required this.createdAt,
    this.message,
    this.options = const <String>[],
    this.placeholder,
    this.prefill,
    this.timeoutMs,
  });

  final String id;
  final String taskId;
  final AgentInteractionMethod method;
  final String title;
  final String? message;
  final List<String> options;
  final String? placeholder;
  final String? prefill;
  final int? timeoutMs;
  final DateTime createdAt;
}

class AgentInteractionBroker extends ChangeNotifier {
  final Map<String, AgentInteractionRequest> _pending =
      <String, AgentInteractionRequest>{};
  final Map<String, Completer<Map<String, dynamic>>> _waiters =
      <String, Completer<Map<String, dynamic>>>{};
  final Map<String, Timer> _timers = <String, Timer>{};

  List<AgentInteractionRequest> get pending {
    final items = _pending.values.toList(growable: false);
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  AgentInteractionRequest? forTask(String taskId) {
    for (final request in _pending.values) {
      if (request.taskId == taskId) return request;
    }
    return null;
  }

  Future<Map<String, dynamic>> request(
    String taskId,
    Map<String, dynamic> event,
  ) {
    final id = event['id']?.toString() ?? '';
    final methodName = event['method']?.toString() ?? '';
    final method = AgentInteractionMethod.values.firstWhere(
      (candidate) => candidate.name == methodName,
      orElse: () =>
          throw StateError('unsupported_agent_interaction:$methodName'),
    );
    if (id.isEmpty) throw StateError('agent_interaction_missing_id');

    cancelForTask(taskId);

    final completer = Completer<Map<String, dynamic>>();
    final timeoutMs = (event['timeout'] as num?)?.toInt();
    _pending[id] = AgentInteractionRequest(
      id: id,
      taskId: taskId,
      method: method,
      title: event['title']?.toString() ?? '',
      message: event['message']?.toString(),
      options: event['options'] is List
          ? <String>[
              for (final value in event['options'] as List) value.toString(),
            ]
          : const <String>[],
      placeholder: event['placeholder']?.toString(),
      prefill: event['prefill']?.toString(),
      timeoutMs: timeoutMs,
      createdAt: DateTime.now().toUtc(),
    );
    _waiters[id] = completer;

    if (timeoutMs != null && timeoutMs > 0) {
      _timers[id] = Timer(
        Duration(milliseconds: timeoutMs + 100),
        () => cancel(id),
      );
    }
    notifyListeners();
    return completer.future;
  }

  void select(String id, String value) {
    _resolve(id, <String, dynamic>{'value': value});
  }

  void confirm(String id, bool confirmed) {
    _resolve(id, <String, dynamic>{'confirmed': confirmed});
  }

  void submitText(String id, String value) {
    _resolve(id, <String, dynamic>{'value': value});
  }

  void cancel(String id) {
    _resolve(id, const <String, dynamic>{'cancelled': true});
  }

  void cancelForTask(String taskId) {
    final ids = <String>[
      for (final entry in _pending.entries)
        if (entry.value.taskId == taskId) entry.key,
    ];
    for (final id in ids) {
      cancel(id);
    }
  }

  void _resolve(String id, Map<String, dynamic> result) {
    final completer = _waiters.remove(id);
    if (completer == null) return;
    _timers.remove(id)?.cancel();
    _pending.remove(id);
    if (!completer.isCompleted) {
      completer.complete(<String, dynamic>{
        'type': 'extension_ui_response',
        'id': id,
        ...result,
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    final ids = _waiters.keys.toList(growable: false);
    for (final id in ids) {
      cancel(id);
    }
    super.dispose();
  }
}
