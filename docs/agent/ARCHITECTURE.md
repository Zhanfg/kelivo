# KELIVO Agent Runtime Foundation

This document records the invariants for KELIVO Agent mode. It intentionally
describes product boundaries rather than exposing Linux as a user-facing
feature.

## Product boundary

KELIVO is the only user interface. Users interact with chats, projects, tasks,
activity, changes, artifacts, and extensions. The Linux userspace, syscall
compatibility layer, package manager, and Pi worker are implementation details.

The control plane stays in KELIVO. The hidden Linux environment is an execution
backend for code and tools.

## Persistence invariants

Runtime process lifetime, environment lifetime, and workspace lifetime are
separate.

- Runtime processes, PTYs, pipes, sockets, and /tmp may be destroyed.
- Agent tasks are durable and survive process/app/device restarts.
- Execution environments are durable by default.
- Installed packages, language runtimes, toolchains, HOME state, and expensive
  package/build caches survive task completion and runtime restart.
- Workspace files never belong to a disposable runtime process.
- A later task attached to the same workspace sees files created by earlier
  tasks without an export/import step.
- A task binds explicitly to a workspace and an environment.
- Runtime recovery must not infer task state solely from chat history.

Persistent Agent data lives under the normal KELIVO application data root, not
the platform cache directory. User-visible project data may later be linked to
an external SAF-backed directory when the user wants it to outlive app
uninstallation.

## Existing KELIVO systems remain authoritative

Agent mode must reuse rather than fork these systems:

- Memory V2 is the Agent memory source.
- SkillsService owns installed skills. Sandboxed execution sees the same skill
  files through the existing read-only /skills mapping.
- McpProvider owns MCP configuration, OAuth state, tool metadata, and approval
  flags. Secrets are not copied into guest files.
- WorkspaceProvider owns managed and linked workspaces.
- AgentRuntimeBootstrap owns Agent execution environments independently from the
  user-facing Workspace/Environment feature. Generic Workspace Linux state must
  never be a prerequisite for Agent mode.
- The existing model/provider layer remains independent from the Agent harness.

Structured task, project, process, and environment state must not be encoded as
LLM memory when KELIVO can store it explicitly.

## Task lifecycle

Initial durable states:

- queued
- preparing
- running
- waitingApproval
- verifying
- paused
- completed
- failed
- cancelled
- interrupted
- recovering

A worker crash converts active unowned work into interrupted; it does not
delete the workspace or environment. Recovery attaches a new worker to the
same durable task bindings.

## Filesystem model

The intended guest view is stable even if the runtime implementation changes:

- /workspace: persistent project/workspace data
- /home/kelivo: persistent environment-owned user data
- /skills: KELIVO-owned shared skill data, read-only to the guest
- /tmp: ephemeral scratch space
- /run: ephemeral process/runtime state

A no-root Android implementation must not depend on kernel OverlayFS. The fast
path should resolve guest paths onto ordinary files in KELIVO-owned storage so
normal file descriptors use the host kernel directly.

## Network model

Default networking follows the Android host network directly. The data path
must not add a second NAT/proxy layer merely to make the guest look like a VM.

A KELIVO network control plane may intervene for Android DNS and Private DNS
semantics, HTTP/PAC proxy integration, network/VPN selection, per-task/domain
permission policy, and connectivity/metered-network state.

Once a managed connection has been established, normal I/O should remain on the
kernel fast path whenever possible.

## Runtime compatibility

The runtime targets capability detection rather than Android/kernel version
branches. The baseline is Android API 26 with Linux 4.9 semantics; newer
syscalls are accelerators, never hard requirements.

The Android Agent image is Wolfi-based: glibc userspace, apk package management,
and a minimal package set embedded into the APK. It is installed automatically
into KELIVO-owned persistent storage; users do not select or install a Linux
distribution for Agent mode.

The long-term fast runtime should selectively translate guest namespace/path
operations while allowing ordinary fd I/O, sockets, mmap, futex, epoll, and
other safe hot-path syscalls to execute directly. PRoot remains a compatibility
backend, not the product identity or performance target.

## Agent harness

KELIVO Pi is the planned reasoning/execution harness. Pi must be replaceable
without changing task, workspace, memory, extension, or environment ownership.

Useful capabilities to port or implement incrementally include planner with
durable step state, long-lived process management, subagents, LSP/DAP,
worktree-backed parallel tasks, diff/review/rollback, crash-safe checkpoints,
artifact provenance, environment review, provider handoff, and Android-aware
background execution.

## Environment journal and diff

Source-code diff alone is insufficient. Agent tasks can also mutate the
execution environment.

The environment layer should eventually journal package installs/removals,
language-runtime changes, configuration changes, and cache ownership. A task
result can therefore show both workspace changes and environment changes.

Environment mutations should be transactional where practical and support a
checkpoint/rollback path. Package/download blobs may later use a shared
content-addressed store while the active rootfs remains a normal directory for
I/O performance.

## Resource and reliability features

High-value additions for Agent mode:

- Resource governor with per-task CPU/RAM/storage/network budgets and
  thermal/battery-aware throttling.
- Warm environment policy that hibernates workers without deleting data.
- Capability graph so planning sees actual device/runtime/network/extensions
  capabilities instead of guessing from Android versions.
- Workspace lease to prevent accidental concurrent writes; Git worktrees for
  intentional parallel work.
- Offline continuation for local steps while network-dependent work is paused.
- Context budgeter for chat, memory, project instructions, files, and tools.
- Process lease for long-running servers with restart descriptors.
- Artifact provenance linking outputs to task, checkpoint, command, and hash.
- Extension provenance, permission scopes, and explicit host/guest targets.
- Hidden runtime health checks and environment repair.

## Security boundary

Root is optional enhancement only. Normal Agent operation must work without it.

KELIVO is the authority for approval policy, Android host capabilities, secrets,
OAuth/session credentials, extension registration, and task ownership.

Guest processes receive the minimum capability required for the current task.
Long-lived credentials must not be persisted as plaintext in the Linux
filesystem.
