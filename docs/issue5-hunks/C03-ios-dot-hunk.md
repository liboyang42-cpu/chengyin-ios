# C03-ios → D6/dot 最小 hunk

Issue：https://github.com/liboyang42-cpu/chengyin-remote-ops/issues/5 领取组 **C03-ios**  
仓库：`github.com/liboyang42-cpu/chengyin-ios` 仅写本仓（不写 `chengyin` / `hengyin` / `chengyin-app`）  
Base：`origin/migration/native-ios` `76ce1b313af2595f9b7d7ace49040866209c7974`  
分支：`cursor/c03-ios-mechanism-projections-e504`

C03-ios 未改下列禁止文件。Xcode 接线请由 D6/dot 按本页粘贴；**Do not edit pbxproj from this PR.**

本仓 **不是** 100%。v12 DOCX、232 pack、unpushed iOS SHA `e2d86c4` 均 **WAITING_SOURCE**。禁止猜代码重写那些原文。XCTest / App / CI = **NOT_RUN**（Linux 只跑 Python 合同）。

Inventoried, not rewritten:

- `Core/PlayExperienceCoordinator.swift`
- `Core/PlayExperienceService.swift`
- `Core/PlayPrefabRuntime.swift`
- Topic-related play already in Core
- `App/AppSession.swift` / `App/AppCompositionRoot.swift`
- `Questify.xcodeproj/project.pbxproj`

IDs below match `tools/generate_project.py` `ident(name) = sha256(name)[:24].upper()`.

## 1. 白名单（实际写入）

Core:

- `Core/MechanismRequestIdProjection.swift` — 原 `TopicRouteAction.actionId` 一次效果投影；UNKNOWN 不 mint
- `Core/ProgressClockMomentumAspectProjection.swift` — `TICK_CLOCK` / `SPEND_MOMENTUM` / `INVOKE_ASPECT`
- `Core/TradeBargainProjection.swift` — ACCEPT/DECLINE；不另造骰子
- `Core/OracleBountyProjection.swift` — 神谕查表 + 赏金钟
- `Core/OathFlashbackProjection.swift` — 誓言 / 闪回；密码=作者冻结值
- `Core/RouteCommunityDayProjection.swift` — 路段 + 社区日服务器 weekpart
- `Core/ClueSecretGoalProjection.swift` — 线索 + 秘密目标；经济值 OpenDecision

Tests（SwiftPM `Tests/CoreTests`，隔离 `testFirstJourney…RecoverOriginal`）+ `Tests/ContractChecks/test_c03_six_mechanism_projections.py` + 本文件。

## 2. Exact pbx file-ref additions (D6/dot only)

Questify target — each Core file needs a `PBXFileReference` plus `PBXBuildFile` (`ident("build:"+path)`). `python3 tools/generate_project.py` will emit the same IDs when it sees the new `Core/*.swift` files. **Do not edit pbxproj from C03-ios.**

```
Core/MechanismRequestIdProjection.swift
  PBXFileReference E799AC3B9E67E365F601BD10
  PBXBuildFile     75D9ACF3AC751488C30D5065  fileRef = E799AC3B9E67E365F601BD10

Core/ProgressClockMomentumAspectProjection.swift
  PBXFileReference 62DCB1FE707A8050C2B8BA8F
  PBXBuildFile     672840B0F5B826D13A19B883  fileRef = 62DCB1FE707A8050C2B8BA8F

Core/OathFlashbackProjection.swift
  PBXFileReference 724ACD4D6AAAA3B7879CAAE6
  PBXBuildFile     A5118723609D602EAC3A3377  fileRef = 724ACD4D6AAAA3B7879CAAE6

Core/TradeBargainProjection.swift
  PBXFileReference B97EB6D16ACC32D9058299E5
  PBXBuildFile     430EDBE3DB89375763EB8141  fileRef = B97EB6D16ACC32D9058299E5

Core/OracleBountyProjection.swift
  PBXFileReference 2C34D4D7324DD2A858ED374D
  PBXBuildFile     46DED334E905D3EBAC225E48  fileRef = 2C34D4D7324DD2A858ED374D

Core/RouteCommunityDayProjection.swift
  PBXFileReference A7A31D2280FA461AE6DFBCD6
  PBXBuildFile     9AAC0CFFB98F277D142F954D  fileRef = A7A31D2280FA461AE6DFBCD6

Core/ClueSecretGoalProjection.swift
  PBXFileReference 963C89CF36A324A658D7C2DD
  PBXBuildFile     C72F17837F20407AE703B5B9  fileRef = 963C89CF36A324A658D7C2DD
```

