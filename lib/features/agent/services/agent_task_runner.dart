import 'dart:async';
import 'dart:io';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/environment_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/workspace_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../utils/app_directories.dart';
import '../../home/utils/model_display_helper.dart';
import '../models/agent_task.dart';
import '../providers/agent_interaction_broker.dart';
import '../providers/agent_settings_provider.dart';
import '../providers/agent_task_provider.dart';
import 'agent_context_materializer.dart';
import 'agent_model_bridge.dart';
import 'agent_runtime_bootstrap.dart';
import 'agent_task_journal.dart';
import 'agent_engine_installer.dart';
import 'agent_github_cli_installer.dart';
import 'pi_rpc_session.dart';

class AgentTaskRunner {
  AgentTaskRunner({
    required this.tasks,
    required this.journal,
    required this.interactions,
    required this.agentSettings,
    required this.workspaces,
    required this.assistants,
    required this.chat,
    required this.contextMaterializer,
    required this.settings,
    required this.runtimeBootstrap,
    required this.environment,
    required this.engineInstaller,
    required this.githubCliInstaller,
  }) {
    recovery = _recoverUnownedTasks();
  }

  final AgentTaskProvider tasks;
  final AgentTaskJournal journal;
  final AgentInteractionBroker interactions;
  final AgentSettingsProvider agentSettings;
  final WorkspaceProvider workspaces;
  final AssistantProvider assistants;
  final ChatService chat;
  final AgentContextMaterializer contextMaterializer;
  final SettingsProvider settings;
  final AgentRuntimeBootstrap runtimeBootstrap;
  final EnvironmentProvider environment;
  final AgentEngineInstaller engineInstaller;
  final AgentGithubCliInstaller githubCliInstaller;

  late final Future<void> recovery;
  final Map<String, PiRpcSession> _sessions = <String, PiRpcSession>{};
  final Set<String> _running = <String>{};
  final Set<String> _cancelled = <String>{};
  final Map<String, String> _toolOutputSnapshots = <String, String>{};
  final Map<String, String> _subagentProgressSnapshots = <String, String>{};

  bool isRunning(String taskId) => _running.contains(taskId);

  Future<void> _recoverUnownedTasks() async {
    await tasks.loaded;
    await tasks.markUnownedRunningTasksInterrupted();
  }

