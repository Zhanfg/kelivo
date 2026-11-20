/// A deterministic in-memory Agent quota admission controller.
/// This contract grants no model/tool capabilities and persists no credentials.
final class AgentQuotaLimits {
  const AgentQuotaLimits({
    required this.globalConcurrency,
    required this.providerConcurrency,
    required this.maxTokens,
    required this.maxCostMicros,
  }) : assert(globalConcurrency > 0),
       assert(providerConcurrency > 0),
       assert(maxTokens > 0),
       assert(maxCostMicros > 0);

  final int globalConcurrency;
  final int providerConcurrency;
  final int maxTokens;
  final int maxCostMicros;
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

/// Reservations are bounded and explicitly released, even on cancellation.
/// All mutation happens synchronously; callers serialize admission on isolate.
final class AgentQuotaPolicy {
  AgentQuotaPolicy(this.limits);
  final AgentQuotaLimits limits;
  final Map<String, AgentQuotaReservation> _active = {};
  int get activeCount => _active.length;
  int get reservedTokens => _active.values.fold(0, (n, r) => n + r.tokens);
  int get reservedCostMicros =>
      _active.values.fold(0, (n, r) => n + r.costMicros);

  bool reserve(AgentQuotaReservation request) {
    final safe = RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$');
    if (!safe.hasMatch(request.id) ||
        !safe.hasMatch(request.provider) ||
        request.tokens <= 0 ||
        request.costMicros < 0) {
      throw ArgumentError('Invalid quota reservation');
    }
    if (_active.containsKey(request.id)) {
      throw StateError('Duplicate reservation ID');
    }
    if (_active.length >= limits.globalConcurrency ||
        _active.values.where((r) => r.provider == request.provider).length >=
            limits.providerConcurrency ||
        request.tokens > limits.maxTokens - reservedTokens ||
        request.costMicros > limits.maxCostMicros - reservedCostMicros) {
      return false;
    }
    _active[request.id] = request;
    return true;
  }

  void release(String id) {
    if (_active.remove(id) == null) throw StateError('Unknown reservation');
  }

  /// No automatic retry or starvation guarantee; caller owns FIFO scheduling.
  bool get isSaturated => activeCount >= limits.globalConcurrency;
}