Tests/CoreTests are SwiftPM-only today (`Package.swift` `path: "Tests/CoreTests"`). If D6/dot also registers them in Xcode, use:

```
Tests/CoreTests/MechanismRequestIdProjectionTests.swift
  PBXFileReference 81BB9045ED83BB3B8B43F562
  PBXBuildFile     6BE35CDABEBCE7D9C61F6149  fileRef = 81BB9045ED83BB3B8B43F562

Tests/CoreTests/ProgressClockMomentumAspectProjectionTests.swift
  PBXFileReference C2EDFACAC613A00C569F3A03
  PBXBuildFile     995550823145D7D68D2012F7  fileRef = C2EDFACAC613A00C569F3A03

Tests/CoreTests/OathFlashbackProjectionTests.swift
  PBXFileReference 4DE6A47C690C3E96D5650D38
  PBXBuildFile     7EB8E39A3C911FEBD3FC465A  fileRef = 4DE6A47C690C3E96D5650D38

Tests/CoreTests/TradeBargainProjectionTests.swift
  PBXFileReference ADB80BD3C3047624E43901F3
  PBXBuildFile     9D417D4D41697312AD69BE6B  fileRef = ADB80BD3C3047624E43901F3

Tests/CoreTests/OracleBountyProjectionTests.swift
  PBXFileReference A22B9FD1F21DF07D9D24506F
  PBXBuildFile     529694DFA9F573C5C1F83D6D  fileRef = A22B9FD1F21DF07D9D24506F

Tests/CoreTests/RouteCommunityDayProjectionTests.swift
  PBXFileReference FDBC69FAAF1E00F977EDBE0F
  PBXBuildFile     180C32D3444462FFC0529C9E  fileRef = FDBC69FAAF1E00F977EDBE0F

Tests/CoreTests/ClueSecretGoalProjectionTests.swift
  PBXFileReference E99E97D5BE0EAE4E67EA491C
  PBXBuildFile     251E1900DA3C5BCA2D6C8211  fileRef = E99E97D5BE0EAE4E67EA491C
```

Paste example (Core kernel only):

```
		"E799AC3B9E67E365F601BD10" = {
			"isa" = "PBXFileReference";
			"lastKnownFileType" = "sourcecode.swift";
			"path" = "Core/MechanismRequestIdProjection.swift";
			"sourceTree" = "<group>";
		};
		"75D9ACF3AC751488C30D5065" = {
			"isa" = "PBXBuildFile";
			"fileRef" = "E799AC3B9E67E365F601BD10";
		};
```

## 3. 不要做

- 不要改 `AppSession`、`AppCompositionRoot`、`PlayExperienceCoordinator`、`PlayExperienceService`、`PlayNode`、`RouteEffects`、`TopicRouteRuntime`、localization catalogs。
- 不要另造骰子 / 钱包 / 角色卡 / 第二套 request 账。
- 不要把 UNKNOWN 投影成 APPLIED，也不要为恢复 mint 新 originalRequestID。
- 不要对未见过的 originalRequestID 做 recoverUnknown 时写入 `originalActions`；未见过只回 UNKNOWN 且 `existing==nil`，否则后续唯一写入会变成对 mint 出的 UNKNOWN 的 recover。
- 不要用客户端时钟判定社区日成功。
- 不要把未确认的阵营 / 领地 / 秘密目标经济值写成数字。

## 4. 验证

```bash
python3 -m unittest Tests.ContractChecks.test_c03_six_mechanism_projections
```

Must run from the chengyin-ios worktree cwd (not `/tmp`). Swift XCTest: authored, **NOT_RUN** on Linux. Not 100%.

## 5. Parent addendum 2026-10-23 17:45 America/Los_Angeles

Timer deliveryCount=31 (00:40Z). WAITING_SOURCE cat-file still ABSENT.

Class-level `recoverOriginal` of never-seen ids stays UNKNOWN and does not occupy `originalActions`; later unique apply is the first APPLIED write:

- TradeBargain ACCEPT `c03-bargain-never` (`85c425de`)
- Oath SWEAR `c03-oath-never`
- Oracle CONSULT `c03-oracle-never`
- Route TAKE_SEGMENT `c03-route-never`
- Clue GAIN_CLUE `c03-clue-never`
- Clock TICK `c03-clock-never`

HEAD `795f5438`. Parent python `Tests.ContractChecks.test_c03_six_mechanism_projections` **11/0**. XCTest / App / HTTP / CI = NOT_RUN. Did not invent recoverOriginal. Runtime / AppSession / PBX still unwired. Not 100%.
