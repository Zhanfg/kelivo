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
}
