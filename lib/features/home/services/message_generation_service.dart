import 'package:Kelivo/core/providers/external_mounts_provider.dart';
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/message_part.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/model_spec.dart';
import '../../../core/models/reasoning_request.dart';
import '../../../core/models/skills_binding.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/database/business_preferences.dart';
import '../../../core/services/api/builtin_tools.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/providers/openai/responses_history.dart';
import '../../../core/services/api/reasoning/reasoning_dialects.dart';
import '../../../core/services/model_spec/model_spec_resolver.dart';
import '../../../core/providers/workspace_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/chat/document_text_extractor.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/services/logging/context_logger.dart';
import '../../../core/services/logging/context_log_models.dart';
import '../../../core/services/skills/skills_service.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../core/services/mcp/mcp_tool_service.dart';
import '../../../core/services/workspace/workspace_tools_service.dart';
import '../../../core/utils/multimodal_input_utils.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../utils/assistant_regex.dart';
import '../../../core/models/assistant_regex.dart';
import '../../story_runtime/context/story_context_resource_compiler.dart';
import '../../story_runtime/context/story_context_resources.dart';
import '../../story_runtime/orchestration/story_break_armor_mode.dart';
import '../../story_runtime/orchestration/story_runtime_prompt_service.dart';
import '../../story_runtime/serialization/story_serialization_tools.dart';
import '../controllers/stream_controller.dart' as stream_ctrl;
import '../controllers/generation_controller.dart';
import 'ask_user_interaction_service.dart';
import 'context_assembly.dart';
import 'context_usage_service.dart';
import 'message_builder_service.dart';
import 'tool_approval_service.dart';
import '../utils/model_display_helper.dart';

/// Callback types for UI updates from MessageGenerationService
typedef OnMessagesChanged = void Function();
typedef OnConversationLoadingChanged =
    void Function(String conversationId, bool loading);
typedef OnScrollToBottom = void Function();
typedef OnShowError = void Function(String message);
typedef OnShowWarning = void Function(String message);

const String conversationIdHeaderName = 'X-Conversation-Id';
const String _conversationIdHeaderNameLower = 'x-conversation-id';

Map<String, String>? buildConversationRequestHeaders({
  required String conversationId,
  Map<String, String>? customHeaders,
}) {
  final headers = <String, String>{
    if (customHeaders != null)
      for (final entry in customHeaders.entries)
        if (entry.key.toLowerCase() != _conversationIdHeaderNameLower)
          entry.key: entry.value,
  };
  final normalizedConversationId = conversationId.trim();
  if (normalizedConversationId.isNotEmpty) {
    headers[conversationIdHeaderName] = normalizedConversationId;
  }
  return headers.isEmpty ? null : headers;
}

/// Result of preparing a message generation
class UnprocessedRequestContext {
  UnprocessedRequestContext({
    required this.apiMessages,
    required this.toolDefs,
    required this.hasBuiltInSearch,
    required this.workspaceContext,
    required this.mcpRouteSnapshot,
    required this.workspaceAttachments,
    required this.cfg,
  });

  final List<Map<String, dynamic>> apiMessages;
  final List<Map<String, dynamic>> toolDefs;
  final bool hasBuiltInSearch;
  final WorkspaceToolContext? workspaceContext;
  final McpToolRouteSnapshot? mcpRouteSnapshot;
  final List<AttachmentInfo> workspaceAttachments;
  final ProviderConfig cfg;
}

class PreparedGeneration {
  final List<Map<String, dynamic>> apiMessages;
  final List<Map<String, dynamic>> toolDefs;
  final ToolCallHandler? onToolCall;
  final bool hasBuiltInSearch;
  final List<String> lastUserImagePaths;
  final Object? contextUsageConfiguration;
  final int? contextUsageRevision;

  PreparedGeneration({
    required this.apiMessages,
    required this.toolDefs,
    this.onToolCall,
    required this.hasBuiltInSearch,
    required this.lastUserImagePaths,
    this.contextUsageConfiguration,
    this.contextUsageRevision,
  });
}

/// Service for handling message generation orchestration.
///
/// This service coordinates:
/// - Message creation (user + assistant placeholder)
/// - API message preparation with all injections
/// - Stream execution and management
/// - Reasoning state initialization
///
/// UI updates are communicated through callbacks to maintain separation.
class MessageGenerationService {
  MessageGenerationService({
    required this.chatService,
    required this.messageBuilderService,
    required this.generationController,
    required this.streamController,
    required this.contextProvider,
  });