  Future<void> run(String taskId) async {
    await recovery;
    if (_running.contains(taskId)) return;

    final task = tasks.byId(taskId);
    if (task == null) throw StateError('agent_task_missing');
    if (task.phase.isTerminal && task.phase != AgentTaskPhase.failed) return;

    _running.add(taskId);
    _cancelled.remove(taskId);
    PiRpcSession? session;
    AgentModelBridge? modelBridge;
    StreamSubscription<Map<String, dynamic>>? subscription;
    Map<String, String> secretValues = const <String, String>{};

    try {
      await tasks.setPhase(
        taskId,
        AgentTaskPhase.preparing,
        currentStep: 'Preparing task',
      );

      final runtimeHandle = await runtimeBootstrap.ensureReady(
        environmentId: task.environmentId,
      );
      final WorkspaceStdioRuntime runtime = runtimeHandle.runtime;

      await workspaces.loaded;
      final workspace = workspaces.byId(task.workspaceId);
      if (workspace == null) throw StateError('agent_workspace_missing');
      final workspaceRoot = await workspaces.hostRootFor(workspace);
      final taskDir = await AppDirectories.agentTaskDir(task.id);
      final installation = await engineInstaller.ensureInstalled(
        environmentId: task.environmentId,
      );
      AgentGithubCliInstallation? githubCli;
      try {
        githubCli = await githubCliInstaller.ensureInstalled(
          environmentId: task.environmentId,
        );
      } catch (_) {
        await journal.append(
          taskId,
          AgentTaskEventKind.notice,
          payload: const <String, dynamic>{
            'kind': 'github_cli_unavailable',
          },
        );
      }
      final execution = await environment.loadExecutionConfig();
      secretValues = execution.variables;

      final assistant = task.assistantId == null
          ? null
          : assistants.getById(task.assistantId!);
      final conversation = task.conversationId == null
          ? null
          : chat.getConversation(task.conversationId!);
      final materializedContext = await contextMaterializer.materialize(
        taskId: task.id,
        assistantId: task.assistantId,
        skillIds: assistant?.skillIds?.toSet(),
        mcpServerIds: conversation?.mcpServerIds.toSet(),
      );

      await settings.loaded;
      await agentSettings.loaded;
      final inheritedModel = resolveChatModel(
        settings,
        conversation: conversation,
        assistant: assistant,
      );
      final providerKey = agentSettings.hasModelOverride
          ? agentSettings.modelProvider
          : inheritedModel.providerKey;
      final modelId = agentSettings.hasModelOverride
          ? agentSettings.modelId
          : inheritedModel.modelId;
      if (providerKey == null || modelId == null) {
        throw StateError('agent_model_not_configured');
      }
      modelBridge = AgentModelBridge(
        config: settings.getProviderConfig(providerKey),
        modelId: modelId,
        assistant: assistant,
        conversationId: task.conversationId,
      );
      final modelEndpoint = await modelBridge.start();
      final modelConfigFiles = await modelBridge.writePiConfig(
        taskDirectory: taskDir,
        endpoint: modelEndpoint,
      );
      final engineConfigFile = await _writeEngineConfig(
        taskDir,
        permissionMode: agentSettings.permissionMode,
        maxParallelAgents: agentSettings.maxParallelAgents,
        subagentIsolation: agentSettings.subagentIsolation,
        githubEnabled: githubCli != null,
      );

      final mounts = <Mount>[
        Mount(host: workspaceRoot, guest: '/workspace'),
        Mount(host: taskDir.path, guest: '/kelivo-agent-task'),
        Mount(
          host: modelConfigFiles.jsonFile.path,
          guest: '/home/kelivo/.pi/agent/models.json',
          readOnly: true,
        ),
        Mount(
          host: modelConfigFiles.yamlFile.path,
          guest: '/home/kelivo/.pi/agent/models.yml',
          readOnly: true,
        ),
        Mount(
          host: engineConfigFile.path,
          guest: '/home/kelivo/.pi/agent/config.yml',
          readOnly: true,
        ),
        installation.asMount(),
        if (githubCli != null) githubCli.asMount(),
        for (final skill in materializedContext.skillMounts)
          Mount(
            host: skill.hostDirectory,
            guest: skill.guestDirectory,
            readOnly: true,
          ),
      ];

      session = await PiRpcSession.start(
        runtime: runtime,
        executable: installation.guestExecutable,
        cwd: '/workspace',
        sessionDir: '/kelivo-agent-task/pi-session',
        sessionName: task.title.isEmpty ? 'KELIVO Agent' : task.title,
        approvalMode: _ompApprovalMode(agentSettings.permissionMode),
        appendSystemPrompt: materializedContext.guestPromptFile,
        extraArgs: <String>[
          '--model',
          'kelivo/current',
          '--tools',
          _ompTools(agentSettings.permissionMode),
        ],
        mounts: mounts,
        environment: <String, String>{
          ...execution.variables,
          'PI_CODING_AGENT_DIR': '/home/kelivo/.pi/agent',
          'PI_TELEMETRY': '0',
          'PI_SKIP_VERSION_CHECK': '1',
          'KELIVO_AGENT_PERMISSION_MODE': agentSettings.permissionMode.name,
          'KELIVO_AGENT_BRIDGE_KEY': modelEndpoint.token,
          'OMP_WORKTREE_DIR': '/kelivo-agent-task/worktrees',
          if (githubCli != null)
            'PATH':
                '${githubCli.guestRoot}/bin:/home/kelivo/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
        },
      );
      _sessions[taskId] = session;
      final subagentSubscription = await session.setSubagentSubscription(
        level: 'events',
      );
      if (subagentSubscription['success'] != true) {
        throw StateError('agent_subagent_subscription_rejected');
      }

      final agentEnd = Completer<void>();
      Future<void> eventTail = Future<void>.value();
      subscription = session.events.listen(
        (event) {
          eventTail = eventTail
              .then((_) async {
                final ended = await _handleEvent(
                  taskId,
                  session!,
                  event,
                  secrets: secretValues.values,
                );
                if (ended && !agentEnd.isCompleted) agentEnd.complete();
              })
              .catchError((Object error, StackTrace stack) {
                if (!agentEnd.isCompleted) agentEnd.completeError(error, stack);
              });
        },
        onError: (Object error, StackTrace stack) {
          if (!agentEnd.isCompleted) agentEnd.completeError(error, stack);
        },
        onDone: () {
          if (!agentEnd.isCompleted && !_cancelled.contains(taskId)) {
            agentEnd.completeError(
              StateError(
                session?.exitDescription ?? 'agent_rpc_closed',
              ),
            );
          }
        },
      );

      await tasks.setPhase(
        taskId,
        AgentTaskPhase.running,
        currentStep: 'Working',
      );
      final promptResponse = await session.prompt(task.goal);
      if (promptResponse['success'] != true) {
        throw StateError('pi_prompt_rejected');
      }

      await agentEnd.future;
      await eventTail;
      if (_cancelled.contains(taskId)) return;

      await tasks.setPhase(
        taskId,
        AgentTaskPhase.verifying,
        currentStep: 'Checking results',
      );
      await _waitUntilIdle(session);
      if (_cancelled.contains(taskId)) return;

      await journal.append(
        taskId,
        AgentTaskEventKind.checkpoint,
        payload: const <String, dynamic>{'kind': 'pi_agent_end'},
      );
      await tasks.setPhase(
        taskId,
        AgentTaskPhase.completed,
        currentStep: 'Completed',
      );
    } catch (error) {
      if (!_cancelled.contains(taskId)) {
        final safe = _redact(error.toString(), secretValues.values);
        await tasks.setPhase(
          taskId,
          AgentTaskPhase.failed,
          currentStep: 'Agent failed',
          error: safe,
        );
        await journal.append(
          taskId,
          AgentTaskEventKind.note,
          payload: const <String, dynamic>{'kind': 'runner_error'},
        );
      }
    } finally {
      interactions.cancelForTask(taskId);
      await subscription?.cancel();
      if (session != null) {
        await session.close();
      }
      await modelBridge?.close();
      _sessions.remove(taskId);
      _running.remove(taskId);
      _toolOutputSnapshots.removeWhere(
        (key, _) => key.startsWith('$taskId:'),
      );
      _subagentProgressSnapshots.removeWhere(
        (key, _) => key.startsWith('$taskId:'),
      );
    }
  }

