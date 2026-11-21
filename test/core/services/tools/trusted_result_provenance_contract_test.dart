import 'package:Kelivo/core/services/tools/trusted_result_provenance_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TrustedResultProvenance tag(
    TrustedResultOrigin origin, {
    bool verified = false,
    Map<String, String> metadata = const {},
  }) => TrustedResultProvenance(
    origin: origin,
    sourceId: 'tool:read',
    environmentId: 'workspace:one',
    authorizationScope: 'task:approved',
    observedAt: DateTime.utc(2026, 11, 21),
    hostVerified: verified,
    metadata: metadata,
  );

  test('only host-verified executed tool evidence is trusted', () {
    expect(
      tag(TrustedResultOrigin.executedTool, verified: true).decision,
      TrustedResultDecision.trustedEvidence,
    );
    expect(
      tag(TrustedResultOrigin.executedTool).decision,
      TrustedResultDecision.unverified,
    );
    expect(
      tag(TrustedResultOrigin.storedCache, verified: true).decision,
      TrustedResultDecision.unverified,
    );
    expect(
      tag(TrustedResultOrigin.modelGenerated, verified: true).decision,
      TrustedResultDecision.unverified,
    );
  });

  test('rejects missing origin identifiers and credential-shaped keys', () {
    expect(
      () => tag(
        TrustedResultOrigin.executedTool,
        metadata: {'api_token': 'redacted'},
      ),
      throwsArgumentError,
    );
    expect(
      () => TrustedResultProvenance(
        origin: TrustedResultOrigin.executedTool,
        sourceId: '../file',
        environmentId: 'workspace:one',
        authorizationScope: 'task:approved',
        observedAt: DateTime.utc(2026),
        hostVerified: true,
      ),
      throwsArgumentError,
    );
  });

  test('immutable sanitized metadata and UTC timestamps', () {
    final map = <String, String>{'host': 'android'};
    final receipt = tag(
      TrustedResultOrigin.executedTool,
      verified: true,
      metadata: map,
    );
    map['host'] = 'changed';
    expect(receipt.metadata['host'], 'android');
    expect(() => receipt.metadata['host'] = 'bad', throwsUnsupportedError);
    expect(receipt.toRedactedJson()['origin'], 'executedTool');
    expect(receipt.observedAt.isUtc, isTrue);
  });
}