  final ChatService chatService;
  final MessageBuilderService messageBuilderService;
  final GenerationController generationController;
  final stream_ctrl.StreamController streamController;
  final BuildContext contextProvider;

  // Callbacks for UI updates (set by home_page)
  OnMessagesChanged? onMessagesChanged;
  OnConversationLoadingChanged? onConversationLoadingChanged;
  OnScrollToBottom? onScrollToBottom;
  OnShowError? onShowError;
  OnShowWarning? onShowWarning;

  /// Called when file processing starts for the assistant message [messageId].
  void Function(String messageId)? onFileProcessingStarted;

  /// Called when file processing finishes. A null [messageId] clears whichever
  /// message currently owns the indicator (error/cancel cleanup paths).
  void Function(String? messageId)? onFileProcessingFinished;

  /// Check if reasoning is enabled for given budget
  bool isReasoningEnabled(ReasoningRequest r) {
    return r.level != ReasoningLevel.off;
  }

  void _injectStoryRuntimeSystemPrompt(
    List<Map<String, dynamic>> apiMessages,
    String? storyPrompt,
  ) {
    final prompt = (storyPrompt ?? '').trim();
    if (prompt.isEmpty) return;
    final systemIndex = apiMessages.indexWhere(
      (message) => (message['role'] ?? '').toString() == 'system',
    );
    if (systemIndex == -1) {
      apiMessages.insert(0, <String, dynamic>{
        'role': 'system',
        'content': prompt,
      });
      return;
    }
    final existing = (apiMessages[systemIndex]['content'] ?? '')
        .toString()
        .trim();
    apiMessages[systemIndex]['content'] = existing.isEmpty
        ? prompt
        : '$existing\n\n$prompt';
  }

  List<Map<String, dynamic>> _storySerializationToolDefinitions(
    ProviderKind kind,
  ) {
    return StorySerializationTools.definitions()
        .map((definition) {
          final normalized = Map<String, dynamic>.from(definition);
          final function = Map<String, dynamic>.from(
            normalized['function'] as Map,
          );
          final parameters = Map<String, dynamic>.from(
            function['parameters'] as Map,
          );
          function['parameters'] =
              GenerationController.sanitizeToolParametersForProvider(
                parameters,
                kind,
              );
          normalized['function'] = function;
          return normalized;
        })
        .toList(growable: false);
  }

