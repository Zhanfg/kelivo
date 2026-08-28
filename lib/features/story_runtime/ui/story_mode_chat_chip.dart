import 'package:flutter/material.dart';

/// Compatibility placeholder for the former floating Story quick-tools strip.
///
/// Story actions now live in the native composer `+` sheet. Keeping this widget
/// as a zero-size surface avoids a second navigation hierarchy above the input
/// bar and prevents message content from being covered by an unmeasured Story
/// toolbar.
class StoryModeChatChip extends StatelessWidget {
  const StoryModeChatChip({super.key, required this.conversationId});

  final String? conversationId;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
