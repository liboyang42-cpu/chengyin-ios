# Issue #61 交接响应与逐项对账账本（2026-10-20）

- **关联 Issue**：[`liboyang42-cpu/chengyin-ios#61`](https://github.com/liboyang42-cpu/chengyin-ios/issues/61)（及 [`#issuecomment-6291991678`](https://github.com/liboyang42-cpu/chengyin-ios/issues/61#issuecomment-6291991678)、[`#issuecomment-6293304881`](https://github.com/liboyang42-cpu/chengyin-ios/issues/61#issuecomment-6293304881)）
- **集成分支**：`integration/wave2-20261019`（PR [`#18`](https://github.com/liboyang42-cpu/chengyin-ios/pull/18)）
- **父提交（Parent SHA）**：`1e72f9916c438d3fee4b7e087e002f16aeb3feaf`（已含 `c06ff341` 对 `origin/migration/native-ios@50e2cf9be15999e35f566463db61908690f7c149` 的合并及 `553dd9bf`..`1e72f991` 的模块导入与 `AnyShapeStyle` 编译修复）
- **对比基线（Comparison Base）**：`50e2cf9be15999e35f566463db61908690f7c149`（`origin/migration/native-ios`）

---

## 一、A1–A6（iOS 项）逐项状态、路径与验证边界

### A1 — 整合冲突解除
- **状态**：已在父链 `c06ff3415676dfd9a04fd936f2a838bc0ecd970d` 解除并由 `dot` 核实（`#18` `mergeable=true`），本提交基于 `1e72f9916c438d3fee4b7e087e002f16aeb3feaf` 线性推进，未覆盖任何在途修复。

### A2 — 普通商家项目参与者流程整合
- **状态**：源码已在 `c06ff3415676dfd9a04fd936f2a838bc0ecd970d` 合入并保留（含 `MerchantTopicEndpoint.players` 显式 `scope=MERCHANT`、`loadOrdinaryMerchantParticipants`、`MerchantProjectParticipantsDestination`、`merchant.project.participants.read` 门禁及父子页面租约生命周期）；运行验收独立保留（当前 `NOT_RUN`）。

### A3 — 漫游私人/护照工具只读依赖注入接线（写操作继续关闭，生产配置仍关闭）
- **状态**：已提交代码修正（依赖注入选择器与传输层只读校验接通；生产端点白名单仍为空，默认不开放生产流量）。
- **改动路径**：
  - `Core/RoamPassportPrivateToolsReading.swift`
  - `App/AppCompositionRoot.swift`
  - `App/AppSession.swift`
  - `tools/check_roam_private_tools.py`
  - `Tests/ContractChecks/test_roam_private_tools.py`
- **正常入口 → 页面 → 读取 → 结果 → 返回路径与生产关闭边界**：
  1. **入口与页面**：漫游主页（`RoamView`）→ 漫游护照 / 私人工具入口（`RoamPassportToolsSheet` / `RoamPrivateToolsSheet`，含月度回顾 `monthly-recap`、探索周年 `anniversary`、探索目标 `exploration-goals`、时光胶囊 `capsule`、探索导出 `exploration-export`）。
  2. **读取链路**：`AppSession` 通过 `roamPassportToolsReadAccessSelector` 与 `roamPrivateToolsAccess` 委托调用 `composition.roamPassportToolsReadAccess(context)` / `composition.roamPrivateToolsReadAccess(context)`，并在 `CompositionHTTPTransport.send(_:)` 中校验 `RoamPassportToolsRoute.reads` 与 `RoamPrivateToolsRoute.reads`。
  3. **会话与写隔离边界**：每次读取及读回落地均校验 `ContentDraftContextFence.matches(context, current)` 与 `!selected.allowsWrites`；未登录、退出、切账号、401 或撤销授权时立即清空 `roamPassportToolsState` / `roamPrivateToolsState` 并丢弃迟到响应；所有写路由（`RoamPrivateToolsRoute.writes`）不在 `CompositionHTTPTransport` 放行，写权限保持独立关闭。
  4. **生产默认关闭边界**：`AppCompositionRoot.init` 的 `roamPassportToolsReadAccess` 与 `roamPrivateToolsReadAccess` 默认仍为 `{ _ in nil }`，`Config/ApprovedProductionEndpoints.json` 仍为空数组 `[]`；仅在显式注入经审阅的只读 Access 对象且端点位于该 Access 的 `endpoints` 白名单时才会发起请求，不等于生产端点已启用。

### A4 — 发布证书改为证据驱动 Fail-Closed（预览样例与正式验收入口分离）
- **状态**：已提交代码修正。
- **改动路径**：
  - `Core/FinalReleaseSignoffAndZeroGapCertificateContract.swift`
  - `App/FinalReleaseSignoffAndZeroGapCertificateView.swift`
  - `Tests/CoreTests/FinalReleaseSignoffAndZeroGapCertificateContractTests.swift`
  - `Tests/AppUnitTests/FinalReleaseSignoffAndZeroGapCertificateViewTests.swift`
- **反例与门禁规则（2026-10-20 按 dot 15:01 UTC 审查意见修正）**：
  - 默认 `canonicalPillars` 全部为 `status = .notRun`、`completedCount = 0`、`zeroOpenBlockers = false`；无参 `issueCertificate()` 恒 `false`。
  - `issueCertificate` 现要求：①完整 canonical 6 个 ID 各出现一次（重复 ID / 未知 ID 直接拒绝，例如把一个 `id=x`、1/1、passed 的 pillar 复制六次不再通过）；②`requiredCount`/`completedCount` 不得低于 `canonicalRequiredCount(forPillarID:)`（要求数不能自行降低）；③`expectedCommitSHA` 不可省略，必须为合法 40 位十六进制，所有 pillar 绑定同一 SHA（混合 SHA 拒绝）；④显式传入但无法解析的 `notBeforeISO8601` 直接拒绝，不再被忽略；⑤证据来源 `ReleaseEvidenceOrigin`：`.previewFixture` 即使携带真实 40 位 SHA 也无法通过正式认证。
  - `evaluateCertificate` 复用同一 `issueCertificate` 评价，并额外拒绝重复/未知证据 ID。
  - UI（`FinalReleaseCertificateSnapshot`）不再自行计算布尔“已认证”，改由 Core `issueCertificate` / `isCanonicalPillarCertified` 得出；`previewReadyFixture` 现为 `isZeroGapCertified == false`。
  - 新增反例测试（源码级，未运行）：重复/未知 ID、降低 requiredCount、省略/混合 SHA、非法 notBefore、预览夹具冒充真实 SHA。

### A5 — 99 页与 176 项要求映射台账（注明来源版本与差异，四层状态分离）
- **状态**：已更新代码枚举与四层状态字段（不宣称全量已上线或 100% 端到端通过）。
- **改动路径**：
  - `Core/MiniProgramPageByPage99DecisionLedgerContract.swift`
  - `Core/MiniProgram99PageParityRegistry.swift`
  - `Core/ThreeDocumentMasterCrosswalkContract.swift`
- **来源版本与差异说明**：
  1. **99 页路由清单来源**：取自公共仓库 `liboyang42-cpu/hengyin`（`chengyinhub-xcx/app.json`，对照基线 `a6ec8bbdadd88ac4fb83bdab6f78e3a976ea3f18`）的 99 条核心与分包页面路径（`pages/*`、`subpackageP3/*`、`subpackageRoam/*`、`subpackageTools/*`、`subpackageMember/*`）。注：当前 `hengyin/chengyinhub-xcx/app.json` 全量注册为 136 条路由（130 页面 + 6 拆分路由），本文件的 99 条为 Wave-1/Wave-2 初版冻结的 99 页基线子集，其余 37 条在 `docs/parity/w2-01.md`..`w2-21.md`（共 198 行对账表）中按模块分列。**修正（dot 15:01 UTC 审查）**：99 行 `codeStatus`/`wiringStatus` 现默认 `.pending`（不再批量 `.passed`）；`MiniProgram99PageParityRegistry.all99BaselinePageEntries` 不再按五组粗映射，也不再把 `decisionMode` 字符串当作 native 符号——仅 7 条已核实路由（如 `subpackageTools/capsule/index` → `RoamCapsuleView` @ `App/RoamPassportPrivateToolsViews.swift`，宿主 `RoamPassportPrivateLinks`）填写真实文件/符号/宿主，其余留空且 `isSourceMappingVerified == false`；`evaluateEndToEndVerification` 拒绝重复路由、未知路由、缺失/混合/非法 SHA 与空证据。
  2. **176 项改革计划枚举说明**：`ThreeDocumentMasterCrosswalkContract.clientTracking176EnumerationIDs`（已从 `reformPlanV9All176StableIDs` 重命名，明确为客户端跟踪枚举、不强称原 176 baseline；默认 `mappedItems` 为空，`isHundredPercentCovered` 默认 `false`；四层 ledger 默认 `.pending`；评价器拒绝重复 ID/未知 ID/缺失或混合 SHA）收录了 `docs/plan-progress/{F,G,H,I}-20261019.md` 中已登记的 `W01..W20` 子项（127 项）+ `U01..U08`（8 项）+ `MV01..MV41`（41 项）共 176 个客户端跟踪 ID。**重要差异说明**：正如 `docs/ios-current-status.md` 第 14–15 行所载，原《Questify城瘾全面改革施工计划》（封面版次 9 / 文件记录版本 10）的 176 项原始文本在公共仓库中尚未形成与正文逐字核验的完整对照；此处 `127 W + 8 U + 41 MV = 176` 是客户端按 `F–I` 进度卡整理的工作包/决策/视觉规范跟踪枚举，不能仅凭数量等于 176 替代原始施工文档的逐条业务签收。四层状态中 `wiringStatus = .pending`、`testStatus = .notRun`、`deploymentStatus = .notRun`，`evaluateEndToEndDeploymentVerified()` 默认返回 `false`。

### A6 — 本次提交实际执行的检查命令与未运行边界
- **实际执行并通过（源码静态契约与工程结构检查，非 Swift 编译/XCTest 运行）**：
  - `python3 tools/check_roam_private_tools.py` → `PASS: 30 roam private tools source contracts`（Python 源码契约检查）
  - `python3 -m unittest Tests/ContractChecks/test_roam_private_tools.py` → `Ran 8 tests ... OK`（Python 契约脚本单测，非 Swift XCTest）
  - `python3 -m unittest Tests/ContractChecks/test_batch15_zero_gap_certificate.py` → `Ran 3 tests ... OK`（Python 源码契约检查）
  - `python3 tools/current_ci.py refresh --base 50e2cf9be15999e35f566463db61908690f7c149` & `python3 tools/current_ci.py check --base 50e2cf9be15999e35f566463db61908690f7c149` → `CURRENT_LEDGER_OK`
  - `python3 tools/check_scaffold.py` → `Scaffold check passed`
- **明确未运行（`NOT_RUN`）**：
  - Swift/Xcode 完整构建与链接（`xcodebuild`）：`NOT_RUN`
  - Swift `CoreTests` / `AppUnitTests` / `AppUITests`（XCTest / XCUITest 运行）：`NOT_RUN`
  - iOS 模拟器 / 真机运行与 UI 交互实测：`NOT_RUN`
  - GitHub Actions 远端 CI：本提交带 `[skip ci]`，未触发新运行（`NOT_RUN`）

---

## 二、原 Issue B1–B3（跨仓 `hengyin` 依赖项）核对状态

| 编号 | 跨仓事项（`liboyang42-cpu/hengyin`） | 当前状态与 iOS 协同边界 |
|---|---|---|
| **B1** | 小程序 UI 移植（`hengyin #293`，head `d83a7d7a5be34961fb07a582000af9b408a8dfa2`） | `hengyin #293` 仍为 open（已有 9 个二级页等成果且 CI / Funds IT 通过），待小程序主线整合与界面/导航验收；iOS 端不越界修改 `hengyin` 仓库，也不擅自恢复 `#293` 中明确排除的收藏据点入口。 |
| **B2** | 审核系统及后续修复（`hengyin #385` head `b19200a3` 及 `#387` / `#388` / `#390`） | 均在 `hengyin` 审核整合分支推进中；iOS 端对应举报/申诉/媒体机审可见性保持只读契约与写门禁关闭（`OPT-021`/`OPT-022`），待后端合入 `master` 并完成测试环境部署后再联调。 |
| **B3** | 后端大移植与当前 `master` 分叉（`#339` / `#301` 在 `integrate/master-port-20261019@b548cdc4` vs `master@a6ec8bbd`） | 已知整合分支相对 `master` 为 `ahead 245 / behind 2`（且 `#389`、`#391` 已合入 `master`）；iOS 端在未获明确联调目标 SHA 与已部署环境前，不将未部署接口标为生产已接通。 |

---

## 三、iOS 环境、配置与产品决策阻塞（独立列出，不替换原 B1–B3）

1. **生产端点白名单与构建签名配置**：`Config/ApprovedProductionEndpoints.json` 仍为空 `[]`，`Config/Base.xcconfig` 保持 `QUESTIFY_API_BASE_URL =` 与 `CODE_SIGNING_ALLOWED = NO`。
2. **共用后端合同状态**：`CLAIM-MATERIAL`、`AI-DELETE`、`AI-VOICE` 仍为 `DRAFT`，全部 `BK-*` 仍为 `TEST_DEPLOYED = NO`。
3. **产品政策决定 `D-01` 至 `D-10`**：未决期间全部保持现状与默认关闭状态。