  /// Prepare API messages with all injections applied.
  /// [requiredAttachmentMessageId] identifies a new submission; retries and
  /// historical context can legitimately reference attachments since removed.
  Future<PreparedGeneration> prepareApiMessagesWithInjections({
    required List<ChatMessage> messages,
    required Map<String, int> versionSelections,
    required Conversation? currentConversation,
    required SettingsProvider settings,
    required Assistant? assistant,
    required String? assistantId,
    required String providerKey,
    required String modelId,
    String? requiredAttachmentMessageId,
    bool syncWorkspaceAttachments = true,
    bool persistWorldBookActivation = true,
    void Function(int before, int after)? onWorldBookActivationPersisted,
  }) async {
    final cfg = settings
        .getProviderConfig(providerKey)
        .forModelProtocol(modelId);
    final kind = ProviderConfig.classify(
      providerKey,
      explicitType: cfg.providerType,
    );
    final includeToolMessages = switch (kind) {
      ProviderKind.openai || ProviderKind.claude || ProviderKind.google => true,
    };
    WorkspaceProvider? workspaceProvider;
    WorkspaceRuntimeProvider? runtimeProvider;
    ExternalMountsProvider? externalMounts;
    try {
      workspaceProvider = contextProvider.read<WorkspaceProvider>();
      runtimeProvider = contextProvider.read<WorkspaceRuntimeProvider>();
      externalMounts = contextProvider.read<ExternalMountsProvider?>();
    } catch (_) {}

    final apiMessages = messageBuilderService.buildApiMessages(
      messages: messages,
      versionSelections: versionSelections,
      currentConversation: currentConversation,
      includeToolMessages: includeToolMessages,
      preserveToolTurns: kind == ProviderKind.openai,
      claudeSource: kind == ProviderKind.claude
          ? (providerId: providerKey, modelId: modelId)
          : null,
      responsesScope: kind == ProviderKind.openai && cfg.useResponseApi == true
          ? responsesReplayScope(cfg, modelId)
          : null,
    );

    if (assistant != null && assistant.regexRules.isNotEmpty) {
      for (int i = 0; i < apiMessages.length; i++) {
        final role = (apiMessages[i]['role'] ?? '').toString();
        if (role != 'assistant') continue;
        final raw = (apiMessages[i]['content'] ?? '').toString();
        if (raw.isEmpty) continue;
        apiMessages[i]['content'] = applyAssistantRegexes(
          raw,
          assistant: assistant,
          scope: AssistantRegexScope.assistant,
          target: AssistantRegexTransformTarget.send,
        );
      }
    }

    final promptConversation = currentConversation == null
        ? null
        : chatService.getConversation(currentConversation.id) ??
              currentConversation;

    messageBuilderService.injectSystemPrompt(
      apiMessages,
      assistant,
      modelId,
      conversation: promptConversation,
    );

    BusinessPreferences? storyPreferences;
    StoryRuntimePromptResult? storyRuntime;
    try {
      storyPreferences = contextProvider.read<BusinessPreferences>();
    } on ProviderNotFoundException {
      storyPreferences = null;
    }
    if (storyPreferences != null) {
      final storyAssistantId = (assistantId ?? assistant?.id ?? '').trim();
      if (promptConversation != null && storyAssistantId.isNotEmpty) {
        storyRuntime = await StoryRuntimePromptService(storyPreferences).build(
          conversation: promptConversation,
          messages: messages,
          assistantId: storyAssistantId,
        );
        if (storyRuntime != null) {
          const storyContextCompiler = StoryContextResourceCompiler();
          for (final message in apiMessages) {
            if ((message['role'] ?? '').toString() != 'user') continue;
            final content = message['content'];
            if (content is! String || content.isEmpty) continue;
            final transformed = storyContextCompiler.applyRegex(
              content,
              target: StoryRegexTarget.userInput,
              rules: storyRuntime.regexRules,
            );
            if (transformed == content) continue;
            message['content'] = transformed;
            if (ContextLogger.enabled) {
              ContextSegmentTags.replaceWithSingle(
                message,
                source: ContextSource.chatHistory,
                length: transformed.length,
              );
            }
          }
          StoryBreakArmorMode(
            storyPreferences,
          ).prependToSystemPrompt(apiMessages);
          _injectStoryRuntimeSystemPrompt(
            apiMessages,
            storyRuntime.providerText,
          );
        }
      }
    }

    await messageBuilderService.injectMemoryAndRecentChats(
      apiMessages,
      assistant,
      settings: settings,
      currentConversationId: currentConversation?.id,
    );

    final hasBuiltInSearch = messageBuilderService.hasBuiltInSearch(
      settings,
      providerKey,
      modelId,
    );
    messageBuilderService.injectSearchPrompt(
      apiMessages,
      settings,
      assistant,
      hasBuiltInSearch,
    );
    await messageBuilderService.injectInstructionPrompts(
      apiMessages,
      assistantId,
      conversation: promptConversation,
      conversationScoped: assistant?.allowConversationPromptInjection ?? false,
    );
    await messageBuilderService.injectWorldBookPrompts(
      apiMessages,
      assistantId,
      conversation: promptConversation,
      conversationScoped: assistant?.allowConversationPromptInjection ?? false,
      persistActivation: persistWorldBookActivation,
      onActivationPersisted: onWorldBookActivationPersisted,
      sourceMessages: messageBuilderService.collapseVersions(
        messages,
        versionSelections,
      ),
      additionalActiveBookIds:
          storyRuntime?.activeWorldBookIds ?? const <String>{},
    );

    WorkspaceToolContext? workspaceContext;
    var workspaceAttachments = const <AttachmentInfo>[];
    try {
      if (workspaceProvider != null && runtimeProvider != null) {
        workspaceContext = await WorkspaceToolsService.resolve(
          externalMounts: externalMounts,
          conversationId: currentConversation?.id,
          workspaceProvider: workspaceProvider,
          runtimeProvider: runtimeProvider,
          chatService: chatService,
        );
      }
      workspaceContext ??= await _skillsOnlyContext(
        assistant: assistant,
        conversation: currentConversation,
      );
      if (syncWorkspaceAttachments &&
          workspaceContext != null &&
          !workspaceContext.skillsOnly) {
        workspaceAttachments = await syncAttachments(
          workspaceContext,
          messages,
          requiredMessageId: requiredAttachmentMessageId,
        );
      }
      if (workspaceContext != null) {
        await messageBuilderService.injectWorkspacePrompt(
          apiMessages,
          assistant,
          conversationId: currentConversation?.id,
          workspaceContext: workspaceContext,
          attachments: workspaceAttachments,
        );
      }
    } catch (e) {
      if (workspaceContext != null && !workspaceContext.skillsOnly) {
        rethrow;
      }
      debugPrint('Workspace prompt/attachments failed: $e');
    }
    await messageBuilderService.injectSkillsPrompt(
      apiMessages,
      assistant,
      conversationId: currentConversation?.id,
      workspaceContext: workspaceContext,
    );

    messageBuilderService.applyContextLimit(apiMessages, assistant);

    // Only this step does the actual attachment work (document extraction and
    // OCR), so the indicator must not cover the injection/trim passes above —
    // and it only claims to be parsing files when the retained messages really
    // carry files to parse. A text-only send that is merely slow (frozen prompt
    // reads, memory injection, templating) must never show the bar.
    // Tools are assembled first: whether a data file is read into the prompt
    // or left for the sandbox depends on which tools go with it.
    var mcpRouteSnapshot = generationController.captureMcpToolRoutes(assistant);
    if (storyRuntime?.mcpProfileId != null) {
      mcpRouteSnapshot = mcpRouteSnapshot.filtered(
        allowedToolNames: storyRuntime!.allowedMcpToolNames,
        allowedServerIds: storyRuntime.allowedMcpServerIds,
        includeUnlisted: storyRuntime.includeAssistantMcpDefaults,
      );
    }
    final toolDefs = generationController.buildToolDefinitions(
      settings,
      assistant,
      providerKey,
      modelId,
      hasBuiltInSearch,
      mcpRouteSnapshot: mcpRouteSnapshot,
      workspaceContext: workspaceContext,
      conversationId: currentConversation?.id,
    );
    final storySerializationEnabled =
        storyPreferences != null &&
        storyRuntime != null &&
        StorySerializationTools.enabledFor(storyRuntime.activeSkillIds) &&
        generationController.isToolModel(providerKey, modelId);
    if (storySerializationEnabled) {
      toolDefs.addAll(_storySerializationToolDefinitions(kind));
    }
    final sandboxDataFiles = BuiltInToolsHelper.sendsDataFilesToSandbox(
      cfg: cfg,
      modelId: modelId,
      clientTools: toolDefs,
    );
    final resolvedWorkspace = workspaceContext;
    final hasWorkspaceFileTools =
        resolvedWorkspace != null &&
        !resolvedWorkspace.skillsOnly &&
        toolDefs.any((tool) {
          final name = (tool['function'] as Map?)?['name'];
          return (name == 'read_file' || name == 'shell') &&
              resolvedWorkspace.workspace.isToolEnabled(name as String);
        });
    final localAttachments = <String, AttachmentInfo>{
      if (hasWorkspaceFileTools)
        for (final file in workspaceAttachments) file.sourceUri: file,
    };
    final indicatorMessageId =
        processingMessageId != null &&
            messageBuilderService.hasPendingAttachmentWork(
              apiMessages,
              settings,
              conversation: currentConversation,
              sourceMessages: messages,
              sandboxDataFiles: sandboxDataFiles,
              nativePdfInput: nativePdfInput,
              workspaceAttachments: localAttachments,
            )
        ? processingMessageId
        : null;
    final List<String> lastUserImagePaths;
    if (indicatorMessageId != null) {
      onFileProcessingStarted?.call(indicatorMessageId);
    }
    try {
      lastUserImagePaths = await messageBuilderService
          .processUserMessagesForApi(
            apiMessages,
            settings,
            assistant,
            conversation: currentConversation,
            sourceMessages: messages,
            sandboxDataFiles: sandboxDataFiles,
            nativePdfInput: nativePdfInput,
            workspaceAttachments: localAttachments,
          );
    } on AttachmentRequiresWorkspace catch (e) {
      if (!contextProvider.mounted) rethrow;
      throw Exception(
        AppLocalizations.of(
              contextProvider,
            )?.attachmentRequiresWorkspace(e.name) ??
            e.toString(),
      );
    } finally {
      if (indicatorMessageId != null) {
        onFileProcessingFinished?.call(indicatorMessageId);
      }
    }

    await messageBuilderService.inlineLocalImages(apiMessages);
    if (ContextLogger.enabled) {
      final providerName = cfg.name.trim();
      ContextLogger.logPrepared(
        apiMessages: apiMessages,
        conversationId: currentConversation?.id ?? '',
        assistantName: assistant?.name ?? '',
        provider: providerName.isNotEmpty ? providerName : providerKey,
        model: modelId,
      );
    }
    messageBuilderService.stripInternalRevisionIds(apiMessages);

    final nativeOnToolCall = toolDefs.isNotEmpty
        ? generationController.buildToolCallHandler(
            settings,
            assistant,
            approvalService: approvalService,
            askUserService: askUserService,
            conversationId: currentConversation?.id,
            mcpRouteSnapshot: mcpRouteSnapshot,
            workspaceContext: workspaceContext,
          )
        : null;
    ToolCallHandler? onToolCall = nativeOnToolCall;
    if (storySerializationEnabled) {
      final preferences = storyPreferences;
      onToolCall = (name, args, {toolCallId}) async {
        if (StorySerializationTools.names.contains(name)) {
          final result = await StorySerializationTools.tryHandle(
            name: name,
            arguments: args,
            preferences: preferences,
            approveRestore: () async {
              final approval = approvalService;
              if (approval == null) return false;
              final providedId = toolCallId?.trim();
              final decision = await approval.requestApproval(
                toolCallId: providedId != null && providedId.isNotEmpty
                    ? providedId
                    : '${name}_${DateTime.now().microsecondsSinceEpoch}',
                toolName: name,
                arguments: args,
                conversationId: currentConversation?.id,
              );
              return decision.approved;
            },
          );
          if (result != null) return result;
        }
        if (nativeOnToolCall != null) {
          return nativeOnToolCall(name, args, toolCallId: toolCallId);
        }
        return null;
      };
    }

    return PreparedGeneration(
      apiMessages: apiMessages,
      toolDefs: toolDefs,
      onToolCall: onToolCall,
      hasBuiltInSearch: hasBuiltInSearch,
      lastUserImagePaths: lastUserImagePaths,
      contextUsageConfiguration: requestConfiguration,
      contextUsageRevision: requestRevision,
    );
  }