  Future<bool> runShell(String taskId, String command) async {
    final text = command.trim();
    if (text.isEmpty) return false;
    final session = _sessions[taskId];
    if (session == null) return false;
    final id = 'shell-${DateTime.now().microsecondsSinceEpoch}';
    await journal.append(
      taskId,
      AgentTaskEventKind.toolStarted,
      payload: <String, dynamic>{
        'tool': 'bash',
        'toolCallId': id,
        'direct': true,
        'args': <String, dynamic>{'command': text},
      },
    );
    final response = await session.bash(text, id: id);
    final data = response['data'];
    final map = data is Map ? data.cast<String, dynamic>() : const <String, dynamic>{};
    final output = map['output']?.toString() ?? '';
    await journal.append(
      taskId,
      AgentTaskEventKind.toolFinished,
      payload: <String, dynamic>{
        'tool': 'bash',
        'toolCallId': id,
        'direct': true,
        'isError': (map['exitCode'] as num?)?.toInt() != 0,
        if (output.isNotEmpty) 'output': _limit(output, 16000),
        if (map['exitCode'] != null) 'exitCode': map['exitCode'],
      },
    );
    return response['success'] == true;
  }

  Future<bool> steer(String taskId, String message) async {
    final text = message.trim();
    if (text.isEmpty) return false;
    final session = _sessions[taskId];
    if (session == null) return false;
    final response = await session.steer(text);
    if (response['success'] == true) {
      await journal.append(
        taskId,
        AgentTaskEventKind.note,
        payload: <String, dynamic>{'kind': 'steer', 'text': _limit(text, 4000)},
      );
      return true;
    }
    return false;
  }

