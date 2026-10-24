# KELIVO 上游同步与发行账本 — 2026-10-24

## 发行与分支

- 发行仓库：`Zhanfg/kelivo`，稳定集成目标：`main`。
- GitHub 当前默认分支仍为 `master`；不要将其默认分支身份误认为它包含新集成代码。
- 已发布 ARM64 预览版：`kelivo-preview-20261024-c74edb3e`，源码为 `main@c74edb3eabcfba431eff0222c50d028227ba4125`，**CI Debug 签名，非正式稳定版**。
- 后续已验证集成：`main@d27fdc0c97f8e5e4092269baa96bbe006e289a7c`。其 Preview 2 发布流水线见 [GitHub Actions #40106541052](https://github.com/Zhanfg/kelivo/actions/runs/40106541052)；仅当该运行成功且 Release 资产存在，才可宣称 Preview 2 已发布。

## 已通过自动化并合入 main

| PR | 合并提交 | 改动 | 验证 |
| --- | --- | --- | --- |
| #20 | `f07c51d2` | 上游聊天壁纸对齐、Drift 调用修正、PRoot 下载回退 | Flutter CI + ARM64 APK |
| #21 | `c74edb3e` | Agent 任务快照、权限约束、rootfs 回滚、日志目录安全 | Flutter CI + PRoot Integrity + ARM64 APK |
| #23 | `d27fdc0c` | 官方上游 `cfb82bd` 的工作区能力修复：移动端宽屏内部 PTY、禁止虚假的宿主文件管理器入口，兼容 Agent 沙箱接口 | Flutter CI 四分片 + ARM64 APK |

## 与官方上游的关系

- 本次核对的官方 `Chevey339/kelivo` 最新已知 `master` 提交：`c6383c95b7d5c639bd492c3013d39aa5f97972b4`（2026-10-24）。
- 早前从官方 `199647a5` 产生的**大规模源码快照**：`sync/upstream-full-candidate-20261024`。这不是可直接合并的版本。
- API 对齐候选：Draft PR #22 (`sync/upstream-compat-v2-20261024`)。运行 [Analyzer #40097641660](https://github.com/Zhanfg/kelivo/actions/runs/40097641660) 时仍有 572 项 Dart 错误。禁止为了消除错误而删除 Chat、Story 或 Agent 的能力。
- 继续遵循“从官方挑选独立补丁 → 保留自研边界 → 完整分析、测试、APK → 合入 `main`”的增量同步方式，直到全量冲突按模块收敛。

## 剩余阻塞与验收顺序

1. **Agent P0：** 持久化任务的真实恢复语义、避免执行有副作用的工具步骤被重复重放；用户安装的 guest 包与 rootfs 更新迁移；guest 凭据隔离。
2. **Chat / MCP：** 消息流、Skills、工具权限及 provider 调用的回归；备份还原与数据库迁移。
3. **Story：** 世界线、角色、记忆、TTS 与持久化状态，关闭重进后复验；勿让官方通用聊天接口覆盖 Story 的自研扩展。
4. **Android 真机：** ARM64 APK 签名和原生库检查只证明包可构建，**不等于**真机运行、网络调用、存储读写、长时运行和用户数据安全验证。
5. **正式签名：** 预览 APK 使用 CI Debug 签名，每次运行可能更换证书；正式覆盖升级需要用户自行管理的固定签名证书及密钥保护流程。不可把 Debug APK 冒充稳定版。

## 发布原则

- 不强制修改 `master` 来覆盖 `main`。
- 不把失败的 Draft PR 或编译尚未完成的功能标为可发布。
- 保留每个发行 APK 的源提交、版本号、原生 ABI、签名校验与 SHA-256。
- 在真实设备完整验证前，发行类型只能为 **Preview / Pre-release**。