  /// Create user message from input data.
  Future<ChatMessage> createUserMessage({
    required String conversationId,
    required ChatInputData input,
    required Assistant? assistant,
  }) async {
    final parts = await MessageGenerationService.buildPersistedUserMessageParts(
      input,
      assistant: assistant,
    );
    return chatService.addMessage(
      conversationId: conversationId,
      role: 'user',
      parts: parts,
    );
  }

  Future<
    ({ChatMessage userMessage, ChatMessage assistantMessage, String? runId})
  >
  beginSendGeneration({
    required String conversationId,
    required ChatInputData input,
    required Assistant? assistant,
    required String modelId,
    required String providerKey,
  }) async {
    final userParts = await buildPersistedUserMessageParts(
      input,
      assistant: assistant,
    );
    if (chatService.isTemporaryConversation(conversationId)) {
      final userMessage = await chatService.addMessage(
        conversationId: conversationId,
        role: 'user',
        parts: userParts,
      );
      final assistantMessage = await createAssistantPlaceholder(
        conversationId: conversationId,
        modelId: modelId,
        providerKey: providerKey,
      );
      return (
        userMessage: userMessage,
        assistantMessage: assistantMessage,
        runId: null,
      );
    }
    final result = await chatService.beginSendGeneration(
      conversationId: conversationId,
      userParts: userParts,
      modelId: modelId,
      providerId: providerKey,
      draftSubmission: input.draftSubmission,
    );
    return (
      userMessage: result.userMessage!,
      assistantMessage: result.assistantMessage,
      runId: result.run.id,
    );
  }

