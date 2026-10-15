# CY-HANDOFF: IOS — 统一范围、状态与证据入口

更新：2026-10-15 UTC。**这是文档整合，不是新功能交付或业务验收。** 当前源码核对基线为 `migration/native-ios@7c21af4572ce6084a9cc7b87129aa2c5ececadeb`，tree `17ad90730eba744fd9eb37612038174db7aaa11a`。本文后续文档提交不改变该源码证据基线。未合并 main，未部署，未进行应用签名或应用发布；能力门禁保持原状。

## 先读什么

1. **先读本页**：确认范围、当前 SHA、12 张复核卡和后端依赖。
2. **按任务读本页链接的模块说明及源码**：既有实现先复用，文档中的“已实现”仅对其列明的切片和证据有效。
3. **适配前读取共用后端当前记录**：[BACKEND_CHANGES](https://github.com/liboyang42-cpu/hengyin/blob/codex/mini-bugs-backend-cloud-plan-20261015/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md) 与 [OWNERSHIP](https://github.com/liboyang42-cpu/hengyin/blob/codex/mini-bugs-backend-cloud-plan-20261015/docs/plans/mini-codex-cloud-20261015/OWNERSHIP.md)。固定快照见下一节；移动分支可能已更新，不能把本页当实时通知。
4. **需要追溯时再读历史**：[PROGRESS](../PROGRESS.md)、[迁移计划](migration-plan.md)、[历史覆盖报告](migration-coverage.md)、[历史覆盖数据](migration-coverage-data.json)、[词法源清单](source-inventory.json)。这些文件保留原文；不再从其中摘取旧数作为当前剩余量。

## 范围与计数：只有一套原计划

- 原《Questify城瘾全面改革施工计划》的 **176 项仍是总范围**；I00–I11 是同一工作的 **12 张复核/优化卡**，不是额外 12 项产品需求，也不是已复现的 12 个 bug。它们与原工作包、页面、玩法交叉，不能相加或凭卡片完成数换算百分比。
- 176 项逐项原文、当前源码映射及验收分母在本公共仓库中 **尚未形成可独立核验的完整对照**。本次只核对总范围关系，没有完成176条与当前正文逐条匹配，也未签发逐条 I/BK 映射。本页只声明范围关系，不发布逐项完成/剩余计数，也不复制未验证公开来源的原文。原文身份存在版本精度差异：文件记录版本 10、封面版次 9（2026-10-09），保留这一差异，不改称“正文第10版”。
- [原公开 iOS 交接](https://github.com/liboyang42-cpu/hengyin/blob/7cda068a98f463d453b94378e41ffbbd6b3acb26/docs/plans/mini-codex-cloud-20261015/IOS_HANDOFF.md)明确要求接续现有分支，不重新迁移。旧迁移计划继续提供架构与范围背景；本页统一当前状态，逐模块文档提供具体证据。
- `source-inventory.json` 固定 Flutter `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`，只记录词法目录/声明；`migration-coverage-data.json` 是 2026-10-01 的原生 `a17b4ff` 静态审计。均未在本次重新生成，不是当前页面或业务覆盖率。
- 本地累计交付路径 **131 → 139** 是集成集合的文件路径变化，仅用于交付身份核对，既不是剩余任务数，也不是总需求数或验收通过数。本页没有重新审计全树代码完成数量。

## 当前后端事实及优先级

协议：CY-COORD-20261015-v1。本页只维护 iOS 专属文档；共用后端及控制日志由 C00/C99 和已登记原所有者维护，不因 iOS 消费合同而转移写权。

本次已直接读取控制提交 `f9823c6afbead694f048b9d950b0f8c2d42777fb` 的 [BACKEND_CHANGES](https://github.com/liboyang42-cpu/hengyin/blob/f9823c6afbead694f048b9d950b0f8c2d42777fb/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md) 和 [OWNERSHIP](https://github.com/liboyang42-cpu/hengyin/blob/f9823c6afbead694f048b9d950b0f8c2d42777fb/docs/plans/mini-codex-cloud-20261015/OWNERSHIP.md)。

- **执行发布记录优先于同文件后面的初始规划。** GPS / LIKE / BADGE / AUTHOR / ASSET / SCHEDULE / PRIVACY / SESSION / NARRATIVE 已列 CONTRACT_FROZEN；AI 和 EXISTING 仅限记录中已明确的部分。CLAIM-MATERIAL / AI-DELETE / AI-VOICE 仍 DRAFT。
- 业务/测试源码候选为 `c24202f659e8709a00b513b8e456d101a6b99daf`。本次读取 [PR18](https://github.com/liboyang42-cpu/hengyin/pull/18) 时，其头为 `69c281af1ecc3493db5614b74e494b91c7bb0656`，正文说明后续提交同步控制文档。PR 仍 open draft / UNMERGED；这三个 SHA 分别指控制、业务和 PR 头，不能互换。
- 所有 TEST_DEPLOYED 为 NO；部署 NOT_VERIFIED。冻结只允许针对确切合同进行源码/fixture 适配，不代表原生执行、真实账号/provider、业务独立读回或发布已通过。未重新读取的 CI 状态不在本页签收。
- 开始新适配前复核对应 BK 的确切字段、单位、错误、权限、版本/请求身份、兼容向量和所有权。遇到更新或冲突，记录新 SHA 后处理，不猜测字段、不放开生产开关。

### 历史状态为何不同

[I01 原交付](ios-i01-native-location-callback.md)在控制 `7cda068` 时记录 BK-GPS DRAFT；[I09 原交付](ios-i09-series-time-handoff.md)在控制 `a8865e69c50ed680bcb1d5157705f99c1ca2fa18` 时明确记录 OWNERSHIP 已冻结、旧逐 BK 日志尚未同步的差异。这些是当时证据，保留不改写。现在 `f9823c6` 的执行区已明确逐 BK 冻结，前述文档漂移已在当前控制记录中澄清；这并不补成部署或原生测试证据。

## I00–I11 当前对照

“待复核”表示本次没有该整卡的新验收证据，不表示既有实现不存在。各模块说明与源码是复核入口，不是整卡完成凭据。完整验收要求见原公开交接；下表只压缩导航与下一步边界。

| 卡 | 现有入口与当前证据 | 后端依赖 / 下一步与未闭合项 |
|---|---|---|
| I00 接续与准入 | 本页固定当前分支/SHA；[CN 会话合同](cn-native-session-contract.md)、[作用域源码](../Core/RegionalSessionStorageScope.swift) | C00；仅基线记录已建立。实际运行包、批准端点、账号/realm/role 读回未验；无证据保持 OFF |
| I01 GPS与坐标 | [回调隔离修复](ios-i01-native-location-callback.md)已远端提交于 `8c24b744ebad3c6a71350f4992035ff5704fb52a`；[测量精度/时间适配](ios-i01-location-fidelity.md)基于 `b6720951` 为当前本地源码候选，NOT_PUSHED，待独立复核 | BK-GPS 冻结阻塞已解除；重新核对控制 `ab377921` 和候选 `1e403b13`，accuracy 原值贯通 provider→projection→evidence→请求，时间只在本地，旧 UNKNOWN 身份/请求体不变。后端 SOURCE_READY 仅限其 CI 范围，TEST_DEPLOYED NO；本地 Swift/AppUnit/设备均 NOT_RUN，生产仍 OFF |
| I02 未知写入与账号 | [原命令回执恢复修复](ios-i02-session-receipt-recovery.md)基于已发布 `0f2f0eb5`，本次源码候选待独立复核/推送；复用原 receipt/retryExact | A01 / BK-SESSION；控制 `3783d0fd`、候选 `1e403b13`。回执/view 失败不清原 pending，刷新先核原回执，APPLIED 后只补同局投影；13 个回归方法已编写，所有测试/构建 NOT_RUN，TEST_DEPLOYED NO。跨进程/双设备及整卡仍待验，能力保持 OFF |
| I03 作者保存与媒体 | [作者模块](template-authoring-migration.md)、[发布回执](../Core/TemplateAuthoringPublishReceipt.swift)；整卡待复核 | B02/A03 / BK-AUTHOR、BK-NARRATIVE；保存重开、重排/媒体未知、旧局兼容与真实 ID 读回。首次 create 丢响应仍未知 |
| I04 订单与资产 | [订单模块](order-lifecycle-module.md)、[钱包集成](wallet-commerce-integration.md)；既有原生能力保留，整卡待复核 | B03 / BK-ASSET；报价/退款/账本独立读回、SDK回跳及并发待验。无新收费、支付或出金授权 |
| I05 私密引用与撤回 | [Square 模块](square-module.md)、[Square 协调器](../Core/SquareWorkspaceCoordinator.swift)；整卡待复核 | B05 / BK-PRIVACY；两身份、撤回后旧链接与媒体缓存访问待验；本机隐藏不代替服务端鉴权 |
| I06 音频与生命周期 | [原生平台适配器](../App/NativePlatformAdapters.swift)、[NPC 设备适配器](../App/MerchantNPCVoiceDevice.swift)；已有中断实现，整卡待复核 | 可独立进行原生回归；离页/中断/恢复/资源释放需设备证据，不照抄 wx 生命周期 |
| I07 徽章积分榜单 | [钱包集成](wallet-commerce-integration.md)、[漫游模块](roam-experience-module.md)；整卡待复核 | BK-BADGE、BK-ASSET、BK-EXISTING；平台/俱乐部 scope、缓存、全量与分页读面分别核，不发明统一分页 |
| I08 AI与NPC数据 | [NPC 数据模型](../Core/NPCChatData.swift)、[数据页面](../App/NPCChatDataView.swift)；已有 export 读面，整卡待复核 | A02 / BK-AI、BK-EXISTING；未知用量不能显示真实0。日志删除接口不证明回执清除/晚到写屏障；AI-DELETE/AI-VOICE 仍 DRAFT |
| I09 排期与团队 | [时刻读回修复](ios-i09-series-time-handoff.md)已远端提交于 `7c21af4572ce6084a9cc7b87129aa2c5ececadeb`；[团队模块](team-module.md)保留 | B04 / BK-SCHEDULE；本次仅系列 startTime 源码/fixture 适配。团队迟到轮询、allowedActions/候补保护、设备及后端独立读回仍待验 |
| I10 交互与性能 | [原生验证对照](native-verification-parity.md)、[无障碍测试源码](../Tests/AppUITests/AccessibilityPresentationFlowTests.swift)；整卡待复核 | 可独立核；普通入口、VoiceOver/大字/Reduce Motion、地图/列表性能需同场景设备证据，源码数量不代表表现 |
| I11 候选新入口 | [群投票](group-polls.md)、[漫游体验](roam-experience-module.md)、[创作内容](creator-content-integration.md)已有切片 | BK-EXISTING；逐项判已有/部分/未纳入/依赖，先确认原授权范围，不把小程序未露出变成 iOS 删除依据或新增需求 |

### 两个已远端提交源码切片的精确限制

- **I01 / 8c24b744**：旧 CLLocationManager 回调不能消费后继捕获；取消受捕获代际隔离。三参数输出、WGS84 标签、原坐标/投影策略及请求字段未变。三个 AppUnit 用例已编写，未执行。其完成不等于 GPS 整卡验收。
- **I09 / 7c21af45**：update 只接收有效 HH:mm；缺失/null/错误类型/非法格式保持未知并要求明确选择；create 仍默认 09:00。既有日期不改时刻，原缺陷在新增日期可能使用错误默认时间。CAS、权限与请求字段不扩展。确切适配来源为 B04 候选 `c236f131b19111138d5d6443fa18441f1adb68de` 的合同，后续当前控制冻结不追溯替换原证据。
- I09 的三个新增源码契约检查与结构检查通过；更广 club 检查仍有与未改基线一致的 14 failures / 8 errors / 4 skips，不能称整体绿。详情及原始检查口径保留在切片文档。

## 证据层级与后续更新

本次只验证文档变更范围、相对链接和历史正文保留。I01/I09 的 Python/结构检查是既有交付证据，不是此次重跑结果。以下在该当前源码基线上均没有本次新运行证据：Swift/Core XCTest、AppUnit、XCUITest、Xcode 构建、模拟器、真机/无障碍、真实账号/provider/支付、后端集成/独立业务读回、部署、签名与发布。历史绿灯不能移给新 SHA，跳过也不是通过。

小程序仅作只读语义对照：[玩家路径](player-journey-parity.md)、[成员模板读面](member-template-read-parity.md)、[俱乐部报名](club-enrollment-parity.md)。各文件的源快照/日期须逐一核实；不以小程序组件或范围裁决替换原生设计。Flutter 保留为历史源清单，本轮不改 Flutter。

后续每次交付在本页更新相应卡的确切 iOS SHA、关联 BK/后端 SHA、改动路径和实际执行证据；保留原交付文档，不以新概述覆盖历史。源码适配、原生运行、目标部署和业务验收分别记账。无需重写全部旧文档，也不因这次整合释放已有文件锁或扩大任何写入授权。