  Future<bool> followUp(String taskId, String message) async {
    final text = message.trim();
    if (text.isEmpty) return false;
    final session = _sessions[taskId];
    if (session == null) return false;
    final response = await session.followUp(text);
    if (response['success'] == true) {
      await journal.append(
        taskId,
        AgentTaskEventKind.note,
        payload: <String, dynamic>{
          'kind': 'follow_up',
          'text': _limit(text, 4000),
        },
      );
      return true;
    }
    return false;
  }

  Future<void> cancel(String taskId) async {
    await recovery;
    _cancelled.add(taskId);
    interactions.cancelForTask(taskId);
    final session = _sessions[taskId];
    if (session != null) {
      await session.abort();
      await session.close();
    }
    await tasks.setPhase(
      taskId,
      AgentTaskPhase.cancelled,
      currentStep: 'Cancelled',
    );
  }

  Future<bool> _handleEvent(
    String taskId,
    PiRpcSession session,
    Map<String, dynamic> event, {
    required Iterable<String> secrets,
  }) async {
    final type = event['type']?.toString();
    switch (type) {
      case 'agent_start':
        await tasks.setPhase(
          taskId,
          AgentTaskPhase.running,
          currentStep: 'Working',
        );
      case 'agent_settled':
        await journal.append(
          taskId,
          AgentTaskEventKind.checkpoint,
          payload: const <String, dynamic>{'kind': 'agent_settled'},
        );
        return true;
      case 'turn_start':
        await journal.append(taskId, AgentTaskEventKind.turnStarted);
      case 'turn_end':
        await journal.append(taskId, AgentTaskEventKind.turnFinished);
      case 'message_end':
        final message = event['message'];
        final text = _messageText(message);
        if (text.isNotEmpty && _messageRole(message) == 'assistant') {
          await journal.append(
            taskId,
            AgentTaskEventKind.assistantMessage,
            payload: <String, dynamic>{'text': _redact(text, secrets)},
          );
        }
      case 'bash_execution_update':
        if (!agentSettings.showToolOutput) break;
        final delta = event['delta']?.toString() ?? '';
        if (delta.isNotEmpty) {
          await journal.append(
            taskId,
            AgentTaskEventKind.toolProgress,
            payload: <String, dynamic>{
              'tool': 'bash',
              if (event['id'] != null) 'toolCallId': event['id'].toString(),
              'output': _redact(_limit(delta, 12000), secrets),
              'delta': true,
            },
          );
        }
      case 'tool_execution_start':
        final tool = event['toolName']?.toString() ?? 'tool';
        final args = _safeValue(event['args'], secrets);
        if (tool == 'kelivo_plan') {
          final plan = args is Map
              ? args.cast<String, dynamic>()
              : const <String, dynamic>{};
          await journal.append(
            taskId,
            AgentTaskEventKind.planUpdated,
            payload: plan,
          );
          break;
        }
        await tasks.setPhase(
          taskId,
          AgentTaskPhase.running,
          currentStep: 'Running $tool',
        );
        await journal.append(
          taskId,
          AgentTaskEventKind.toolStarted,
          payload: <String, dynamic>{
            'tool': tool,
            if (event['toolCallId'] != null)
              'toolCallId': event['toolCallId'].toString(),
            if (args != null) 'args': args,
          },
        );
      case 'tool_execution_update':
        if (!agentSettings.showToolOutput) break;
        final tool = event['toolName']?.toString() ?? 'tool';
        final toolCallId = event['toolCallId']?.toString() ?? '';
        final output = _toolText(event['partialResult']);
        final snapshotKey = '$taskId:$toolCallId';
        final previous = _toolOutputSnapshots[snapshotKey] ?? '';
        final delta = output.startsWith(previous)
            ? output.substring(previous.length)
            : output;
        _toolOutputSnapshots[snapshotKey] = output;
        if (delta.isNotEmpty) {
          await journal.append(
            taskId,
            AgentTaskEventKind.toolProgress,
            payload: <String, dynamic>{
              'tool': tool,
              if (toolCallId.isNotEmpty) 'toolCallId': toolCallId,
              'output': _redact(_limit(delta, 12000), secrets),
              'delta': true,
            },
          );
        }
      case 'tool_execution_end':
        final tool = event['toolName']?.toString() ?? 'tool';
        final toolCallId = event['toolCallId']?.toString() ?? '';
        final hadStreamingOutput = toolCallId.isNotEmpty &&
            _toolOutputSnapshots.remove('$taskId:$toolCallId') != null;
        if (tool == 'kelivo_plan') break;
        final output = agentSettings.showToolOutput && !hadStreamingOutput
            ? _toolText(event['result'])
            : '';
        await journal.append(
          taskId,
          AgentTaskEventKind.toolFinished,
          payload: <String, dynamic>{
            'tool': tool,
            if (event['toolCallId'] != null)
              'toolCallId': event['toolCallId'].toString(),
            'isError': event['isError'] == true,
            if (output.isNotEmpty)
              'output': _redact(_limit(output, 16000), secrets),
          },
        );
      case 'queue_update':
        await journal.append(
          taskId,
          AgentTaskEventKind.queueChanged,
          payload: <String, dynamic>{
            if (event['steering'] is List)
              'steeringCount': (event['steering'] as List).length,
            if (event['followUp'] is List)
              'followUpCount': (event['followUp'] as List).length,
          },
        );
      case 'subagent_lifecycle':
        final raw = _safeValue(event['payload'], secrets);
        final payload = raw is Map
            ? raw.cast<String, dynamic>()
            : <String, dynamic>{};
        await journal.append(
          taskId,
          AgentTaskEventKind.subagentLifecycle,
          payload: payload,
        );
        final agent = payload['agent']?.toString() ?? 'subagent';
        final status = payload['status']?.toString() ?? 'updated';
        await tasks.setPhase(
          taskId,
          AgentTaskPhase.running,
          currentStep: '$agent: $status',
        );
      case 'subagent_progress':
        final raw = _safeValue(event['payload'], secrets);
        final payload = raw is Map
            ? raw.cast<String, dynamic>()
            : <String, dynamic>{};
        final progress = payload['progress'];
        final progressMap = progress is Map
            ? progress.cast<String, dynamic>()
            : const <String, dynamic>{};
        final subagentId =
            progressMap['id']?.toString() ?? payload['index']?.toString() ?? '';
        final signature = [
          progressMap['status'],
          progressMap['currentTool'],
          progressMap['currentToolArgs'],
          progressMap['toolCount'],
          progressMap['requests'],
          progressMap['tokens'],
          (progressMap['recentOutput'] is List &&
                  (progressMap['recentOutput'] as List).isNotEmpty)
              ? (progressMap['recentOutput'] as List).last
              : null,
        ].join('|');
        final snapshotKey = '$taskId:$subagentId';
        if (_subagentProgressSnapshots[snapshotKey] != signature) {
          _subagentProgressSnapshots[snapshotKey] = signature;
          await journal.append(
            taskId,
            AgentTaskEventKind.subagentProgress,
            payload: payload,
          );
        }
      case 'subagent_event':
        final raw = _safeValue(event['payload'], secrets);
        final payload = raw is Map
            ? raw.cast<String, dynamic>()
            : <String, dynamic>{};
        final nested = payload['event'];
        final nestedType = nested is Map
            ? nested['type']?.toString()
            : null;
        if ({
          'tool_execution_start',
          'tool_execution_end',
          'message_end',
          'auto_retry_start',
          'auto_retry_end',
        }.contains(nestedType)) {
          await journal.append(
            taskId,
            AgentTaskEventKind.subagentEvent,
            payload: payload,
          );
        }
      case 'auto_retry_start':
        await tasks.setPhase(
          taskId,
          AgentTaskPhase.running,
          currentStep: 'Retrying',
        );
        await journal.append(
          taskId,
          AgentTaskEventKind.retry,
          payload: <String, dynamic>{
            'state': 'start',
            if (event['attempt'] != null) 'attempt': event['attempt'],
            if (event['maxAttempts'] != null)
              'maxAttempts': event['maxAttempts'],
          },
        );
      case 'auto_retry_end':
        await journal.append(
          taskId,
          AgentTaskEventKind.retry,
          payload: <String, dynamic>{
            'state': 'end',
            'success': event['success'] == true,
          },
        );
      case 'compaction_start':
        await journal.append(
          taskId,
          AgentTaskEventKind.compaction,
          payload: const <String, dynamic>{'state': 'start'},
        );
      case 'compaction_end':
        await journal.append(
          taskId,
          AgentTaskEventKind.compaction,
          payload: const <String, dynamic>{'state': 'end'},
        );
      case 'extension_error':
        await journal.append(
          taskId,
          AgentTaskEventKind.notice,
          payload: <String, dynamic>{
            'kind': 'extension_error',
            if (event['error'] != null)
              'message': _redact(_limit(event['error'].toString(), 4000), secrets),
          },
        );
      case 'extension_ui_request':
        await _handleExtensionUi(taskId, session, event);
      case 'agent_end':
        // A low-level run may still be followed by retry, compaction or queued
        // continuations. Only agent_settled completes a KELIVO task.
        break;
    }
    return false;
  }