  Future<({ChatMessage assistantMessage, String? runId})> beginRegeneration({
    required String conversationId,
    required String modelId,
    required String providerKey,
    required String groupId,
    required int version,
    required bool truncateFuture,
  }) async {
    if (chatService.isTemporaryConversation(conversationId)) {
      final assistantMessage = await createAssistantPlaceholder(
        conversationId: conversationId,
        modelId: modelId,
        providerKey: providerKey,
        groupId: groupId,
        version: version,
      );
      return (assistantMessage: assistantMessage, runId: null);
    }
    final result = await chatService.beginRegeneration(
      conversationId: conversationId,
      modelId: modelId,
      providerId: providerKey,
      groupId: groupId,
      version: version,
      truncateFuture: truncateFuture,
    );
    return (assistantMessage: result.assistantMessage, runId: result.run.id);
  }

  Future<({ChatMessage assistantMessage, String? runId})>
  beginAssistantGeneration({
    required String conversationId,
    required String modelId,
    required String providerKey,
    required String anchorGroupId,
    required bool truncateFuture,
  }) async {
    if (chatService.isTemporaryConversation(conversationId)) {
      final assistantMessage = await createAssistantPlaceholder(
        conversationId: conversationId,
        modelId: modelId,
        providerKey: providerKey,
        temporaryAfterGroupId: anchorGroupId,
      );
      return (assistantMessage: assistantMessage, runId: null);
    }
    final result = await chatService.beginAssistantGeneration(
      conversationId: conversationId,
      modelId: modelId,
      providerId: providerKey,
      anchorGroupId: anchorGroupId,
      truncateFuture: truncateFuture,
    );
    return (assistantMessage: result.assistantMessage, runId: result.run.id);
  }

