import '../../../core/services/asr/asr_service_options.dart';

enum AsrTranscriptDelivery { finalOnly, segmented, streaming }

extension AsrTranscriptDeliveryX on AsrTranscriptDelivery {
  /// Whether recording can expose useful transcript text before the user ends
  /// the session. Segmented services update less frequently than realtime ones
  /// but still provide progressive preview text.
  bool get supportsLivePreview => this != AsrTranscriptDelivery.finalOnly;

  bool get isRealtime => this == AsrTranscriptDelivery.streaming;
}

AsrTranscriptDelivery asrTranscriptDeliveryFor(AsrServiceOptions options) {
  return asrTranscriptDeliveryForKind(options.kind);
}

AsrTranscriptDelivery asrTranscriptDeliveryForKind(AsrServiceKind kind) {
  return switch (kind) {
    AsrServiceKind.sherpaOnnx => AsrTranscriptDelivery.finalOnly,
    AsrServiceKind.mimo || AsrServiceKind.step =>
      AsrTranscriptDelivery.segmented,
    AsrServiceKind.system ||
    AsrServiceKind.openAiRealtime ||
    AsrServiceKind.dashScope ||
    AsrServiceKind.qwenAudio ||
    AsrServiceKind.volcengine => AsrTranscriptDelivery.streaming,
  };
}
