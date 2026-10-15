# Kelivo 功能时间线 × 源码审查（2026-10-15）

> 范围：`Zhanfg/kelivo`，以 PR #17 / `fix/ci-runtime-baseline-20261014` 为审查基线。用户历史需求是验收标准，不把此前某次助手声称的“已完成”当作事实证据。以下仅表示源码存在性、自动化测试覆盖及缺口；非真机验收报告。

## 一、需求时间线与当前实现状态

| 时间 / 需求阶段 | 功能与原始约束 | 当前源码证据 | 状态与尚缺验证 |
| --- | --- | --- | --- |
| 8 月上旬，跨平台统一客户端 | Android + Windows 安装包；桌面统一风格；工作区、文档、搜索、Agent、Workflow、模块沙箱、迁移都在 1.0 范围内 | `lib/features/workspace/`、`lib/core/services/workspace/`、`lib/features/agent/`；CI 有 ARM64 APK 工作流 | **部分实现**。Windows 安装器、端到端 Workflow/模块沙箱以及完整文档格式验收，不可由 Android APK CI 推导为完成 |
| 8 月下旬，Android UI 重构 | Material 3 Expressive + Monet 动态取色；紧凑一致的输入框、菜单和原生交互；聊天/故事分离并可转换 | `lib/main.dart` 的 DynamicColorBuilder；`lib/theme/theme_factory.dart` 的 `useMaterial3`；`lib/features/home/`；`docs/composer_v8_native_audit.md` | **底层主题存在**。M3 不是 M3 Expressive 视觉一致性证明；缺 Android 8/12/17 真机主题、暗色、输入框与分辨率/字体缩放截图验收 |
| 8 月末至 9 月，Story Runtime | Chat↔Story、World Tree checkpoint/fork/rewind、worldline-aware memory、角色、Data Bank、Skills、MCP Profiles、引用、结构化输出、TTS | `story_mode_transition_service.dart`、`story_world_tree_coordinator.dart`、`story_worldline_memory.dart`、`story_native_lifecycle_bridge.dart`、`story_narrative_view.dart`；`message_generation_service.dart` 注入 Story prompt | **主要源码模块已存在**，但侧车提交的崩溃恢复、分支数据隔离、长篇多轮 consistency、voice context 真实播放仍需端到端验证 |
| 9 月 19–23 日，Agent Core | 无 Root；隐藏较新轻量 Linux（非 Debian），不暴露独立终端界面；长期持续的项目/环境/扩展与任务状态；OOM/进程死亡可恢复 | `agent_runtime_bootstrap.dart` + Wolfi + PRoot、`AgentTaskJournal`、`AgentTaskRunner`、`AgentModePage`；任务数据持久化 | **ARM64 基础设施部分具备**，却不等于持续运行/无损恢复；仅自动置为 interrupted，再次 `run()` 仍提示原始目标，存在重复执行风险；根目录更新与用户环境独立性未做真机验证 |
| 同期，Android 广泛支持 | Android 8–17、Linux 4.9–7.x、不同手机 ABI，不要求 Root | `agent_runtime_bootstrap.dart` 在 probe 后仅接受 `arm64-v8a/arm64` | **未达到全 ABI 要求**。ARM32/x86_64 Agent 当前是显式 unsupported；Android 版本与内核兼容尚无跨设备矩阵 |
| 同期，Agent 模型/权限与扩展 | 每任务可复现的模型选择；ReadOnly 不能执行命令；Agent OMP、多 Agent、MCP/GitHub/Skills | `AgentTask` 有持久模型字段；`AgentTaskRunner` 原先没有使用快照、`runShell` 入口缺只读检查 | **本轮已提交修复**：任务创建写入模型快照，Runner 优先使用；direct Shell 在宿主层使用运行会话权限快照验证；日志脱敏。仍需最新 CI 与实际效果验证 |
| 9 月 23 日之后，正式构建 | CI 全通过、能安装、不因升级破坏已有数据 | PR #17 `b3672203` 的三种 Actions 均通过；ARM64 debug APK artifact 已生成 | **构建基线通过**，尚无真机安装/升级迁移与 Story/Agent/MCP 实际工作证据，不可作为正式 1.0 交付 |

## 二、当前审查发现的 P0 / P1 缺口（优先级）