  /// Build structured parts for a persisted user message.
  ///
  /// Text is always present (possibly empty). Attachments follow in the
  /// user's selection order. No legacy attachment markers are produced.
  static Future<List<MessagePart>> buildPersistedUserMessageParts(
    ChatInputData input, {
    required Assistant? assistant,
  }) async {
    final processedUserText = applyAssistantRegexes(
      input.text.trim(),
      assistant: assistant,
      scope: AssistantRegexScope.user,
      target: AssistantRegexTransformTarget.persist,
    );

    final parts = <MessagePart>[TextPart(processedUserText)];
    for (final path in input.imagePaths) {
      parts.add(
        ImagePart(
          uri: SandboxPathResolver.canonicalize(path),
          mime: await inferAttachmentMime(uri: path),
        ),
      );
    }
    for (final document in input.documents) {
      parts.add(
        FilePart(
          uri: SandboxPathResolver.canonicalize(document.path),
          name: document.fileName,
          mime: await inferAttachmentMime(
            uri: document.path,
            explicitMime: document.mime,
            fileName: document.fileName,
          ),
        ),
      );
    }
    return parts;
  }

  /// Derived text body for callers that still need a plain string.
  static Future<String> buildPersistedUserMessageContent(
    ChatInputData input, {
    required Assistant? assistant,
  }) async {
    final parts = await buildPersistedUserMessageParts(
      input,
      assistant: assistant,
    );
    return parts.whereType<TextPart>().map((part) => part.text).join();
  }