  Future<void> _handleExtensionUi(
    String taskId,
    PiRpcSession session,
    Map<String, dynamic> event,
  ) async {
    final method = event['method']?.toString() ?? '';
    if (!{'select', 'confirm', 'input', 'editor'}.contains(method)) {
      await journal.append(
        taskId,
        AgentTaskEventKind.note,
        payload: <String, dynamic>{'kind': 'pi_ui', 'method': method},
      );
      return;
    }

    await tasks.setPhase(
      taskId,
      AgentTaskPhase.waitingApproval,
      currentStep: 'Waiting for user input',
    );
    await journal.append(
      taskId,
      AgentTaskEventKind.approvalRequested,
      payload: <String, dynamic>{'method': method},
    );

    final response = await interactions.request(taskId, event);
    await session.respondToExtensionUi(response);
    await journal.append(
      taskId,
      AgentTaskEventKind.approvalResolved,
      payload: <String, dynamic>{
        'method': method,
        'cancelled': response['cancelled'] == true,
      },
    );
    await tasks.setPhase(
      taskId,
      AgentTaskPhase.running,
      currentStep: 'Working',
    );
  }

  static String _ompApprovalMode(AgentPermissionMode mode) => switch (mode) {
    AgentPermissionMode.auto => 'yolo',
    AgentPermissionMode.ask => 'always-ask',
    AgentPermissionMode.planFirst => 'always-ask',
    AgentPermissionMode.readOnly => 'yolo',
  };

