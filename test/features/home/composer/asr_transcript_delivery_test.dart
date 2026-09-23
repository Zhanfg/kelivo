import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/asr/asr_service_options.dart';
import 'package:Kelivo/features/home/composer/asr_transcript_delivery.dart';

void main() {
  test('classifies final-only local ASR separately from live preview', () {
    final delivery = asrTranscriptDeliveryForKind(AsrServiceKind.sherpaOnnx);
    expect(delivery, AsrTranscriptDelivery.finalOnly);
    expect(delivery.supportsLivePreview, isFalse);
    expect(delivery.isRealtime, isFalse);
  });

  test(
    'classifies HTTP segment recognizers as progressive segmented preview',
    () {
      for (final kind in [AsrServiceKind.mimo, AsrServiceKind.step]) {
        final delivery = asrTranscriptDeliveryForKind(kind);
        expect(delivery, AsrTranscriptDelivery.segmented);
        expect(delivery.supportsLivePreview, isTrue);
        expect(delivery.isRealtime, isFalse);
      }
    },
  );

  test('classifies system and websocket recognizers as realtime preview', () {
    for (final kind in [
      AsrServiceKind.system,
      AsrServiceKind.openAiRealtime,
      AsrServiceKind.dashScope,
      AsrServiceKind.qwenAudio,
      AsrServiceKind.volcengine,
    ]) {
      final delivery = asrTranscriptDeliveryForKind(kind);
      expect(delivery, AsrTranscriptDelivery.streaming);
      expect(delivery.supportsLivePreview, isTrue);
      expect(delivery.isRealtime, isTrue);
    }
  });
}
