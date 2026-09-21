import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/home/controllers/streaming_content_notifier.dart';

void main() {
  test('active SSE is classified as working', () {
    final now = DateTime(2026, 9, 22, 1, 0);
    final health = GenerationHealthData(
      phase: GenerationTransportPhase.sseStreaming,
      httpOpen: true,
      sseOpen: true,
      requestStartedAt: now.subtract(const Duration(seconds: 20)),
      lastNetworkEventAt: now.subtract(const Duration(seconds: 2)),
    );

    expect(health.classify(now), GenerationHealthClass.working);
  });

  test('silent SSE is suspected, not failed', () {
    final now = DateTime(2026, 9, 22, 1, 0);
    final health = GenerationHealthData(
      phase: GenerationTransportPhase.sseStreaming,
      httpOpen: true,
      sseOpen: true,
      requestStartedAt: now.subtract(const Duration(minutes: 1)),
      lastNetworkEventAt: now.subtract(const Duration(seconds: 31)),
    );

    expect(health.classify(now), GenerationHealthClass.suspectedStall);
  });

  test('tool execution remains working even without SSE events', () {
    final now = DateTime(2026, 9, 22, 1, 0);
    final health = GenerationHealthData(
      phase: GenerationTransportPhase.tool,
      httpOpen: true,
      sseOpen: true,
      activeToolName: 'search',
      lastNetworkEventAt: now.subtract(const Duration(minutes: 2)),
    );

    expect(health.classify(now), GenerationHealthClass.working);
  });

  test('retry backoff remains working', () {
    final now = DateTime(2026, 9, 22, 1, 0);
    final health = GenerationHealthData(
      phase: GenerationTransportPhase.retrying,
      retryStatus: RetryStatus(
        attempt: 1,
        maxRetries: 3,
        retryAt: now.add(const Duration(seconds: 4)),
      ),
    );

    expect(health.classify(now), GenerationHealthClass.working);
  });

  test('terminal provider error is failed', () {
    final health = GenerationHealthData(
      phase: GenerationTransportPhase.failed,
      errorText: 'socket closed',
    );

    expect(
      health.classify(DateTime(2026, 9, 22, 1, 0)),
      GenerationHealthClass.failed,
    );
  });
}
