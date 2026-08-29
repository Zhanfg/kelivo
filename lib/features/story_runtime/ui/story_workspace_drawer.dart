import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/models/conversation.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../state/story_runtime_store.dart';
import 'story_conversation_mode_control.dart';
import 'story_mode_runtime_page.dart';

class StoryWorkspaceDrawer extends StatefulWidget {
  const StoryWorkspaceDrawer({
    super.key,
    required this.onSelectStory,
    required this.onNewStory,
  });

  final ValueChanged<String> onSelectStory;
  final Future<void> Function() onNewStory;

  @override
  State<StoryWorkspaceDrawer> createState() => _StoryWorkspaceDrawerState();
}

class _StoryWorkspaceDrawerState extends State<StoryWorkspaceDrawer> {
  String? _signature;
  Future<List<Conversation>>? _storiesFuture;

  Future<List<Conversation>> _storiesFor(
    BuildContext context,
    List<Conversation> conversations,
    int revision,
  ) {
    final signature =
        '$revision|${conversations.map((item) => '${item.id}:${item.updatedAt.millisecondsSinceEpoch}').join(',')}';
    if (_signature != signature || _storiesFuture == null) {
      _signature = signature;
      final store = StoryRuntimeStore(context.read<BusinessPreferences>());
      _storiesFuture =
          Future.wait(
            conversations.map((conversation) async {
              final session = await store.readOrDefault(conversation.id);
              return session.enabled ? conversation : null;
            }),
          ).then(
            (items) =>
                items.whereType<Conversation>().toList()
                  ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
          );
    }
    return _storiesFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    final chatService = context.watch<ChatService>();
    final conversations = chatService.getAllConversations();
    final currentId = chatService.currentConversationId;

    return Material(
      color: cs.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      zh ? '故事' : 'Stories',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: zh ? '新建故事' : 'New story',
                    onPressed: widget.onNewStory,
                    icon: const Icon(Lucide.Plus),
                  ),
                ],
              ),
            ),
            Divider(color: cs.outlineVariant.withValues(alpha: 0.35)),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: storyConversationModeRevision,
                builder: (context, revision, _) =>
                    FutureBuilder<List<Conversation>>(
                      future: _storiesFor(context, conversations, revision),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final stories = snapshot.data!;
                        if (stories.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                zh
                                    ? '还没有故事，点击右上角新建。'
                                    : 'No stories yet. Create one above.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: stories.length,
                          itemBuilder: (context, index) {
                            final story = stories[index];
                            final title = story.title.trim();
                            return ListTile(
                              selected: story.id == currentId,
                              leading: const Icon(Lucide.BookOpen),
                              title: Text(
                                title.isEmpty
                                    ? (zh ? '未命名故事' : 'Untitled story')
                                    : title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => widget.onSelectStory(story.id),
                            );
                          },
                        );
                      },
                    ),
              ),
            ),
            ListTile(
              leading: const Icon(Lucide.Settings),
              title: Text(zh ? '故事设置' : 'Story settings'),
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const StoryModeRuntimePage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
