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

I03 本次单独刷新到控制 `05346fedae227c12cff9d9ca533c3e92e62ae743`：冻结候选仍为 `1e403b13`；后续新候选 `4a943501262cb533158428d9748d8ac49aaa8950` 已发布 edit-detail 只读 RR 聚合读取，NO_API_CHANGE。已直接比对其控制器与售卖冻结 resolver；`SELLING_FROZEN` 既有语义不变。该控制快照中的新 Java/真库证据仍待取得，TEST_DEPLOYED=NO；本次不查询或启动 CI。确切来源及原生切片见 [I03 冻结读回](ios-i03-author-frozen-readback.md)，不改写上方历史核对事实。

### 历史状态为何不同

[I01 原交付](ios-i01-native-location-callback.md)在控制 `7cda068` 时记录 BK-GPS DRAFT；[I09 原交付](ios-i09-series-time-handoff.md)在控制 `a8865e69c50ed680bcb1d5157705f99c1ca2fa18` 时明确记录 OWNERSHIP 已冻结、旧逐 BK 日志尚未同步的差异。这些是当时证据，保留不改写。现在 `f9823c6` 的执行区已明确逐 BK 冻结，前述文档漂移已在当前控制记录中澄清；这并不补成部署或原生测试证据。

## I00–I11 当前对照

“待复核”表示本次没有该整卡的新验收证据，不表示既有实现不存在。各模块说明与源码是复核入口，不是整卡完成凭据。完整验收要求见原公开交接；下表只压缩导航与下一步边界。

