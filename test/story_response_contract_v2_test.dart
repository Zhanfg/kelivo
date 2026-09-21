import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/parsing/story_response_contract.dart';

void main() {
  test('V2 sidecar is sparse and optional', () {
    expect(storyResponseContractV2, contains('Normally stop after the prose'));
    expect(storyResponseContractV2, contains('omit the sidecar entirely'));
    expect(
      storyResponseContractV2,
      isNot(contains('events must semantically mirror the visible prose')),
    );
  });
}
