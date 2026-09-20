import 'dart:async';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/environment_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/workspace_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../utils/app_directories.dart';
import '../../home/utils/model_display_helper.dart';
import '../models/agent_task.dart';
import '../providers/agent_task_provider.dart';
import 'agent_context_materializer.dart';
import 'agent_model_bridge.dart';
import 'agent_task_journal.dart';
import 'pi_binary_installer.dart';
import 'pi_rpc_session.dart';

class AgentTaskRunner {
  AgentTaskRunner({
    required this.tasks,
    required this.journal,
    required this.workspaces,
    required this.assistants,
    required this.chat,
    required this.contextMaterializer,
    required this.settings,
    required this.runtimeProvider,
    required this.environment,
    required this.piInstaller,
  }) {
    recovery = _recoverUnownedTasks();
  }

  final AgentTaskProvider tasks;
  final AgentTaskJournal journal;
  final WorkspaceProvider workspaces;
  final AssistantProvider assistants;
  final ChatService chat;
  final AgentContextMaterializer contextMaterializer;
  final SettingsProvider settings;
  final WorkspaceRuntimeProvider runtimeProvider;
  final EnvironmentProvider environment;
  final PiBinaryInstaller piInstaller;

  late final Future<void> recovery;
  final Map<String, PiRpcSession> _sessions = <String, PiRpcSession>{};
  final Set<String> _running = <String>{};
  final Set<String> _cancelled = <String>{};

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
        currentStep: 'Preparing Pi runtime',
      );

      await runtimeProvider.initialization;
      final runtime = runtimeProvider.runtime;
      if (runtime is! WorkspaceStdioRuntime) {
        throw StateError('agent_stdio_runtime_unavailable');
      }
      final status = await runtime.status();
      if (!status.ready) {
        throw StateError(status.reason ?? 'agent_environment_not_ready');
      }

      await workspaces.loaded;
      final workspace = workspaces.byId(task.workspaceId);
      if (workspace == null) throw StateError('agent_workspace_missing');
      final workspaceRoot = await workspaces.hostRootFor(workspace);
      final taskDir = await AppDirectories.agentTaskDir(task.id);
      final installation = await piInstaller.ensureInstalled(
        environmentId: task.environmentId,
      );
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
        skillIds: assistant?.skillIds.toSet(),
        mcpServerIds: conversation?.mcpServerIds.toSet(),
      );

      await settings.loaded;
      final selectedModel = resolveChatModel(
        settings,
        conversation: conversation,
        assistant: assistant,
      );
      final providerKey = selectedModel.providerKey;
      final modelId = selectedModel.modelId;
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
      await modelBridge.writePiConfig(
        taskDirectory: taskDir,
        endpoint: modelEndpoint,
      );

      final mounts = <Mount>[
        Mount(host: workspaceRoot, guest: '/workspace'),
        Mount(host: taskDir.path, guest: '/kelivo-agent-task'),
        installation.asMount(),
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
        appendSystemPrompt: materializedContext.guestPromptFile,
        skills: [
          for (final skill in materializedContext.skillMounts)
            skill.guestDirectory,
        ],
        extraArgs: const <String>[
          '--provider',
          'kelivo',
          '--model',
          'current',
        ],
        mounts: mounts,
        environment: <String, String>{
          ...execution.variables,
          'PI_CODING_AGENT_DIR': '/kelivo-agent-task/pi-config',
        },
      );
      _sessions[taskId] = session;

      final agentEnd = Completer<void>();
      Future<void> eventTail = Future<void>.value();
      subscription = session.events.listen(
        (event) {
          eventTail = eventTail
              .then((_) async {
                final ended = await _handleEvent(taskId, session!, event);
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
                session?._exitDescriptionForRunner() ?? 'pi_rpc_closed',
              ),
            );
          }
        },
      );

      await tasks.setPhase(
        taskId,
        AgentTaskPhase.running,
        currentStep: 'Pi is working',
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
        currentStep: 'Verifying Pi session state',
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
      await subscription?.cancel();
      if (session != null) {
        await session.close();
      }
      await modelBridge?.close();
      _sessions.remove(taskId);
      _running.remove(taskId);
    }
  }

  Future<void> cancel(String taskId) async {
    await recovery;
    _cancelled.add(taskId);
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
    Map<String, dynamic> event,
  ) async {
    final type = event['type']?.toString();
    switch (type) {
      case 'agent_start':
        await tasks.setPhase(
          taskId,
          AgentTaskPhase.running,
          currentStep: 'Pi is working',
        );
      case 'tool_execution_start':
        final tool = event['toolName']?.toString() ?? 'tool';
        await tasks.setPhase(
          taskId,
          AgentTaskPhase.running,
          currentStep: 'Running $tool',
        );
        await journal.append(
          taskId,
          AgentTaskEventKind.toolStarted,
          payload: <String, dynamic>{'tool': tool},
        );
      case 'tool_execution_end':
        final tool = event['toolName']?.toString() ?? 'tool';
        await journal.append(
          taskId,
          AgentTaskEventKind.toolFinished,
          payload: <String, dynamic>{
            'tool': tool,
            'isError': event['isError'] == true,
          },
        );
      case 'extension_ui_request':
        await _handleExtensionUi(taskId, session, event);
      case 'agent_end':
        return true;
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
      currentStep: 'Pi requested user input',
    );
    await journal.append(
      taskId,
      AgentTaskEventKind.approvalRequested,
      payload: <String, dynamic>{'method': method},
    );

    final id = event['id']?.toString();
    if (id != null && id.isNotEmpty) {
      await session.respondToExtensionUi(<String, dynamic>{
        'type': 'extension_ui_response',
        'id': id,
        'cancelled': true,
      });
    }
    await journal.append(
      taskId,
      AgentTaskEventKind.approvalResolved,
      payload: const <String, dynamic>{'cancelled': true},
    );
    await tasks.setPhase(
      taskId,
      AgentTaskPhase.running,
      currentStep: 'Pi is working',
    );
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

extension on PiRpcSession {
  String _exitDescriptionForRunner() {
    final code = exitCode;
    final stderr = stderrTail.trim();
    final base = code == null ? 'pi_rpc_closed' : 'pi_rpc_exit_$code';
    return stderr.isEmpty ? base : '$base:$stderr';
  }
}
