import 'package:Kelivo/features/agent/orchestration/agent_quota_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AgentQuotaReservation request(int id, String provider, {int tokens = 1}) =>
      AgentQuotaReservation('stress_$id', provider, tokens, 1);

  test('bounded FIFO grants oldest queued task over newer provider', () {
    final quota = AgentQuotaPolicy(
      const AgentQuotaLimits(
        globalConcurrency: 1,
        providerConcurrency: 1,
        maxTokens: 32,
        maxCostMicros: 128,
        maxWaiting: 64,
      ),
    );
    expect(quota.enqueue(request(0, 'a')), isTrue);
    for (var n = 1; n <= 32; n++) {
      expect(quota.enqueue(request(n, n.isEven ? 'a' : 'b')), isFalse);
    }
    expect(quota.reserve(request(100, 'b')), isFalse);
    for (var n = 0; n <= 32; n++) {
      expect(quota.activeCount, 1);
      expect(quota.reservedTokens, 1);
      quota.release('stress_$n');
      final next = quota.takeGranted();
      if (n < 32) {
        expect(next.map((e) => e.id), ['stress_${n + 1}']);
      } else {
        expect(next, isEmpty);
      }
    }
    expect(quota.activeCount, 0);
    expect(quota.waitingCount, 0);
    expect(quota.reservedCostMicros, 0);
  });

  test('provider capacity and global budgets remain bounded under churn', () {
    final quota = AgentQuotaPolicy(
      const AgentQuotaLimits(
        globalConcurrency: 4,
        providerConcurrency: 2,
        maxTokens: 50,
        maxCostMicros: 200,
        providerMaxTokens: 25,
        providerMaxCostMicros: 100,
      ),
    );
    for (var round = 0; round < 50; round++) {
      expect(quota.reserve(request(round * 10, 'p', tokens: 12)), isTrue);
      expect(quota.reserve(request(round * 10 + 1, 'p', tokens: 12)), isTrue);
      expect(quota.reserve(request(round * 10 + 2, 'p')), isFalse);
      expect(quota.reserve(request(round * 10 + 3, 'q', tokens: 12)), isTrue);
      expect(quota.activeCount, 3);
      expect(quota.reservedTokens, 36);
      quota.release('stress_${round * 10}');
      quota.release('stress_${round * 10 + 1}');
      quota.release('stress_${round * 10 + 3}');
      expect(quota.reservedTokens, 0);
      expect(quota.reservedCostMicros, 0);
    }
  });

  test('failed reservation and cancelled waiting work do not leak budget', () {
    final quota = AgentQuotaPolicy(
      const AgentQuotaLimits(
        globalConcurrency: 1,
        providerConcurrency: 1,
        maxTokens: 10,
        maxCostMicros: 100,
        maxWaiting: 2,
      ),
    );
    expect(quota.enqueue(request(0, 'p', tokens: 10)), isTrue);
    expect(quota.enqueue(request(1, 'p')), isFalse);
    expect(quota.enqueue(request(2, 'q')), isFalse);
    expect(() => quota.enqueue(request(3, 'p')), throwsStateError);
    quota.cancelWaiting('stress_1');
    quota.release('stress_0');
    expect(quota.takeGranted().map((r) => r.id), ['stress_2']);
    quota.release('stress_2');
    expect(quota.reservedTokens, 0);
    expect(quota.waitingCount, 0);
  });

  test(
    'quota checks do not imply live Provider billing or distributed locks',
    () {
      final quota = AgentQuotaPolicy(
        const AgentQuotaLimits(
          globalConcurrency: 1,
          providerConcurrency: 1,
          maxTokens: 2,
          maxCostMicros: 3,
        ),
      );
      expect(
        () => quota.reserve(request(1, 'p', tokens: 3)),
        throwsArgumentError,
      );
      expect(quota.activeCount, 0);
    },
  );
}
