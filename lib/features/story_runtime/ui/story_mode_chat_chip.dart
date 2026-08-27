import 'package:flutter/widgets.dart';

/// Compatibility shim kept while older Home layouts still reference the
/// previous input-area Story chip. Story Mode selection now lives in the native
/// chat header, so this widget intentionally renders nothing.
class StoryModeChatChip extends StatelessWidget {
  const StoryModeChatChip({super.key, required this.conversationId});

  final String? conversationId;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