  /// Create assistant message placeholder.
  Future<ChatMessage> createAssistantPlaceholder({
    required String conversationId,
    required String modelId,
    required String providerKey,
    String? groupId,
    int version = 0,
    String? temporaryAfterGroupId,
  }) async {
    return chatService.addMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerKey,
      isStreaming: true,
      groupId: groupId,
      version: version,
      selectVersion: groupId != null,
      temporaryAfterGroupId: temporaryAfterGroupId,
    );
  }

  /// Initialize reasoning state for a message if reasoning is enabled.
  Future<void> initializeReasoningState({
    required String messageId,
    required bool enableReasoning,
  }) async {
    if (enableReasoning) {
      final rd = stream_ctrl.ReasoningData();
      streamController.reasoning[messageId] = rd;
      await chatService.updateMessage(
        messageId,
        reasoningStartAt: DateTime.now(),
      );
    }
  }

  /// Build GenerationContext for streaming.
  stream_ctrl.GenerationContext buildGenerationContext({
    required ChatMessage assistantMessage,
    required PreparedGeneration prepared,
    required List<String> userImagePaths,
    required bool allowImagesApiRouting,
    required String providerKey,
    required String modelId,
    required Assistant? assistant,
    required SettingsProvider settings,
    required bool supportsReasoning,
    required bool enableReasoning,
    required bool generateTitleOnFinish,
    String? generationRunId,
    bool scheduled = false,
    bool scheduledNotify = true,
    bool scheduledPreview = true,
  }) {
    final bool ocrActive = settings.ocrActive;

    return stream_ctrl.GenerationContext(
      assistantMessage: assistantMessage,
      apiMessages: prepared.apiMessages,
      contextUsageConfiguration: prepared.contextUsageConfiguration,
      contextUsageRevision: prepared.contextUsageRevision,
      userImagePaths: userImagePaths,
      allowImagesApiRouting: allowImagesApiRouting,
      providerKey: providerKey,
      modelId: modelId,
      assistant: assistant,
      settings: settings,
      config: settings.getProviderConfig(providerKey),
      toolDefs: prepared.toolDefs,
      onToolCall: prepared.onToolCall,
      extraHeaders: buildConversationRequestHeaders(
        conversationId: assistantMessage.conversationId,
        customHeaders: generationController.buildCustomHeaders(assistant),
      ),
      extraBody: generationController.buildCustomBody(assistant),
      supportsReasoning: supportsReasoning,
      enableReasoning: enableReasoning,
      streamOutput: assistant?.streamOutput ?? true,
      ocrActive: ocrActive,
      generateTitleOnFinish: generateTitleOnFinish,
      generationRunId: generationRunId,
      scheduled: scheduled,
      scheduledNotify: scheduledNotify,
      scheduledPreview: scheduledPreview,
    );
  }

  /// Get the model this conversation sends with: the conversation's own
  /// override, else the assistant's model, else the global default.
  ({String? providerKey, String? modelId}) getModelConfig(
    SettingsProvider settings,
    Assistant? assistant, {
    Conversation? conversation,
  }) => resolveChatModel(
    settings,
    conversation: conversation,
    assistant: assistant,
  );

  /// Calculate version info for regeneration.
  ({String? targetGroupId, int nextVersion, int lastKeep})
  calculateRegenerationVersioning({
    required ChatMessage message,
    required List<ChatMessage> messages,
    required bool assistantAsNewReply,
  }) {
    final idx = messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) {
      return (targetGroupId: null, nextVersion: 0, lastKeep: -1);
    }

    String? targetGroupId;
    int nextVersion = 0;
    int lastKeep;

    if (message.role == 'assistant') {
      lastKeep = idx;
      if (assistantAsNewReply) {
        targetGroupId = null;
        nextVersion = 0;
      } else {
        targetGroupId = message.groupId ?? message.id;
        int maxVer = -1;
        for (final m in messages) {
          final gid = (m.groupId ?? m.id);
          if (gid == targetGroupId) {
            if (m.version > maxVer) maxVer = m.version;
          }
        }
        nextVersion = maxVer + 1;
      }
    } else {
      // User message
      final userGroupId = message.groupId ?? message.id;
      int userFirst = -1;
      for (int i = 0; i < messages.length; i++) {
        final gid0 = (messages[i].groupId ?? messages[i].id);
        if (gid0 == userGroupId) {
          userFirst = i;
          break;
        }
      }
      if (userFirst < 0) userFirst = idx;

      int aid = -1;
      for (int i = userFirst + 1; i < messages.length; i++) {
        final candidateGroupId = messages[i].groupId ?? messages[i].id;
        if (candidateGroupId == userGroupId) continue;
        if (messages[i].role == 'assistant') {
          aid = i;
        }
        break;
      }

      if (aid >= 0) {
        lastKeep = aid;
        targetGroupId = messages[aid].groupId ?? messages[aid].id;
        int maxVer = -1;
        for (final m in messages) {
          final gid = (m.groupId ?? m.id);
          if (gid == targetGroupId) {
            if (m.version > maxVer) maxVer = m.version;
          }
        }
        nextVersion = maxVer + 1;
      } else {
        lastKeep = userFirst;
        targetGroupId = null;
        nextVersion = 0;
      }
    }

    return (
      targetGroupId: targetGroupId,
      nextVersion: nextVersion,
      lastKeep: lastKeep,
    );
  }

  /// Remove trailing messages after regeneration cut point.
  @visibleForTesting
  static List<String> collectTrailingMessageIdsForRemoval({
    required List<ChatMessage> messages,
    required int lastKeep,
    required String? targetGroupId,
  }) {
    if (lastKeep >= messages.length - 1) {
      return const [];
    }

    final keepGroups = <String>{};
    for (int i = 0; i <= lastKeep && i < messages.length; i++) {
      keepGroups.add(messages[i].groupId ?? messages[i].id);
    }
    if (targetGroupId != null) keepGroups.add(targetGroupId);

    final removeIds = <String>[];
    for (final message in messages.sublist(lastKeep + 1)) {
      final groupId = message.groupId ?? message.id;
      if (!keepGroups.contains(groupId)) {
        removeIds.add(message.id);
      }
    }
    return removeIds;
  }

  /// Remove trailing messages after regeneration cut point.
  Future<List<String>> removeTrailingMessages({
    required List<ChatMessage> messages,
    required int lastKeep,
    required String? targetGroupId,
  }) async {
    final removeIds = collectTrailingMessageIdsForRemoval(
      messages: messages,
      lastKeep: lastKeep,
      targetGroupId: targetGroupId,
    );

    var deletedIds = removeIds;
    if (removeIds.isNotEmpty && messages.isNotEmpty) {
      final removeIdSet = removeIds.toSet();
      final conversationId = messages.first.conversationId;
      final selectionChanges = <String, int?>{};
      for (final message in messages) {
        if (removeIdSet.contains(message.id)) {
          selectionChanges[message.groupId ?? message.id] = null;
        }
      }
      deletedIds = (await chatService.deleteMessages(
        conversationId: conversationId,
        messageIds: removeIdSet,
        versionSelectionChanges: selectionChanges,
      )).toList(growable: false);
    }
    for (final id in deletedIds) {
      streamController.reasoning.remove(id);
      streamController.toolParts.remove(id);
      streamController.reasoningSegments.remove(id);
    }

    return deletedIds;
  }

  String _effectiveAttachmentMime(DocumentAttachment attachment) {
    return resolveDocumentAttachmentMime(attachment);
  }

  /// Image / audio / video the [spec] can read. Documents are never included.
  @visibleForTesting
  static List<String> filterMediaPathsForProvider(
    List<String> paths, {
    required ModelSpec spec,
  }) {
    return [
      for (final path in paths)
        if (_specAcceptsGatedMediaPath(path, spec)) path,
    ];
  }

  static bool _specAcceptsGatedMediaPath(String path, ModelSpec spec) {
    final mime = inferMediaMimeFromSource(path, fallbackMime: 'image/png');
    if (isAudioMime(mime)) return spec.supportsAudioInput;
    if (isVideoMime(mime)) return spec.supportsVideoInput;
    if (isImageMime(mime)) return spec.supportsImageInput;
    return false;
  }

  /// Build user image paths considering OCR mode.
  List<String> buildUserImagePaths({
    required ChatInputData? input,
    required List<String> lastUserImagePaths,
    required SettingsProvider settings,
    required String providerKey,
    required String modelId,
  }) {
    final bool ocrActive = settings.ocrActive;
    final spec = ModelSpecResolver.instance.spec(
      settings.getProviderConfig(providerKey),
      modelId,
    );

    if (input != null) {
      final currentMediaPaths = <String>[];
      for (final d in input.documents) {
        final effectiveMime = _effectiveAttachmentMime(d);
        if (isVideoMime(effectiveMime) || isAudioMime(effectiveMime)) {
          currentMediaPaths.add(d.path);
        }
      }
      return filterMediaPathsForProvider(<String>[
        if (!ocrActive) ...input.imagePaths,
        ...currentMediaPaths,
      ], spec: spec);
    }

    return filterMediaPathsForProvider(
      lastUserImagePaths
          .where((path) {
            if (!ocrActive) return true;
            return !isImageMime(
              inferMediaMimeFromSource(path, fallbackMime: 'image/png'),
            );
          })
          .toList(growable: false),
      spec: spec,
    );
  }

  Future<WorkspaceToolContext?> _skillsOnlyContext({
    required Assistant? assistant,
    required Conversation? conversation,
  }) async {
    try {
      final skillsService = contextProvider.read<SkillsService>();
      await skillsService.loaded;
      final override = conversation == null
          ? null
          : SkillsBinding.fromExtras(conversation.extras).skillIds;
      final skills = skillsService.resolveForAssistant(
        assistant,
        conversationOverride: override,
      );
      if (skills.isEmpty) return null;
      return WorkspaceToolContext.skillsOnly(
        skillsHostDir: skillsService.skillsDirectory.path,
        conversationId: conversation?.id,
      );
    } catch (_) {
      return null;
    }
  }
}
