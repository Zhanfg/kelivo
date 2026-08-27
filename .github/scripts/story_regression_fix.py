from pathlib import Path


message_path = Path("lib/features/home/services/message_generation_service.dart")
message_text = message_path.read_text()
start_marker = "    StoryBreakArmorMode("
end_marker = "      _injectStoryMvpSystemPrompt(apiMessages, storyPrompt);\n    }\n"
start = message_text.find(start_marker)
end_start = message_text.find(end_marker, start)
if start < 0 or end_start < 0:
    raise SystemExit("message_generation_service.dart: Story injection block not found")
end = end_start + len(end_marker)
new_story = """    BusinessPreferences? storyPreferences;
    try {
      storyPreferences = contextProvider.read<BusinessPreferences>();
    } on ProviderNotFoundException {
      // Story Runtime is opt-in. Plain chat/test contexts do not have to
      // register its persistence provider.
      storyPreferences = null;
    }
    if (storyPreferences != null) {
      StoryBreakArmorMode(storyPreferences).prependToSystemPrompt(apiMessages);

      final storyConversationId = (currentConversation?.id ?? '').trim();
      final storyAssistantId = (assistantId ?? assistant?.id ?? '').trim();
      if (storyConversationId.isNotEmpty && storyAssistantId.isNotEmpty) {
        final storyPrompt = await StoryMvpPromptService(storyPreferences).build(
          conversationId: storyConversationId,
          assistantId: storyAssistantId,
        );
        _injectStoryMvpSystemPrompt(apiMessages, storyPrompt);
      }
    }
"""
message_path.write_text(message_text[:start] + new_story + message_text[end:])

for path in [
    "test/core/services/backup/restore_bundle_mover_test.dart",
    "test/core/services/backup/restore_receipt_test.dart",
]:
    file = Path(path)
    text = file.read_text()
    old = "const ['upload', 'images', 'avatars', 'fonts']"
    if old not in text:
        raise SystemExit(f"{path}: legacy asset-root fixture not found")
    file.write_text(
        text.replace(
            old,
            "const ['upload', 'images', 'avatars', 'fonts', 'story_skills']",
        )
    )

for path in [
    "test/core/services/backup/restore_previous_builder_test.dart",
    "test/core/services/backup/restore_previous_plan_test.dart",
]:
    file = Path(path)
    lines = file.read_text().splitlines(keepends=True)
    out: list[str] = []
    additions = 0
    for index, line in enumerate(lines):
        out.append(line)
        if "'fonts': RestorePreviousAssetRootState." not in line:
            continue
        next_line = lines[index + 1] if index + 1 < len(lines) else ""
        if "'story_skills': RestorePreviousAssetRootState." in next_line:
            continue
        indent = line[: len(line) - len(line.lstrip())]
        out.append(
            f"{indent}'story_skills': RestorePreviousAssetRootState.missing,\n"
        )
        additions += 1
    if additions == 0:
        raise SystemExit(f"{path}: no root-state fixture updated")
    file.write_text("".join(out))

builder = Path("test/core/services/backup/restore_previous_builder_test.dart")
text = builder.read_text().replace(
    "describes selected database and all four asset roots",
    "describes selected database and all five asset roots",
)
builder.write_text(text)
