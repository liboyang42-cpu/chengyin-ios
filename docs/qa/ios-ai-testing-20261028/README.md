# 城瘾 iOS AI 自动化测试体系实施计划

本目录是只读审查结果与待实施计划，范围仅原生 iOS。首期按一台 Mac 设计，保留第二台 Mac 扩展。

## 从这里开始

- **[完整实施计划](implementation-plan.md)**：14 个部分、业务状态台账、架构、工具比较、26 项任务、双端消息示例及 Agent 任务包。
- [交互阅读版 HTML](questify-ios-ai-testing-plan.html)：下载后可离线打开，带场景筛选。
- [92 条完整字段测试场景](test-cases.json)：全部为 `PLANNED_NOT_RUN`，覆盖 A–L 与补充治理域。
- [审查证据摘要](audit-evidence.json)：固定 SHA、环境观测和执行状态。
- [全部文件 ZIP](questify-ios-ai-testing-packet.zip)。

## 审查身份与边界

- 源码基线：`liboyang42-cpu/chengyin-ios` 的 `migration/native-ios@76ce1b313af2595f9b7d7ace49040866209c7974`。
- 审查日期：2026-10-28，America/Los_Angeles。
- 原生测试、真实后端调用、多设备验收：本次均未运行；未安装测试工具，未修改产品源码。
- 92 条是首批场景集，不是穷尽所有状态组合，也不是通过数。未实现、未合并和合同不明确的能力保留阻断。
- 用户更新为已清理 70GB、升级 Xcode 27；当前会话仍观测到 Xcode 26.6/较低磁盘余量，差异待实际执行主机确认。

## 核心结论

主方案采用现有 XCTest/XCUITest、agent-device 和轻量确定性协调器；MobileBuildMCP 按需负责构建诊断。首个跨设备里程碑为双账号消息收发、服务端回读、断线补偿和重启恢复。

当前基线普通启动未配置 reviewed deployment；消息 HTTP 发送/历史已存在，但接收方自动同步、重连补偿未接通，对端已读合同不足。详细事实和文件行号见正文与各域审查。

## 源码与官方资料审查

- [账号消息社交与组队](source-audit/identity-messaging.md)
- [玩法漫游 NPC 与赛季](source-audit/gameplay.md)
- [商家俱乐部创作者与交易](source-audit/business.md)
- [工具选型与官方来源](source-audit/tools.md)

本目录仅增加文档和场景设计，不包含可运行的 E2E 基础设施，也不改变任何生产能力门禁。
