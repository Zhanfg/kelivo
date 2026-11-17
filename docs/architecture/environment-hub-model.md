# Environment Hub：数据模型与后续集成边界

Issue: #123（W21），基础提交：`83d336ca7b78b6c3d95db7cd4e5c962ec617c928`。

## 当前阶段

本 PR **只定义纯 Dart 只读状态快照和协议测试**，不修改现有 `EnvironmentPage`、`EnvironmentPane`、`TerminalPage`、`EnvironmentProvider`、导航、终端或后台服务。

官方已经存在环境设置页、下载与修复流程、多标签交互终端；未来的 Environment Hub 应当**复用**这些功能，而不是平行重做一个安装器。

## 第一版视图

- 环境列表：实例 ID、名称、后端、状态、发行版及版本、磁盘统计。
- 环境详情：已观测的监听端口及其 TCP/UDP、回环限制信息。
- 终端入口：调用已有终端页面，不从快照执行 Shell。
- 安装、重置、修复等修改动作：未来由独立授权控制器执行，不能从快照字段直接触发。

## 安全边界

Android PRoot 不是独立内核 VM，也不天然拥有独立网络命名空间；因此显示 `loopbackOnly` 只代表**观测到的绑定范围**，不代表没有其他进程能够访问。iOS iSH、Windows/Linux/macOS 本地 Shell、SSH/容器由后续运行时适配层按真实能力填充，不能通过数据模型假装存在。

协议采用 `schemaVersion=1` 和明确枚举；未知后端或状态直接拒绝。快照不保存命令、环境变量、主机凭据、SSH 私钥或可直接重用的授权 Token。所有有副作用的操作必须走单独审批通道。

## 后续接入门槛

1. #53 的 Backend 合约和现有 EnvironmentProvider 状态映射完成；
2. UI 只读渲染和独立路由在 Android、iOS、桌面验证；
3. 后台端口/进程观测正确区分共享宿主、PRoot 与 SSH；
4. 任何真实安装/重置仍通过现有确认机制。

此文档不是已实现的 UI 截图，也不是已完成的跨平台验证结果。