  static String _ompTools(AgentPermissionMode mode) {
    if (mode == AgentPermissionMode.readOnly) {
      // Do not merely rely on prompts here: a read-only task must not receive
      // mutating/exec tools at all. This also prevents headless subagents from
      // inheriting an execution surface through task/hub.
      return 'read,grep,glob,find,ask,todo';
    }
    return 'read,bash,edit,write,grep,glob,find,lsp,task,hub,todo,github,ask,checkpoint,rewind,ast_grep,ast_edit,security_scan';
  }

  Future<File> _writeEngineConfig(
    Directory taskDir, {
    required AgentPermissionMode permissionMode,
    required int maxParallelAgents,
    required bool subagentIsolation,
    required bool githubEnabled,
  }) async {
    final file = File('${taskDir.path}/omp-config.yml');
    await file.writeAsString(
      [
        'tools:',
        '  approvalMode: ${_ompApprovalMode(permissionMode)}',
        'async:',
        '  enabled: true',
        '  maxJobs: ${(maxParallelAgents + 2).clamp(3, 6)}',
        'bash:',
        '  autoBackground:',
        '    enabled: true',
        'task:',
        '  batch: true',
        '  maxConcurrency: ${maxParallelAgents.clamp(1, 4)}',
        '  maxRecursionDepth: 2',
        '  isolation:',
        '    enabled: ${subagentIsolation ? 'true' : 'false'}',
        'isolation:',
        '  backend: rcopy',
        'github:',
        '  enabled: ${githubEnabled ? 'true' : 'false'}',
        '',
      ].join('\n'),
      flush: true,
    );
    return file;
  }

