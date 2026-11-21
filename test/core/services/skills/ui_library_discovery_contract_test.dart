import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/skills/ui_library_discovery_contract.dart';

void main() {
  final now = DateTime.utc(2026, 11, 21);
  UiLibraryCandidate candidate({
    UiLibrarySource source = UiLibrarySource.pubDev,
    UiLibraryDelivery delivery = UiLibraryDelivery.compiledSdk,
    String? license = 'MIT',
    String platform = 'android',
    Uri? url,
    DateTime? updated,
    bool installScript = false,
  }) => UiLibraryCandidate(
    id: 'example-ui',
    source: source,
    url: url ?? Uri.parse('https://pub.dev/packages/example_ui'),
    license: license,
    targetPlatforms: {platform},
    lastUpdated: updated ?? now.subtract(const Duration(days: 5)),
    dependencies: const ['flutter >=3.0.0'],
    delivery: delivery,
    hasInstallationScript: installScript,
  );

  const policy = UiLibraryDiscoveryContract();

  test('SDK candidates only produce review plans and require compilation', () {
    final review = policy.review(
      candidate(),
      targetPlatform: 'android',
      now: now,
    );
    expect(review.decision, UiLibraryDecision.review);
    expect(review.requiresRebuild, isTrue);
    expect(review.eligibleForAutomaticExecution, isFalse);
    expect(review.adaptationSteps.join(' '), contains('rebuild'));
  });

  test('registry runtime extension is not compiled SDK', () {
    final review = policy.review(
      candidate(
        source: UiLibrarySource.extensionRegistry,
        delivery: UiLibraryDelivery.runtimeExtension,
      ),
      targetPlatform: 'android',
      now: now,
    );
    expect(review.requiresRebuild, isFalse);
    expect(review.adaptationSteps.join(' '), contains('sandbox'));
    expect(review.eligibleForAutomaticExecution, isFalse);
  });

  test('unknown license, stale maintenance and wrong platform fail closed', () {
    final review = policy.review(
      candidate(
        license: null,
        platform: 'ios',
        updated: now.subtract(const Duration(days: 900)),
      ),
      targetPlatform: 'android',
      now: now,
    );
    expect(review.decision, UiLibraryDecision.reject);
    expect(review.reasons, contains('unknown license'));
    expect(review.reasons, contains('unsupported target platform'));
    expect(review.reasons, contains('unverified maintenance freshness'));
  });

  test('insecure URL and remote install script cannot pass review', () {
    final review = policy.review(
      candidate(
        url: Uri.parse('http://127.0.0.1/install'),
        installScript: true,
      ),
      targetPlatform: 'android',
      now: now,
    );
    expect(review.decision, UiLibraryDecision.reject);
    expect(review.reasons, contains('non-HTTPS source'));
    expect(review.reasons.join(' '), contains('manual security review'));
  });

  test('source catalog distinguishes four providers', () {
    expect(
      UiLibrarySource.values,
      containsAll([
        UiLibrarySource.pubDev,
        UiLibrarySource.npm,
        UiLibrarySource.github,
        UiLibrarySource.extensionRegistry,
      ]),
    );
  });
}