### P0：会造成真实行为与预期不一致

1. **Agent 恢复语义**：`agent_task_provider.dart` 把无主运行任务标为 `interrupted`；`agent_task_runner.dart` 再次运行以 `session.prompt(task.goal)` 重新启动，**没有可证实的持久 RPC 游标和副作用幂等机制**。写文件、执行 shell、GitHub 推送若已经成功但 ack 丢失，重新执行可能再次写入。必须引入步骤 execution ID、确认提交与恢复协议；在完成前不得将“恢复”宣传为无损断点续跑。
2. **Agent 平台适配**：`agent_runtime_bootstrap.dart` 只支持 Android arm64。要支持其它架构和桌面，需要对应 runtime 发行物、架构探测和 CI/设备矩阵，不能仅打包跨 ABI 的 PRoot 库。
3. **真实端到端 Android smoke**：当前 `.github/workflows/pr-check.yml` 在主机上运行 Flutter tests，而 `integration_test/workspace/android_proot_test.dart` 未随 Android 模拟器/实机自动验收。需要新建 Android 启动与 Agent runtime 启动、持久化/断电恢复测试。
4. **Agent 密钥边界**：`agent_task_runner.dart` 把 `execution.variables` 传进 guest 环境，且模型桥接令牌写入任务配置。必须区分普通变量和真正的 secret、校验共享进程访问/日志/目录权限；日志脱敏不能替代隔离。

### P1：功能存在但验收不闭环

5. **Story 一致性与长篇工作负载**：真实 10+ 轮角色/关系/世界书、多 worldline fork、反复 Chat↔Story 转换与 TTS/引用同源语义；覆盖 sidecar commit 失败/进程退出后的恢复。
6. **UI/Monet/Expressive**：按 MD3E 设计核查输入框与导航、动态色/暗色/屏幕方向、字体缩放、桌面客户端；不是 `useMaterial3: true` 就等于完成。
7. **Wolfi 构建可重现性**：`tool/prepare_agent_runtime.sh` 使用 `cgr.dev/chainguard/apko:latest` 和动态包仓，未固定基础镜像 digest/依赖版本；两次同提交可能产生不同 rootfs，必须固定生成链或保存 SBOM/hash 及可复建制品。
8. **1.0 跨平台产品覆盖**：Windows Setup EXE、桌面沙箱/后台、工作区预览（尤其 PDF/EPUB）、Workflow 和迁移验收，必须单独 CI 与真实使用测试；当前 Android 快速构建并不能覆盖。

## 三、本轮已经确证的验证与修复

- PR #17 `b3672203`：`CI`、`PRoot integrity`、`Fast Test APK` 全绿，APK 上传为 `Kelivo-Fast-Test-arm64`。
- PRoot 旧依赖通过来自不可变上游 commit 的小型压缩包恢复，SHA-256 校验，另有历史 APK 兜底。
- 本轮提交：新增任务固定模型标识、Runner 优先使用快照；宿主层禁止 ReadOnly 的直接 Shell；日志避免写入模型桥接令牌及已知环境变量值；补充模型持久化/权限单测。
- 本轮修改后的 CI 状态以对应提交的 Actions 为准，不沿用上一版本绿灯。

## 四、正确的交付门禁

- **G0（源码与 CI）**：Dart format/analyze、全 test shards、PRoot 所有 ABI 校验、Android ARM64 APK 出包。
- **G1（安装启动）**：签名/覆盖安装、Android 启动、Chat/Story 本地数据迁移、首次 Agent rootfs 安装和二次启动持久化。
- **G2（Agent 行为）**：无 Root 权限边界、只读无法执行、模型固定、shell 输出脱敏、OOM/强制退出后任务恢复语义、GitHub MCP/Skills 工作流与安全确认。
- **G3（Story 行为）**：多轮剧情、角色/记忆、世界书、支线、回滚、数据恢复、TTS/引用。
- **G4（1.0 产品）**：Android 8–17 & 架构矩阵、Windows Setup、UI MD3E/动态 Monet、文档/工作区、后台、备份与迁移，逐项通过验收。

**不满足 G1–G4 前，保持 PR 为 Draft；不要将这轮“CI 全绿”作为完整 1.0 已完成的声明。**