  static String _messageRole(Object? raw) {
    if (raw is Map) return raw['role']?.toString() ?? '';
    return '';
  }

  static String _messageText(Object? raw) {
    if (raw is! Map) return '';
    final content = raw['content'];
    if (content is String) return content;
    if (content is! List) return '';
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is Map && item['type']?.toString() == 'text') {
        final text = item['text']?.toString() ?? '';
        if (text.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.write(text);
        }
      }
    }
    return buffer.toString();
  }

  static String _toolText(Object? raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is Map) {
      final content = raw['content'];
      if (content is List) {
        final buffer = StringBuffer();
        for (final item in content) {
          if (item is Map && item['text'] != null) {
            if (buffer.isNotEmpty) buffer.writeln();
            buffer.write(item['text'].toString());
          }
        }
        if (buffer.isNotEmpty) return buffer.toString();
      }
      if (raw['text'] != null) return raw['text'].toString();
    }
    return raw.toString();
  }

  static Object? _safeValue(Object? value, Iterable<String> secrets) {
    if (value == null || value is num || value is bool) return value;
    if (value is String) return _redact(_limit(value, 12000), secrets);
    if (value is List) {
      return <Object?>[
        for (final item in value.take(64)) _safeValue(item, secrets),
      ];
    }
    if (value is Map) {
      final result = <String, Object?>{};
      var count = 0;
      for (final entry in value.entries) {
        if (count++ >= 64) break;
        result[entry.key.toString()] = _safeValue(entry.value, secrets);
      }
      return result;
    }
    return _redact(_limit(value.toString(), 12000), secrets);
  }

  static String _limit(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}\n… [truncated]';
  }

  Future<void> _waitUntilIdle(PiRpcSession session) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final response = await session.getState();
      final data = response['data'];
      if (data is Map) {
        final state = data.cast<String, dynamic>();
        final streaming = state['isStreaming'] == true;
        final pending = (state['pendingMessageCount'] as num?)?.toInt() ?? 0;
        if (!streaming && pending == 0) return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('pi_session_not_idle');
  }

  static String _redact(String input, Iterable<String> secrets) {
    var output = input;
    for (final secret in secrets) {
      if (secret.isEmpty) continue;
      output = output.replaceAll(secret, '<REDACTED>');
    }
    return output;
  }
}

