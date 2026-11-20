import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/agent/orchestration/agent_quota_policy.dart';

void main() {
  final limits = AgentQuotaLimits(
    globalConcurrency: 2,
    providerConcurrency: 1,
    maxTokens: 100,
    maxCostMicros: 1000,
  );
  AgentQuotaReservation request(
    String id,
    String provider, {
    int tokens = 20,
    int cost = 100,
  }) => AgentQuotaReservation(id, provider, tokens, cost);

  test('global and per-provider concurrency admission', () {
    final policy = AgentQuotaPolicy(limits);
    expect(policy.reserve(request('a', 'one')), isTrue);
    expect(policy.reserve(request('b', 'one')), isFalse);
    expect(policy.reserve(request('c', 'two')), isTrue);
    expect(policy.isSaturated, isTrue);
    expect(policy.reserve(request('d', 'three')), isFalse);
  });

  test('token and cost budgets fail closed', () {
    final policy = AgentQuotaPolicy(limits);
    expect(policy.reserve(request('a', 'one', tokens: 95)), isTrue);
    expect(policy.reserve(request('b', 'two', tokens: 6)), isFalse);
    expect(policy.reserve(request('c', 'two', tokens: 5, cost: 901)), isFalse);
  });

  test('release returns all reserved resources', () {
    final policy = AgentQuotaPolicy(limits);
    policy.reserve(request('a', 'one'));
    expect(policy.reservedTokens, 20);
    policy.release('a');
    expect(policy.reservedTokens, 0);
    expect(policy.reservedCostMicros, 0);
    expect(policy.reserve(request('b', 'one')), isTrue);
  });

  test('duplicate IDs and unknown releases are rejected', () {
    final policy = AgentQuotaPolicy(limits);
    policy.reserve(request('a', 'one'));
    expect(() => policy.reserve(request('a', 'two')), throwsStateError);
    expect(() => policy.release('missing'), throwsStateError);
  });

  test('negative, zero or unsafe requests rejected', () {
    final policy = AgentQuotaPolicy(limits);
    expect(() => policy.reserve(request('bad id', 'p')), throwsArgumentError);
    expect(
      () => policy.reserve(request('a', 'p', tokens: 0)),
      throwsArgumentError,
    );
    expect(
      () => policy.reserve(request('a', 'p', cost: -1)),
      throwsArgumentError,
    );
  });

  test('provider token and cost budgets apply independently', () {
    final quota = AgentQuotaPolicy(
      const AgentQuotaLimits(
        globalConcurrency: 4,
        providerConcurrency: 3,
        maxTokens: 200,
        maxCostMicros: 2000,
        providerMaxTokens: 50,
        providerMaxCostMicros: 500,
      ),
    );
    expect(quota.reserve(request('a', 'p', tokens: 40, cost: 400)), isTrue);
    expect(quota.reserve(request('b', 'p', tokens: 11)), isFalse);
    expect(quota.reserve(request('c', 'p', tokens: 10, cost: 101)), isFalse);
    expect(quota.reserve(request('d', 'q', tokens: 50, cost: 500)), isTrue);
  });

  test('bounded FIFO queue admits older requests on release', () {
    final policy = AgentQuotaPolicy(
      const AgentQuotaLimits(
        globalConcurrency: 1,
        providerConcurrency: 1,
        maxTokens: 100,
        maxCostMicros: 1000,
        maxWaiting: 2,
      ),
    );
    expect(policy.enqueue(request('a', 'p')), isTrue);
    expect(policy.enqueue(request('b', 'p')), isFalse);
    expect(policy.enqueue(request('c', 'p')), isFalse);
    expect(() => policy.enqueue(request('d', 'p')), throwsStateError);
    expect(policy.reserve(request('new', 'other')), isFalse);
    policy.release('a');
    expect(policy.takeGranted().map((r) => r.id), ['b']);
    expect(policy.waitingCount, 1);
    policy.release('b');
    expect(policy.takeGranted().map((r) => r.id), ['c']);
    expect(policy.waitingCount, 0);
  });

  test('cancelled waiting work releases queue slot', () {
    final policy = AgentQuotaPolicy(
      const AgentQuotaLimits(
        globalConcurrency: 1,
        providerConcurrency: 1,
        maxTokens: 100,
        maxCostMicros: 1000,
      ),
    );
    policy.enqueue(request('a', 'p'));
    policy.enqueue(request('b', 'p'));
    policy.cancelWaiting('b');
    expect(policy.waitingCount, 0);
    expect(() => policy.cancelWaiting('b'), throwsStateError);
    policy.release('a');
    expect(policy.takeGranted(), isEmpty);
  });
}