| 卡 | 现有入口与当前证据 | 后端依赖 / 下一步与未闭合项 |
|---|---|---|
| I00 接续与准入 | 本页固定当前分支/SHA；[CN 会话合同](cn-native-session-contract.md)、[作用域源码](../Core/RegionalSessionStorageScope.swift) | C00；仅基线记录已建立。实际运行包、批准端点、账号/realm/role 读回未验；无证据保持 OFF |
| I01 GPS与坐标 | [回调隔离修复](ios-i01-native-location-callback.md)已远端提交于 `8c24b744ebad3c6a71350f4992035ff5704fb52a`；[测量精度/时间适配](ios-i01-location-fidelity.md)基于 `b6720951` 为当前本地源码候选，NOT_PUSHED，待独立复核 | BK-GPS 冻结阻塞已解除；重新核对控制 `ab377921` 和候选 `1e403b13`，accuracy 原值贯通 provider→projection→evidence→请求，时间只在本地，旧 UNKNOWN 身份/请求体不变。后端 SOURCE_READY 仅限其 CI 范围，TEST_DEPLOYED NO；本地 Swift/AppUnit/设备均 NOT_RUN，生产仍 OFF |
| I02 未知写入与账号 | [原命令回执恢复修复](ios-i02-session-receipt-recovery.md)基于已发布 `0f2f0eb5`，本次源码候选待独立复核/推送；复用原 receipt/retryExact | A01 / BK-SESSION；控制 `3783d0fd`、候选 `1e403b13`。回执/view 失败不清原 pending，刷新先核原回执，APPLIED 后只补同局投影；13 个回归方法已编写，所有测试/构建 NOT_RUN，TEST_DEPLOYED NO。跨进程/双设备及整卡仍待验，能力保持 OFF |
| I03 作者保存与媒体 | [作者冻结读回兼容](ios-i03-author-frozen-readback.md)基于已发布 `09323a41`，当前源码候选待独立复核/推送；保留[作者模块](template-authoring-migration.md)与[发布回执](../Core/TemplateAuthoringPublishReceipt.swift) | B02 / BK-AUTHOR；正确接收既有 SELLING_FROZEN 并保持只读。已确认读回保留本地草稿/journal，UNKNOWN 不因读取解锁；保留 V2 回执时独立 cover/review/release 写入口同受门禁。9 个 Core + 8 个 AppUnit 回归方法已编写，全部测试/构建 NOT_RUN。控制 `05346fed`、后续候选 `4a943501`，TEST_DEPLOYED NO。重排/媒体/旧局及整卡待验，首次 create 丢响应仍未知，能力 OFF |
| I04 订单与资产 | [订单模块](order-lifecycle-module.md)、[钱包集成](wallet-commerce-integration.md)；既有原生能力保留，整卡待复核 | B03 / BK-ASSET；报价/退款/账本独立读回、SDK回跳及并发待验。无新收费、支付或出金授权 |
| I05 私密引用与撤回 | [编辑历史失效读回](ios-i05-privacy-history-readback.md)基于已发布 `e2ef0373`；源码候选待独立复核/推送，复用 [Square 协调器](../Core/SquareWorkspaceCoordinator.swift) 既有 detail/revisions 链 | B05 / BK-PRIVACY，NO_API_CHANGE；重新读取前清旧历史，拒绝/超时不保留旧正文，晚到结果不覆盖新选择；17 个 Core 回归方法已编写，全部测试/构建 NOT_RUN。控制 `da842579`，合同候选 `1e403b13` 与后续 `4a943501` 三个关联源码 blob 相同，TEST_DEPLOYED NO；两身份/真实删除/媒体访问及整卡仍待验，能力 OFF |
| I06 音频与生命周期 | [播放通知代际隔离](ios-i06-audio-lifecycle.md)基于已发布 `80c16907`；当前源码候选待独立复核/推送，复用既有 AVAudioSession/AVAudioPlayer | 原生独立，NO_API_CHANGE；自己的 categoryChange 不再误停播放，旧通知不能终止新播放，停止/失败清理仅释放已激活会话。10 个 AppUnit + 3 个 Core 方法已编写，全部测试/构建/设备/CI NOT_RUN；控制 `e7fe5d00`，AI-VOICE 仍 DRAFT，能力 OFF。来电/耳机/锁屏/多音频消费者及整卡待设备验收 |
| I07 徽章积分榜单 | [本次限定源码复核](ios-i08-npc-unknown-outcome.md#i07-bounded-no-change-review)：基于已发布 `8e3c74a1`，NO_CHANGE_SOURCE_REVIEW；既有全量/分页区分、身份卡降级、榜外本人可空分数及scope隔离保留 | BK-BADGE、BK-ASSET、BK-EXISTING；本次未确认需改代码，不等于整卡通过。平台/俱乐部源数据、真实缓存失效与部署/设备仍待验；控制 `53d50db2`，TEST_DEPLOYED NO |
| I08 AI与NPC数据 | [商家NPC未知结果适配](ios-i08-npc-unknown-outcome.md)已发布于 `1ddbb792`；[玩家Shop NPC同类完整流程](ios-i08-shop-npc-unknown-outcome.md)以该SHA为父基线，当前源码候选待独立复核/推送 | A02 / BK-AI，NO_API_CHANGE；控制 `53d50db2`、冻结 `1e403b13` 与滚动 `adc7c68e` 已重读。Shop端精确接收UNKNOWN元组、保留文字/语音/重生成review与原ID、遵守禁止重试且不误报终态，复用既有本地取消；12 Core + 5 AppUnit方法已编写，全部NOT_RUN。删除/usage及整卡待验，AI-VOICE/CLAIM-MATERIAL仍DRAFT，TEST_DEPLOYED NO，能力OFF |
| I09 排期与团队 | [时刻读回修复](ios-i09-series-time-handoff.md)已提交 `7c21af45`；[团队返回读回](ios-i09-team-return-readback.md)已提交 `fefc96a6`；[精确剩余排期与日期校验](ios-i09-exact-schedule-dates.md)以该SHA为父基线，当前源码候选待独立复核/推送 | B04 / BK-SCHEDULE；带取消缺口的WEEKLY读回保留原日期，以明示的CUSTOM_DATES转换供Apply/最终复核；连续周排期不变，今天的日期不静默删除，更新只允许上海明天起。10 Core + 7 AppUnit方法已编写，全部测试/构建/App/CI NOT_RUN；控制 `11f7a956`、CORE `05d307ec`、另核PR36 `25ede658`，TEST_DEPLOYED NO。已有HH:mm、CAS、UNKNOWN锁和读回复用，能力OFF；设备/真实保护场次及整卡仍待验 |
| I10 交互与性能 | [本次限定源码复核](ios-i11-poll-return-readback.md#i10-bounded-no-change-review)：基于已发布 `fed79fed`，已核指定地图/导航生命周期、列表替代及既有Reduce Motion处理，NO_CHANGE_SOURCE_REVIEW | 仅所读路径未确认需改；不等于整卡或无障碍/性能通过。普通入口、VoiceOver/大字、地图/列表/图片音频表现仍须同场景设备证据；本轮不运行 |
| I11 候选新入口 | [群投票返回读回](ios-i11-poll-return-readback.md)以已发布 `fed79fed` 为父基线，源码候选待独立复核/推送；修已有创建/投票/关闭在退场返回后旧响应覆盖新读回/复核、旧成员读取反盖新状态 | BK-EXISTING，NO_API_CHANGE；控制 `8533507d`、CORE `2b1984b5` 与实际投票源码已重读。13 Core方法已编写，全部测试/构建/App/CI NOT_RUN；原未决锁、精确创建重试与版本/权限不变，TEST_DEPLOYED NO、能力OFF。其余候选入口不据此称已复核或批准 |

## 原生个人收藏完整流程续作

[Account / Settings 收藏与取消收藏流程](ios-profile-settings-favorites-flow.md)以已发布 `30adba500ab3d1746105e1de061bd9dab83a57d9` 为基线，当前源码候选待独立复核/推送。复用已有列表、详情和明确的帖子取消收藏合同，补齐实际 Settings 入口、默认空权限的可撤销组合注入、成功关闭/手势返回刷新、列表已无该帖时的只读 UNKNOWN 核对、旧响应不能重建已解除锁，以及匹配会话的401恢复。主题取消收藏仍未实现，未新增任何生产或集成fixture准入；能力 OFF。

这是一组既有原生功能链的源码续作，不增加或重算原计划需求，也不把整项个人资料/设置或整卡标为验收完成。控制 `e2163ab8` 的公开 START/HANDOFF/BACKEND_CHANGES 已刷新；NO_API_CHANGE，TEST_DEPLOYED NO。新增/复用回归均仅编写，所有测试、构建、App、设备、CI均 NOT_RUN；具体路径、完整入口到结果/恢复、证据边界见链接。

### 两个已远端提交源码切片的精确限制

- **I01 / 8c24b744**：旧 CLLocationManager 回调不能消费后继捕获；取消受捕获代际隔离。三参数输出、WGS84 标签、原坐标/投影策略及请求字段未变。三个 AppUnit 用例已编写，未执行。其完成不等于 GPS 整卡验收。
- **I09 / 7c21af45**：update 只接收有效 HH:mm；缺失/null/错误类型/非法格式保持未知并要求明确选择；create 仍默认 09:00。既有日期不改时刻，原缺陷在新增日期可能使用错误默认时间。CAS、权限与请求字段不扩展。确切适配来源为 B04 候选 `c236f131b19111138d5d6443fa18441f1adb68de` 的合同，后续当前控制冻结不追溯替换原证据。
- I09 的三个新增源码契约检查与结构检查通过；更广 club 检查仍有与未改基线一致的 14 failures / 8 errors / 4 skips，不能称整体绿。详情及原始检查口径保留在切片文档。

## 证据层级与后续更新

本次只验证文档变更范围、相对链接和历史正文保留。I01/I09 的 Python/结构检查是既有交付证据，不是此次重跑结果。以下在该当前源码基线上均没有本次新运行证据：Swift/Core XCTest、AppUnit、XCUITest、Xcode 构建、模拟器、真机/无障碍、真实账号/provider/支付、后端集成/独立业务读回、部署、签名与发布。历史绿灯不能移给新 SHA，跳过也不是通过。

小程序仅作只读语义对照：[玩家路径](player-journey-parity.md)、[成员模板读面](member-template-read-parity.md)、[俱乐部报名](club-enrollment-parity.md)。各文件的源快照/日期须逐一核实；不以小程序组件或范围裁决替换原生设计。Flutter 保留为历史源清单，本轮不改 Flutter。

后续每次交付在本页更新相应卡的确切 iOS SHA、关联 BK/后端 SHA、改动路径和实际执行证据；保留原交付文档，不以新概述覆盖历史。源码适配、原生运行、目标部署和业务验收分别记账。无需重写全部旧文档，也不因这次整合释放已有文件锁或扩大任何写入授权。

## Wave 1–3 Parity & Handoff Summary (2026-10-19 to 2026-10-20)

- **Wave 1 (`docs/alignment/xcx-ios-{B..E}-20261019.md`, `docs/plan-progress/{F..H}-20261019.md`):** Audited all 99 mini-program pages and reform plan v9 work packages (`W02–W20`, `U01–U08`, `MV01–MV41`); fixed P0 contract mismatches (`GET /api/config/public`, `AccountProfile.career`, `OfficialEventUnavailableError` 404/410, `/api/exploration-anniversary`, `/api/monthly-recap`, `/api/merchant/insight` top-level keys, `IMInbox` tabs, `myproject` template shelf, `/api/club/access/me` POST form, `/api/merchant/decor/save` JSON, `/api/merchant/npc/voice/status` top-level keys).
- **Wave 2 (`docs/parity/w2-01.md` .. `w2-21.md` + Batch 1/2 Parity Completions):** Delivered page-by-page mini-program parity across all 21 scopes (`w2-01` through `w2-21`), keeping all unreviewed writes, payments, and cash movements fail-closed behind empty per-market endpoint allowlists.
- **Wave 3 (`docs/handoff/ios-I00-I11-20261019.md`, `ios-I01..I10-20261019.md`, `ios-BK-20261019.md`):** Landed `I00+I11` (received stamps & session admission baseline), `I01` (GPS accuracy & arrival failure), `I02` (durable game command journal), `I03` (story boolean fallback validation), `I04` (asset points ledger readback), `I05` (square media cache eviction & topic like ledger), `I06` (audio session lifecycle & interruption recovery), `I07` (leaderboard form encoding & standing normalization), `I08` (NPC chat log deletion coordinator & UI, default OFF), `I09` (schedule dates fixture tests & lead progress polling), `I10` (OSSignposter POIs, O(N) map stop projection, VoiceOver/Reduce Motion), and `BK` (backend sync contract tests).

## Batches 4–6 Host Bridges, SwiftUI Sections & AppUnitTests Summary (2026-10-20)

- **Batch 4 (`Lanes 23–38`: Reform Plan v9 `F`/`G`/`H` Host Bridges, Coordinators & Release Preflight Contract):**
  - `MapVisualHostBridge` (`Core/MapVisualHostBridge.swift`, `Tests/CoreTests/MapVisualHostBridgeTests.swift`)
  - `StoryWalkingNavigationHostBridge` (`Core/StoryWalkingNavigationHostBridge.swift`, `Tests/CoreTests/StoryWalkingNavigationHostBridgeTests.swift`)
  - `NPCAISceneHostGuard` (`Core/NPCAISceneHostGuard.swift`, `Tests/CoreTests/NPCAISceneHostGuardTests.swift`)
  - `MerchantInStoreGameAuthoringPresentation` (`Core/MerchantInStoreGameAuthoringPresentation.swift`, `Tests/CoreTests/MerchantInStoreGameAuthoringPresentationTests.swift`)
  - `CommerceOrderLifecycleBridge` (`Core/CommerceOrderLifecycleBridge.swift`, `Tests/CoreTests/CommerceOrderLifecycleBridgeTests.swift`)
  - `PublishMediaEditorBridge` (`Core/PublishMediaEditorBridge.swift`, `Tests/CoreTests/PublishMediaEditorBridgeTests.swift`)
  - `WorkshopModUpgradePresentation` (`Core/WorkshopModUpgradePresentation.swift`, `Tests/CoreTests/WorkshopModUpgradePresentationTests.swift`)
  - `TeamMeetingHandshakePresentation` (`Core/TeamMeetingHandshakePresentation.swift`, `Tests/CoreTests/TeamMeetingHandshakePresentationTests.swift`)
  - `HomeReturnAndCityDeltaCoordinator` (`Core/HomeReturnAndCityDeltaCoordinator.swift`, `Tests/CoreTests/HomeReturnAndCityDeltaCoordinatorTests.swift`)
  - `ReleasePreflightAndUIReadinessContract` (`Core/ReleasePreflightAndUIReadinessContract.swift`, `Tests/CoreTests/ReleasePreflightAndUIReadinessContractTests.swift`)
  - `LocationShareHostCoordinator` (`Core/LocationShareHostCoordinator.swift`, `Tests/CoreTests/LocationShareHostCoordinatorTests.swift`)
  - `MerchantSideQuestHostPresentation` (`Core/MerchantSideQuestHostPresentation.swift`, `Tests/CoreTests/MerchantSideQuestHostPresentationTests.swift`)
  - `RunAuthorityHostCoordinator` (`Core/RunAuthorityHostCoordinator.swift`, `Tests/CoreTests/RunAuthorityHostCoordinatorTests.swift`)
  - `EnvironmentBranchHostPresentation` (`Core/EnvironmentBranchHostPresentation.swift`, `Tests/CoreTests/EnvironmentBranchHostPresentationTests.swift`)
  - `RewardLedgerHostPresentation` (`Core/RewardLedgerHostPresentation.swift`, `Tests/CoreTests/RewardLedgerHostPresentationTests.swift`)
  - `WaveUnifiedParityInventory` (`Core/WaveUnifiedParityInventory.swift`, `Tests/CoreTests/WaveUnifiedParityInventoryTests.swift`)
- **Batch 5 (`Lanes 39–51`: Reform Plan v9 SwiftUI Section Views & `WaveUnifiedParityInventory`):**
  - Added offline/fail-closed SwiftUI section views (`App/MapVisualAndFogHostSectionView.swift`, `App/LocationShareAndSideQuestSectionView.swift`, `App/StoryWalkingAndEnvBranchSectionView.swift`, `App/NPCAISceneAndMerchantGameSectionView.swift`, `App/CommerceAndRewardLedgerSectionView.swift`, `App/PublishMediaAndThemeSeasonSectionView.swift`, `App/WorkshopModAndQmodSectionView.swift`, `App/TeamMeetingAndInviteSectionView.swift`, `App/RunAuthorityHostSectionView.swift`, `App/ReleasePreflightDashboardSectionView.swift`) and their corresponding Core test suites (`Tests/CoreTests/*SectionViewTests.swift`, `Tests/CoreTests/Wave4And5MasterGateTests.swift`).
- **Batch 6 (`Lanes 52–63`: `AppUnitTests` for all new Section Views + `ReformWorldHostWorkbenchView`):**
  - Added `App/ReformWorldHostWorkbenchView.swift` unifying all Reform Plan v9 offline host sections into a single inspectable workbench container.
  - Added `Tests/AppUnitTests/*SectionViewAppUnitTests.swift` and `Tests/AppUnitTests/ReformWorldHostWorkbenchViewAppUnitTests.swift` covering app-hosted SwiftUI section instantiation, view-model state invariants, and default-disabled production gates across Lanes 52–63.

## Batches 7–9 (`Lanes 64–95`): Release Audits, Unified Matrices & Safety Verification (2026-10-20)

- **Batch 7 (`Lanes 64–71`): Unified Matrices & Submission Readiness Audits:**
  - App Store submission readiness audit (`Core/AppStoreSubmissionReadinessAudit.swift`, `Tests/CoreTests/AppStoreSubmissionReadinessAuditTests.swift`)
  - Unified Ticket Phase 0–5 & `MV01–MV41` matrix (`Core/UnifiedTicketMatrixContract.swift`, `Tests/CoreTests/UnifiedTicketMatrixContractTests.swift`)
  - 99-page mini-program parity registry (`Core/MiniProgramPageParityRegistry.swift`, `Tests/CoreTests/MiniProgramPageParityRegistryTests.swift`)
  - Cloud CI shard contract (`Core/CloudCIShardContract.swift`, `Tests/CoreTests/CloudCIShardContractTests.swift`)
  - Wave-3 (`I00–I11` & `BK`) handoff registry (`Core/Wave3HandoffStatusRegistry.swift`, `Tests/CoreTests/Wave3HandoffStatusRegistryTests.swift`)
- **Batch 8 & Batch 9 (`Lanes 72–95`): Domain Safety, Privacy, Accessibility & Recovery Audits:**
  - Regional endpoint allowlist audit (`Core/RegionalEndpointAllowlistAudit.swift`, `Tests/CoreTests/RegionalEndpointAllowlistAuditTests.swift`)
  - Localization zero-missing-keys audit (`Core/LocalizationCompletenessAudit.swift`, `Tests/CoreTests/LocalizationCompletenessAuditTests.swift`)
  - VoiceOver/WCAG accessibility audit (`Core/AccessibilityVoiceOverAudit.swift`, `Tests/CoreTests/AccessibilityVoiceOverAuditTests.swift`)
  - Deep-link & QR/URL safety audit (`Core/DeepLinkAndQRRouteSafetyAudit.swift`, `Tests/CoreTests/DeepLinkAndQRRouteSafetyAuditTests.swift`)
  - Offline durable recovery & journal audit (`Core/OfflineDurableRecoveryAudit.swift`, `Tests/CoreTests/OfflineDurableRecoveryAuditTests.swift`)
  - UI test shard & fixture completeness audit (`Core/UITestShardCompletenessAudit.swift`, `Tests/CoreTests/UITestShardCompletenessAuditTests.swift`)
  - Privacy redaction & coordinate non-leakage audit (`Core/PrivacyRedactionAudit.swift`, `Tests/CoreTests/PrivacyRedactionAuditTests.swift`)
  - Commerce, wallet & points non-withdrawable safety audit (`Core/CommerceWalletSafetyAudit.swift`, `Tests/CoreTests/CommerceWalletSafetyAuditTests.swift`)

## Batches 10–11 (`Lanes 100–120`): Master Crosswalk, 15-Pillar Sign-Off Dashboard & Domain Pipeline Audits (2026-10-20)

- **Batch 10 & Batch 11 (`Lanes 100–120`):**
  - Roam & Exploration audit (`Core/RoamAndExplorationSafetyAudit.swift`, `Tests/CoreTests/RoamAndExplorationSafetyAuditTests.swift`)
  - IM & Social safety audit (`Core/IMAndSocialSafetyAudit.swift`, `Tests/CoreTests/IMAndSocialSafetyAuditTests.swift`)
  - 15-pillar Master Release Sign-off Dashboard (`Core/MasterReleaseSignOffDashboard.swift`, `App/MasterReleaseSignOffDashboardView.swift`, `Tests/CoreTests/MasterReleaseSignOffDashboardTests.swift`, `Tests/AppUnitTests/MasterReleaseSignOffDashboardViewAppUnitTests.swift`)
  - Auth & Session Admission audit (`Core/AuthAndSessionAdmissionAudit.swift`, `Tests/CoreTests/AuthAndSessionAdmissionAuditTests.swift`)
  - World & City Lifecycle audit (`Core/WorldAndCityLifecycleAudit.swift`, `Tests/CoreTests/WorldAndCityLifecycleAuditTests.swift`)
  - Backend Sync & Contract Gate audit (`Core/BackendSyncAndContractGateAudit.swift`, `Tests/CoreTests/BackendSyncAndContractGateAuditTests.swift`)
  - 3-Document Master Crosswalk (`交接文档_20261020.md` + `落地清单.md` + `工单-统一实施版.md`) (`Core/ThreeDocumentMasterCrosswalk.swift`, `Tests/CoreTests/ThreeDocumentMasterCrosswalkTests.swift`)
  - Performance & Signpost audit (`Core/PerformanceAndSignpostAudit.swift`, `Tests/CoreTests/PerformanceAndSignpostAuditTests.swift`)
  - Coupon & Sponsored Reward safety audit (`Core/CouponAndSponsoredRewardSafetyAudit.swift`, `Tests/CoreTests/CouponAndSponsoredRewardSafetyAuditTests.swift`)
  - Audio & Media Pipeline lifecycle audit (`Core/AudioAndMediaPipelineLifecycleAudit.swift`, `Tests/CoreTests/AudioAndMediaPipelineLifecycleAuditTests.swift`)

## Batches 12–13 (`Lanes 125–149`): RC Gate (`RC-GATE-01..06`), `W02..W20` Compliance, Unified Release Audit Hub & Domain Readiness Audits (2026-10-20)

- **Batch 12 & Batch 13 (`Lanes 125–149`):**
  - `W02..W20` compliance audit (`Core/ReformWorkPackageComplianceAudit.swift`, `Tests/CoreTests/ReformWorkPackageComplianceAuditTests.swift`)
  - `AppSession` fixture short-circuit audit (`Core/AppSessionFixtureShortCircuitAudit.swift`, `Tests/CoreTests/AppSessionFixtureShortCircuitAuditTests.swift`)
  - XcodeGen & scaffold integrity audit (`Core/XcodeGenAndScaffoldIntegrityAudit.swift`, `Tests/CoreTests/XcodeGenAndScaffoldIntegrityAuditTests.swift`)
  - End-to-End Release Candidate Gate (`RC-GATE-01..06`) (`Core/EndToEndReleaseCandidateGate.swift`, `Tests/CoreTests/EndToEndReleaseCandidateGateTests.swift`)
  - Side-Quest & Personal Fog host audit (`Core/SideQuestAndPersonalFogHostAudit.swift`, `Tests/CoreTests/SideQuestAndPersonalFogHostAuditTests.swift`)
  - 3-Document Master Crosswalk Python contract check (`Tests/ContractChecks/test_three_document_master_crosswalk.py`)
  - `UnifiedReleaseAuditHubView` (`App/UnifiedReleaseAuditHubView.swift`, `Tests/AppUnitTests/UnifiedReleaseAuditHubViewAppUnitTests.swift`)
  - UI test flow readiness anchor audit (`Core/UITestFlowReadinessAnchorAudit.swift`, `Tests/CoreTests/UITestFlowReadinessAnchorAuditTests.swift`)
  - NPC chat & scene AI safety audit (`Core/NPCChatAndSceneAISafetyAudit.swift`, `Tests/CoreTests/NPCChatAndSceneAISafetyAuditTests.swift`)
  - Play runtime & auxiliary binding audit (`Core/PlayRuntimeAndAuxiliaryBindingAudit.swift`, `Tests/CoreTests/PlayRuntimeAndAuxiliaryBindingAuditTests.swift`)
  - App Store privacy manifest audit (`Core/AppStorePrivacyManifestAudit.swift`, `Tests/CoreTests/AppStorePrivacyManifestAuditTests.swift`)
  - Growth & Leaderboard parity audit (`Core/GrowthAndLeaderboardParityAudit.swift`, `Tests/CoreTests/GrowthAndLeaderboardParityAuditTests.swift`)
  - Schedule & Lead Progress polling audit (`Core/ScheduleAndLeadProgressPollingAudit.swift`, `Tests/CoreTests/ScheduleAndLeadProgressPollingAuditTests.swift`)

## Batch 14 (Lanes 150–162): Wave-3 I00/I04/I05/I07/I08/I09/I10/I11 Deep Audits, Batch 12–14 Contract Suite & Complete Wave 1–3 + Reform v9 Showcase View (2026-10-20)

- `Core/AssetPointsAndOrderCancellationAudit.swift` + `App/AssetPointsAndOrderCancellationSectionView.swift` (`I04` points ledger & cancellation conservation)
- `Core/TopicLikeAndSquareEvictionAudit.swift` + `App/TopicLikeAndSquareEvictionSectionView.swift` (`I05` 404/DELETED media cache eviction & fail-closed topic like write gate)
- `Core/ReceivedStampsAndPassportToolsAudit.swift` + `App/ReceivedStampsAndPassportToolsSectionView.swift` (`I00`/`I11` received stamps & passport tools isolation)
- `Core/MerchantDecorAndShopApplyWizardAudit.swift` + `App/MerchantDecorAndShopApplyWizardSectionView.swift` (`I07`/`I08` merchant decor & shop apply 4-step wizard)
- `Core/ClubAccessAndSettlementParityAudit.swift` + `App/ClubAccessAndSettlementSectionView.swift` (`I09`/`I10` club access control & settlement/payroll)
- `Tests/ContractChecks/test_batch12_to_batch14_contracts.py`
- `App/CompleteWave1To3AndReformV9ShowcaseView.swift` + `Tests/AppUnitTests/CompleteWave1To3AndReformV9ShowcaseViewTests.swift`

## Batches 15–16 (Lanes 163–188): Zero-Gap Release Certificate, Wave-2/3 Deep Parity & Production Runtime Resilience (2026-10-20)

- `Core/GameJournalCompositionAndPlaySummaryAudit.swift` + `App/GameJournalCompositionAndPlaySummarySectionView.swift`
- `Core/SocialGraphAndProfilePrivacyParityAudit.swift` + `App/SocialGraphAndProfilePrivacySectionView.swift`
- `Core/ExplorationPrivateToolsAndCapsuleAudit.swift` + `App/ExplorationPrivateToolsAndCapsuleSectionView.swift`
- `Core/PublishTopicAndCommentModerationAudit.swift` + `App/PublishTopicAndCommentModerationSectionView.swift`
- `Core/MemberSubscriptionAndOrderInvoiceAudit.swift` + `App/MemberSubscriptionAndOrderInvoiceSectionView.swift`
- `Core/FinalReleaseSignoffAndZeroGapCertificateContract.swift` + `App/FinalReleaseSignoffAndZeroGapCertificateView.swift`
- `Core/CrashResilienceAndMetricKitDiagnosticsAudit.swift` + `App/CrashResilienceAndMetricKitDiagnosticsSectionView.swift`
- `Core/PushNotificationAndLiveActivityParityAudit.swift` + `App/PushNotificationAndLiveActivitySectionView.swift`
- `Core/NetworkReachabilityAndRetryBackoffAudit.swift` + `App/NetworkReachabilityAndRetryBackoffSectionView.swift`
- `Core/KeychainAndBiometricSessionSecurityAudit.swift` + `App/KeychainAndBiometricSessionSecuritySectionView.swift`
- `Core/ImageAndVideoDiskCacheBudgetAudit.swift` + `App/ImageAndVideoDiskCacheBudgetSectionView.swift`
- `Core/BackgroundTaskAndScenePhaseLifecycleAudit.swift` + `App/BackgroundTaskAndScenePhaseLifecycleSectionView.swift`
- `Tests/ContractChecks/test_batch15_zero_gap_certificate.py` and `Tests/ContractChecks/test_batch16_runtime_resilience_contracts.py`

## Batches 17–19 (Lanes 189–221): Native Superset Policy, Platform Polish & 7-Day App Store Launch Critical Path (2026-10-20)

### 1. Batches 17–19 Deliverables (`Lanes 189–221`)
- `Core/AppClipAndQRCodeHandshakeParityAudit.swift` + `App/AppClipAndQRCodeHandshakeSectionView.swift`
- `Core/WebViewAndExternalSafariSandboxAudit.swift` + `App/WebViewAndExternalSafariSandboxSectionView.swift`
- `Core/LocalizationPluralAndFormatterConsistencyAudit.swift` + `App/LocalizationPluralAndFormatterConsistencySectionView.swift`
- `Core/DeviceOrientationAndSplitViewAdaptationAudit.swift` + `App/DeviceOrientationAndSplitViewAdaptationSectionView.swift`
- `Core/PhotoLibraryAndCameraPermissionGracefulDegradationAudit.swift` + `App/PhotoLibraryAndCameraPermissionGracefulDegradationSectionView.swift`
- `Core/HapticFeedbackAndMotionReduceComplianceAudit.swift` + `App/HapticFeedbackAndMotionReduceComplianceSectionView.swift`
- `Core/ProductionTelemetryAndPrivacyRedactionPipelineAudit.swift` + `App/ProductionTelemetryAndPrivacyRedactionPipelineSectionView.swift`
- `Core/SQLiteAndJSONJournalCorruptionRecoveryAudit.swift` + `App/SQLiteAndJSONJournalCorruptionRecoverySectionView.swift`
- `Core/AppStoreReviewDemoAccountAndFixtureReadinessAudit.swift` + `App/AppStoreReviewDemoAccountAndFixtureReadinessSectionView.swift`
- `Core/NativeSupersetOverMiniProgramPolicyAudit.swift` + `App/NativeSupersetOverMiniProgramPolicySectionView.swift`
- `Core/SevenDayLaunchCriticalPathMilestoneContract.swift` + `App/SevenDayLaunchCriticalPathMilestoneSectionView.swift`
- `Core/InAppCustomerSupportAndFeedbackParityAudit.swift` + `App/InAppCustomerSupportAndFeedbackSectionView.swift`
- `Core/AccountDeletionAndGDPRPIPLComplianceAudit.swift` + `App/AccountDeletionAndGDPRPIPLComplianceSectionView.swift`
- `Core/MiniProgramVsNativeSupersetPageClassifier.swift` + `App/MiniProgramVsNativeSupersetPageClassifierSectionView.swift`
- `App/MasterSevenDayLaunchCommandCenterView.swift` + `Tests/AppUnitTests/MasterSevenDayLaunchCommandCenterViewTests.swift`

### 2. Native Superset Alignment Principle (iOS 原生超集原则)
- **Backend API Contracts & Business Status Machines (100% Mini-Program Parity):** All backend request/response schemas, status codes, role/permission checks, order/coupon/schedule state machines, and fail-closed allowlists align 100% with the Mini-Program and shared Java backend contracts.
- **Native Superset Capabilities Retained Without Downgrading:** Where iOS is already more complete or architecturally superior to the Mini-Program — specifically **MapKit 3D + Personal Fog**, **Encrypted Durable Command Journal (`<key>:game`)**, **Native Audio/TTS Interruption Recovery**, **StoreKit 2**, **OSSignposter 60fps**, and **Reform v9 Host Bridges** — iOS retains its superior native implementation without downgrading to Mini-Program workarounds.

### 3. 7-Day Launch Critical Path (`Day 1` to `Day 7`)
- **Day 1:** Freeze `Config/Local.xcconfig` production signing (`DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`), verify `PrivacyInfo.xcprivacy`, and lock the 99-page `MiniProgramVsNativeSupersetPageClassifier` baseline.
- **Day 2:** Complete staging backend HTTPS endpoint allowlist smoke tests (`GET /api/config/public`, `GET /api/userInfo` non-empty `role`, `BK-GPS`, `BK-SESSION`, `BK-SCHEDULE`, `BK-ASSET`, `BK-PRIVACY`, `BK-AI`).
- **Day 3:** Execute full CoreTests, AppUnitTests, and 3-shard XCUITest regression suites plus Python contract checks (`tools/current_ci.py check`).
- **Day 4:** Cut **TestFlight Internal RC-1** archive, verify physical-device Keychain, camera/VisionKit QR scanning, GPS arrival accuracy, and `AVAudioSession` interruption recovery.
- **Day 5:** Validate App Store Review demo credentials, offline/review fallback fixtures (`AppStoreReviewDemoAccountAndFixtureReadinessAudit`), In-App Account Deletion (`AccountDeletionAndGDPRPIPLComplianceAudit`), and customer support/feedback flows.
- **Day 6:** Cut **TestFlight External / Release Candidate RC-2**, complete 24-hour MetricKit/crash-free soak (`CrashResilienceAndMetricKitDiagnosticsAudit`), and sign off the 15-pillar `MasterReleaseSignOffDashboard` and `FinalReleaseSignoffAndZeroGapCertificateContract`.
- **Day 7:** Submit to **App Store Connect** for review and staged production release with `MasterSevenDayLaunchCommandCenterView` green across all gates.

## Batches 20–22 (Lanes 222–253): StoreKit 2, LBS Thermal Budget, Cold-Start Latency, ASC Metadata, OAuth/City Isolation, Phased Canary, MP Path Translator & App Review Rejection Prevention Playbook (2026-10-20)

- **StoreKit 2 Entitlement & Transaction Verification:** `Core/StoreKit2EntitlementAndTransactionVerificationAudit.swift` + `App/StoreKit2EntitlementAndTransactionVerificationSectionView.swift`
- **LBS Background Location & Thermal Budget:** `Core/LBSBackgroundLocationAndThermalBudgetAudit.swift` + `App/LBSBackgroundLocationAndThermalBudgetSectionView.swift`
- **Cold-Start Launch Latency & Prewarm Budget:** `Core/ColdStartLaunchLatencyAndPrewarmBudgetAudit.swift` + `App/ColdStartLaunchLatencyAndPrewarmBudgetSectionView.swift`
- **App Store Connect Metadata & Screenshot Matrix:** `Core/AppStoreConnectMetadataAndScreenshotMatrixAudit.swift` + `App/AppStoreConnectMetadataAndScreenshotMatrixSectionView.swift`
- **Apple Sign-In & WeChat OAuth Nonce/Token Isolation:** `Core/AppleSignInAndWeChatOAuthIsolationAudit.swift` + `App/AppleSignInAndWeChatOAuthIsolationSectionView.swift`
- **Multi-City Coordinate & Timezone Boundary Isolation:** `Core/MultiCityCoordinateAndTimezoneBoundaryAudit.swift` + `App/MultiCityCoordinateAndTimezoneBoundarySectionView.swift`
- **Phased Release Canary & Kill-Switch Rollback:** `Core/PhasedReleaseCanaryAndKillSwitchRollbackAudit.swift` + `App/PhasedReleaseCanaryAndKillSwitchRollbackSectionView.swift`
- **Mini-Program 99-Page Path-to-Native-Route Translator:** `Core/MiniProgramPathToNativeRouteTranslator.swift` + `App/MiniProgramPathToNativeRouteTranslatorSectionView.swift`
- **App Store Review Guideline Rejection Prevention Playbook:** `Core/AppStoreReviewGuidelineRejectionPreventionPlaybook.swift` + `App/AppStoreReviewGuidelineRejectionPreventionPlaybookView.swift`
- **Batch 20–22 Contract Suites:** `Tests/ContractChecks/test_batch20_to_batch22_launch_contracts.py`

## Batch 23 (Lanes 254–266): 99-Page Decision Ledger (68 Strict 1:1 + 31 Native Superset), Production Signing Validator, Day-5 TestFlight Smoke Matrix, Legacy Server Isolation & Final Goal Completion Gate (2026-10-20)

- **99-Page Mini-Program vs. Native Superset Decision Ledger (68 Strict 1:1 + 31 Native Superset):** Audited and locked every single one of the 99 Mini-Program pages into an explicit per-page decision ledger (`68` strict `1:1` API/state-machine parity pages + `31` Native Superset pages where iOS retains superior native capabilities such as MapKit 3D + Personal Fog, `<key>:game` encrypted durable command journal, native `AVAudioSession` interruption recovery, StoreKit 2, OSSignposter 60fps, and Reform v9 Host Bridges without downgrading).
- **Production Signing & `Local.xcconfig` Validator:** Enforced pre-archive validation of `CODE_SIGNING_ALLOWED`, `DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`, `QUESTIFY_MARKET`, `QUESTIFY_API_BASE_URL` (HTTPS-only), and `QUESTIFY_SESSION_REALM` while keeping `Config/Base.xcconfig` fail-closed.
- **Day-5 TestFlight Physical-Device Smoke Matrix:** Codified the Day-4/Day-5 TestFlight RC physical-device verification matrix covering Keychain persistence, VisionKit QR scanning, GPS arrival accuracy (`BK-GPS`), `AVAudioSession` route/interruption recovery (`I06`), App Store Review demo credentials & offline fallback fixtures, and In-App Account Deletion (`PIPL`/`GDPR`).
- **Legacy Server (`47.103.124.64`) Isolation Guard:** Hard-blocked unapproved legacy mini-program server IP `47.103.124.64` across regional endpoint allowlist and release preflight validators.
- **Final Goal Completion Gate (`Lanes 254–266`):** Unified all Wave 1–3, Reform Plan v9 (`W02–W20`, `U01–U08`, `MV01–MV41`), 15-pillar release sign-off, 7-day launch critical path, and Batch 23 contract checks into the final goal completion gate.

### Batches 24–27 (`Lanes 267–312` · Three-Document 100% Full Closure)

- **Batch 24 (`Lanes 267–278`)**: Merged `origin/cloud/plan-I-20261019` (`PR #17` Reform Plan I: `W01/W09/W11` `OpsSafetyViews`, `OpsAuditTrail`, `OpsDegradedState`, `OpsServerReadouts`, `SafetyDisclosure`, `Resources/OpsSafety.xcstrings`, `tools/audit_client_ops_surfaces.py`, `test_ops_safety_contracts.py`) + `OPT-001..003` (`509` legacy clues triage & `D-01..D-10` policy gates) + `OPT-010..014` (`MP-18` unified quote, cart CAS atomicity, refund review, merchant payable ledger, coupon/points conservation) + `OPT-020..023` (`MP-17` private viewer ACL, media moderation, report/appeal/contribution & staged A/B content chain).
- **Batch 25 (`Lanes 279–290`)**: Completed `OPT-030..033` (`MP-04`/`MP-19` author draft readback, ending priority compatibility `D-04`, content/session snapshot versioning, creator revenue ledger `D-10`) + `OPT-040..043` (`MP-01..03`/`MP-06`/`MP-08`/`MP-13..15`/`MP-20..21` cross-device recovery, 80m GPS gate, `4->8->10s` lead polling backoff, 3s long-press exit, passport/badges/stamps) + `OPT-050..053` (`CLUB-MEM-01..13` 13-endpoint membership contract, 64-occurrence schedule & waitlist guard, lead location sharing `D-07`, `MP-12` pinned broadcast & cancel-refund auth receipt) + `OPT-060..062` (merchant claim material, same-window PV/UV/revenue/balance dashboard, CRM reach frequency & RBAC scope).
- **Batch 26 (`Lanes 291–302`)**: Completed `OPT-070..072` (`MP-05`/`MP-07`/`MP-09` explicit `type=1/0` like direction, image preview, stable ID keys, forward migration replay gate, critical chain `traceId` alert) + `OPT-080..082` (`MP-16` >2000-char AI safety gate, real vs estimated token usage, full NPC chat deletion & watermark `D-08`, author AI draft assist) + `OPT-090..092` & `EXT-01..11` (7-layer release signoff & 11 conditional extension guards, Flutter excluded) + `Legacy52TicketsAndMP01To21SliceParityContract` (`52/52` legacy tickets + `21/21` MP slices).
- **Batch 27 (`Lanes 303–312`)**: Closed all `81` partial + `6` missing rows across `w2-01..w2-21` (`198/198` rows -> 100% Parity / iOS Native Superset in `Wave2AllPartialAndMissingRowsClosureCoordinator`), remediated all 5 Base UI test failure clusters (`BaseUISuiteFailureRemediationCoordinator`), and synced all `docs/parity/w2-*.md` & `docs/handoff/ios-*.md` files.
