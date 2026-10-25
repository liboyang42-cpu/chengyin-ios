# C11-ios → D6/dot 最小 hunk

Issue：https://github.com/liboyang42-cpu/chengyin-remote-ops/issues/5 领取组 **C11-ios**  
仓库：`github.com/liboyang42-cpu/chengyin-ios` 仅写本仓（不写 `chengyin` / `hengyin` / `chengyin-app`）  
Base：`origin/migration/native-ios` `76ce1b313af2595f9b7d7ace49040866209c7974`  
分支：`cursor/c11-ios-ops-support-e504`

C11-ios 未改下列禁止文件。Xcode 接线请由 D6/dot 按本页粘贴；**Do not edit pbxproj from this PR.**

本仓 **不是** 100%。v12 DOCX、232 pack、unpushed iOS SHA `e2d86c4` 均 **WAITING_SOURCE**。禁止猜代码重写那些原文。XCTest / App / CI = **NOT_RUN**（Linux 只跑 Python 合同）。

Inventoried, not rewritten:

- `App/AppSession.swift` / `App/AppCompositionRoot.swift`
- `Questify.xcodeproj/project.pbxproj`
- `Resources/Localizable.xcstrings`
- JWT / RBAC / production config
- Mapper / Controller
- `RouteEffects` / `TopicRouteRuntime*` / `CmsTopic*` / `PlayExperience*`

IDs below match `tools/generate_project.py` `ident(name) = sha256(name)[:24].upper()`. fileRef = sha256(path)[:24].upper(); build = sha256("build:"+path)[:24].upper().

## 1. 白名单（实际写入）

Core:

- `Core/SupportEventLocator.swift` — 按 requestId 定位原 audit 事件；APPLIED+SUCCESS 只对照
- `Core/OrderPageReadback.swift` — 订单页已有 id 回读；第一条 ORDER 必须等于该 id，别的 id 不打开
- `App/ProfileOrdersView.swift` — `ProfileOrderDetailView.id` 调用一次 `locateByOrderId`；不启用 original-event，不借 list/detail 批准，不调用 `/business/audit-log`
- `Core/CompensationEntryProjection.swift` — 既有 extra-approver 权限码 pass-in；冻结条款不被 FINAL 999 覆盖
- `Core/DataDeletionEvidenceTable.swift` — 既有 writer 处置表，不是 cleaner / DDL
- `Core/ReviewResultVisibilityAdapter.swift` — submit → reject → revise → approve 可见性
- `Core/VersionedLocaleDisplay.swift` — PROFILE_VERSION=1 中美展示；法务门禁 NOT_RUN

Tests（SwiftPM `Tests/CoreTests`，隔离 `testFirstJourney…RecoverOriginal`）+ `Tests/ContractChecks/test_c11_ops_support_projections.py` + 本文件。

## 2. Exact pbx file-ref additions (D6/dot only)

Questify target — each Core file needs a `PBXFileReference` plus `PBXBuildFile` (`ident("build:"+path)`). `python3 tools/generate_project.py` will emit the same IDs when it sees the new `Core/*.swift` files. **Do not edit pbxproj from C11-ios.**

```
Core/SupportEventLocator.swift
  PBXFileReference D579A9832347C0C626BE58BE
  PBXBuildFile     0FD49EE8EC846933EEC26AC1  fileRef = D579A9832347C0C626BE58BE

Core/OrderPageReadback.swift
  PBXFileReference B7D9DA25F1136FC4B855DC42
  PBXBuildFile     E8EF22EFB954E8909A13DE5D  fileRef = B7D9DA25F1136FC4B855DC42

Core/CompensationEntryProjection.swift
  PBXFileReference C4B3D4FB8D69753BEEB953E3
  PBXBuildFile     2830750162E8EADDC5B3E597  fileRef = C4B3D4FB8D69753BEEB953E3

Core/DataDeletionEvidenceTable.swift
  PBXFileReference 33920A8B7323EE7F3897C16D
  PBXBuildFile     F21066F2DACA181CB3DAADEF  fileRef = 33920A8B7323EE7F3897C16D

Core/ReviewResultVisibilityAdapter.swift
  PBXFileReference 1FCAABB79FBBE30863814086
  PBXBuildFile     F7203320F287FD91C4631CDD  fileRef = 1FCAABB79FBBE30863814086

Core/VersionedLocaleDisplay.swift
  PBXFileReference CB297192D216922821DE7733
  PBXBuildFile     32F52CD6F3C432395B3B9167  fileRef = CB297192D216922821DE7733
```

