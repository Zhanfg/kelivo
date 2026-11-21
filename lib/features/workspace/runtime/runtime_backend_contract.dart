/// Platform-neutral runtime contract. No platform backend is implemented here.
enum RuntimeCapability { exec, pty, files, processes }

enum RuntimeResultStatus { success, unsupported, denied, failed }

final class RuntimeResult<T> {
  const RuntimeResult(this.status, {this.value, this.reason});
  final RuntimeResultStatus status;
  final T? value;
  final String? reason;
  bool get succeeded => status == RuntimeResultStatus.success;
}

final class RuntimeRequest {
  RuntimeRequest({
    required this.id,
    required this.environmentId,
    required this.operation,
    required Map<String, String> arguments,
  }) : arguments = Map.unmodifiable(arguments) {
    final idPattern = RegExp(r'^[a-zA-Z0-9_.:-]{1,128}$');
    if (!idPattern.hasMatch(id) ||
        !idPattern.hasMatch(environmentId) ||
        arguments.length > 16 ||
        arguments.entries.any(
          (entry) => entry.key.length > 64 || entry.value.length > 256,
        )) {
      throw ArgumentError('Invalid runtime request');
    }
  }
  final String id;
  final String environmentId;
  final RuntimeCapability operation;
  final Map<String, String> arguments;
}

/// Implementations must perform their own permission checks, isolation,
/// cancellation and I/O limits. A request is not an authorization token.
abstract interface class RuntimeBackend {
  String get backendId;
  Set<RuntimeCapability> get capabilities;
  Future<RuntimeResult<String>> run(RuntimeRequest request);
}

/// Deterministic test implementation; never invokes shell or OS services.
final class MockRuntimeBackend implements RuntimeBackend {
  MockRuntimeBackend({
    required this.backendId,
    Set<RuntimeCapability> capabilities = const {},
  }) : capabilities = Set.unmodifiable(capabilities);
  @override
  final String backendId;
  @override
  final Set<RuntimeCapability> capabilities;
  final List<String> recordedRequests = [];
  @override
  Future<RuntimeResult<String>> run(RuntimeRequest request) async {
    if (!capabilities.contains(request.operation)) {
      return const RuntimeResult(
        RuntimeResultStatus.unsupported,
        reason: 'Runtime capability unsupported',
      );
    }
    recordedRequests.add(request.id);
    return RuntimeResult(
      RuntimeResultStatus.success,
      value: 'mock:${request.operation.name}',
    );
  }
}
