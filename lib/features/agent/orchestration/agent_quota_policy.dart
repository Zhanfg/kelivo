/// In-memory, single-isolate bounded admission policy for Agent work.
/// It grants no tools or capabilities and retains no prompts or credentials.
final class AgentQuotaLimits {
  const AgentQuotaLimits({
    required this.globalConcurrency,
    required this.providerConcurrency,
    required this.maxTokens,
    required this.maxCostMicros,
    this.providerMaxTokens,
    this.providerMaxCostMicros,
    this.maxWaiting = 128,
  }) : assert(globalConcurrency > 0),
       assert(providerConcurrency > 0),
       assert(maxTokens > 0),
       assert(maxCostMicros > 0),
       assert(providerMaxTokens == null || providerMaxTokens > 0),
       assert(providerMaxCostMicros == null || providerMaxCostMicros > 0),
       assert(maxWaiting > 0);

  final int globalConcurrency;
  final int providerConcurrency;
  final int maxTokens;
  final int maxCostMicros;
  final int? providerMaxTokens;
  final int? providerMaxCostMicros;
  final int maxWaiting;
}

final class AgentQuotaReservation {
  const AgentQuotaReservation(
    this.id,
    this.provider,
    this.tokens,
    this.costMicros,
  );
  final String id;
  final String provider;
  final int tokens;
  final int costMicros;
}

/// Explicitly released reservations, with optional strict FIFO admission.
/// FIFO avoids newer callers overtaking older waiting requests; an idle worker
/// can still be blocked by the head's provider budget (head-of-line blocking).
/// This is not a durable distributed semaphore or a preemption mechanism.
final class AgentQuotaPolicy {
  AgentQuotaPolicy(this.limits);
  final AgentQuotaLimits limits;
  final Map<String, AgentQuotaReservation> _active = {};
  final List<AgentQuotaReservation> _waiting = [];
  final List<AgentQuotaReservation> _newGrants = [];

  int get activeCount => _active.length;
  int get waitingCount => _waiting.length;
  bool get isSaturated => activeCount >= limits.globalConcurrency;
  int get reservedTokens => _active.values.fold(0, (n, r) => n + r.tokens);
  int get reservedCostMicros =>
      _active.values.fold(0, (n, r) => n + r.costMicros);

  void _validate(AgentQuotaReservation request) {
    final safe = RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$');
    if (!safe.hasMatch(request.id) ||
        !safe.hasMatch(request.provider) ||
        request.tokens <= 0 ||
        request.costMicros < 0 ||
        request.tokens > limits.maxTokens ||
        request.costMicros > limits.maxCostMicros ||
        request.tokens > (limits.providerMaxTokens ?? limits.maxTokens) ||
        request.costMicros >
            (limits.providerMaxCostMicros ?? limits.maxCostMicros)) {
      throw ArgumentError('Invalid or impossible quota reservation');
    }
    if (_active.containsKey(request.id) ||
        _waiting.any((r) => r.id == request.id)) {
      throw StateError('Duplicate reservation ID');
    }
  }

  bool _canAdmit(AgentQuotaReservation request) {
    final providerActive = _active.values
        .where((r) => r.provider == request.provider)
        .toList();
    final providerTokens = providerActive.fold(0, (n, r) => n + r.tokens);
    final providerCost = providerActive.fold(0, (n, r) => n + r.costMicros);
    return activeCount < limits.globalConcurrency &&
        providerActive.length < limits.providerConcurrency &&
        request.tokens <= limits.maxTokens - reservedTokens &&
        request.costMicros <= limits.maxCostMicros - reservedCostMicros &&
        request.tokens <=
            (limits.providerMaxTokens ?? limits.maxTokens) - providerTokens &&
        request.costMicros <=
            (limits.providerMaxCostMicros ?? limits.maxCostMicros) -
                providerCost;
  }

  /// One-shot direct admission. Cannot bypass an older FIFO queue.
  bool reserve(AgentQuotaReservation request) {
    _validate(request);
    if (_waiting.isNotEmpty || !_canAdmit(request)) return false;
    _active[request.id] = request;
    return true;
  }

  /// Bounded FIFO request; returns true if admitted immediately.
  /// A queued request is granted when resources are released.
  bool enqueue(AgentQuotaReservation request) {
    _validate(request);
    if (_waiting.isEmpty && _canAdmit(request)) {
      _active[request.id] = request;
      return true;
    }
    if (_waiting.length >= limits.maxWaiting) {
      throw StateError('Waiting queue is full');
    }
    _waiting.add(request);
    return false;
  }

  void release(String id) {
    if (_active.remove(id) == null) throw StateError('Unknown reservation');
    _drain();
  }

  void cancelWaiting(String id) {
    final index = _waiting.indexWhere((r) => r.id == id);
    if (index < 0) throw StateError('Unknown waiting reservation');
    _waiting.removeAt(index);
    _drain();
  }

  void _drain() {
    while (_waiting.isNotEmpty && _canAdmit(_waiting.first)) {
      final reservation = _waiting.removeAt(0);
      _active[reservation.id] = reservation;
      _newGrants.add(reservation);
    }
  }

  List<AgentQuotaReservation> takeGranted() {
    final result = List<AgentQuotaReservation>.unmodifiable(_newGrants);
    _newGrants.clear();
    return result;
  }
}