Tests/CoreTests are SwiftPM-only today (`Package.swift` `path: "Tests/CoreTests"`). If D6/dot also registers them in Xcode, use:

```
Tests/CoreTests/SupportEventLocatorTests.swift
  PBXFileReference 38E6E058981D542F62494B75
  PBXBuildFile     E6106DA65612D9D545A4E705  fileRef = 38E6E058981D542F62494B75

Tests/CoreTests/OrderPageReadbackTests.swift
  PBXFileReference 5084C3832B1C388DF2D59CB3
  PBXBuildFile     745E19668CFE9543ABF7E56B  fileRef = 5084C3832B1C388DF2D59CB3

Tests/CoreTests/CompensationEntryProjectionTests.swift
  PBXFileReference 2B7EB927177EADE623731274
  PBXBuildFile     36FEE85110D68301A9E0C662  fileRef = 2B7EB927177EADE623731274

Tests/CoreTests/DataDeletionEvidenceTableTests.swift
  PBXFileReference 8A0952E12E7B7A8D9F4DAFBA
  PBXBuildFile     ABC1E4762392E10465EB45E7  fileRef = 8A0952E12E7B7A8D9F4DAFBA

Tests/CoreTests/ReviewResultVisibilityAdapterTests.swift
  PBXFileReference F49A275159FCD3B194D3C38D
  PBXBuildFile     5EAC254767AF26736DF0CFC2  fileRef = F49A275159FCD3B194D3C38D

Tests/CoreTests/VersionedLocaleDisplayTests.swift
  PBXFileReference B78FA163B02E91B0BC0E33F4
  PBXBuildFile     02F9C8182741060C0CDD8273  fileRef = B78FA163B02E91B0BC0E33F4
```

Paste example (Core kernel only):

```
		"D579A9832347C0C626BE58BE" = {
			"isa" = "PBXFileReference";
			"lastKnownFileType" = "sourcecode.swift";
			"path" = "Core/SupportEventLocator.swift";
			"sourceTree" = "<group>";
		};
		"0FD49EE8EC846933EEC26AC1" = {
			"isa" = "PBXBuildFile";
			"fileRef" = "D579A9832347C0C626BE58BE";
		};
```

## 3. 不要做

- 不要改 `AppSession`、`AppCompositionRoot`、pbxproj、`Localizable.xcstrings`。
- 不要查 JWT / RBAC / 菜单；补偿权限只认调用方传入的既有 extra-approver 权限码。
- 不要把当前投影 APPLIED+SUCCESS 当成原 request 成功；UNKNOWN 保持 UNKNOWN。
- 不要把缺失 requestId 写成 `""`；保持 Optional.none / JSON null。
- 不要执行数据删除或 DDL；证据表只登记既有 writer 口径。
- 不要宣称备案 / 协议 / 商店审核 / 生产容量已通过（一律 NOT_RUN）。

## 4. 验证

```bash
python3 -m unittest Tests.ContractChecks.test_c11_ops_support_projections
```

Must run from the chengyin-ios worktree cwd (not `/tmp`). Swift XCTest: authored, **NOT_RUN** on Linux. Not 100%.

## Parent addendum 2026-10-23 17:30 America/Los_Angeles

`testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueAuditApplies`：未见 `c11-comp-never` 的 `recoverOriginal` 回读空 audit 且不把 id 写入 keyed ledger；后续唯一 freeze 才是第一笔。空白 / nil requestId 返回 nil，不写成空串。XCTest NOT_RUN。Not 100%.
