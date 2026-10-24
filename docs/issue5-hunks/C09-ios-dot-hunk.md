# C09-ios → D6/dot 最小 hunk

Issue：https://github.com/liboyang42-cpu/chengyin-remote-ops/issues/5 领取组 **C09-ios**  
仓库：`github.com/liboyang42-cpu/chengyin-ios` 仅写本仓（不写 `chengyin` / `hengyin` / `chengyin-app`）  
Base：`origin/migration/native-ios` `76ce1b313af2595f9b7d7ace49040866209c7974`  
分支：`cursor/c09-ios-notify-push-e504`

C09-ios 未改下列禁止文件。Xcode 接线请由 D6/dot 按本页粘贴；**Do not edit pbxproj from this PR.**

本仓 **不是** 100%。v12 DOCX、232 pack、unpushed iOS SHA `e2d86c4` 均 **WAITING_SOURCE**。禁止猜代码重写那些原文。XCTest / App / CI = **NOT_RUN**（Linux 只跑 Python 合同）。

Inventoried, not rewritten:

- `App/AppSession.swift` / `App/AppCompositionRoot.swift`
- `Questify.xcodeproj/project.pbxproj`
- `Localizable.xcstrings`
- IM send/receipt 公共协议、journal、RouteEffects、TopicRouteRuntime、CmsTopic、PlayExperience
- HTTPTransport / URLSession 真网、NativeWebhook*

IDs below match `tools/generate_project.py`: PBXFileReference = `sha256(path)[:24].upper()`；PBXBuildFile = `sha256("build:"+path)[:24].upper()`.

## 1. 白名单（实际写入）

Core:

- `Core/ImmutableReceiptProducer.swift` — 回复/mention/编辑/撤回/置顶/搜索原回执；UNKNOWN 不 mint；APPLIED+CURRENT 不是原证明
- `Core/AttachmentReviewProducer.swift` — 恰好 16 类附件审核原回执；可见投影不是通过
- `Core/DevicePushRegistrationLifecycle.swift` — `fixture-` token；SANDBOX / PRODUCTION_LABEL；撤权后停止再投
- `Core/WebhookDeliveryLogProducer.swift` — 注入 RecordingTransport（永不打开套接字）；签名体含 signature、不泄漏 raw key
- `Core/WebhookSameEventRetry.swift` — 同 event 保留 eventId / `dlv-{eventId}` / nonce / signature，只增加 attemptCount
- `Core/WebhookSsrfHopGuard.swift` — 每跳 https/443/无 userinfo；缺解析 fail-closed；不 DNS、不跟随真实重定向

Tests（SwiftPM `Tests/CoreTests`，隔离 `testFirstJourney…RecoverOriginal`）+ `Tests/ContractChecks/test_c09_notify_webhook_projections.py` + 本文件。

## 2. Exact pbx file-ref additions (D6/dot only)

Questify target — each Core file needs a `PBXFileReference` plus `PBXBuildFile`. `python3 tools/generate_project.py` will emit the same IDs when it sees the new `Core/*.swift` files. **Do not edit pbxproj from C09-ios.**

```
Core/DevicePushRegistrationLifecycle.swift
  PBXFileReference A1FF02D3570BBB42E0A5DCE0
  PBXBuildFile     4B907AEA0AC50364B258EE03  fileRef = A1FF02D3570BBB42E0A5DCE0

Core/ImmutableReceiptProducer.swift
  PBXFileReference B967E4281054092D40D1BF28
  PBXBuildFile     A533EC68B202FE78859E47C7  fileRef = B967E4281054092D40D1BF28

Core/AttachmentReviewProducer.swift
  PBXFileReference 911F86EFD0EBF5439E69FE21
  PBXBuildFile     9431C5D1363AB26D14C84A67  fileRef = 911F86EFD0EBF5439E69FE21

Core/WebhookSsrfHopGuard.swift
  PBXFileReference 3784841CCD3F826F84FE5936
  PBXBuildFile     176B0A8F3147601FB8E89989  fileRef = 3784841CCD3F826F84FE5936

Core/WebhookDeliveryLogProducer.swift
  PBXFileReference B0E6F3FB552B81A64EFA45EC
  PBXBuildFile     5D16B639E0B3F68C5DE081E1  fileRef = B0E6F3FB552B81A64EFA45EC

Core/WebhookSameEventRetry.swift
  PBXFileReference 92A3F8A7B9336FD7154202DC
  PBXBuildFile     7DEB2935B2F97D5575670E4F  fileRef = 92A3F8A7B9336FD7154202DC
```

Tests/CoreTests are SwiftPM-only today (`Package.swift` `path: "Tests/CoreTests"`). If D6/dot also registers them in Xcode, use:

```
Tests/CoreTests/DevicePushRegistrationLifecycleTests.swift
  PBXFileReference 088080A5300C42D9D84A951A
  PBXBuildFile     2FF4B177B4D300983D08CEE3  fileRef = 088080A5300C42D9D84A951A

Tests/CoreTests/ImmutableReceiptProducerTests.swift
  PBXFileReference CAA3F7CDDF52674A95B590F5
  PBXBuildFile     3AF4D035A7815624956461F2  fileRef = CAA3F7CDDF52674A95B590F5

Tests/CoreTests/AttachmentReviewProducerTests.swift
  PBXFileReference 30A33B0B469DAED30CC25F6E
  PBXBuildFile     41815A3193BCC455EC3AC038  fileRef = 30A33B0B469DAED30CC25F6E

Tests/CoreTests/WebhookSsrfHopGuardTests.swift
  PBXFileReference BC6BE91305940D8CF2E4DCB6
  PBXBuildFile     CD403E9806C19E5F074DF159  fileRef = BC6BE91305940D8CF2E4DCB6

Tests/CoreTests/WebhookDeliveryLogProducerTests.swift
  PBXFileReference 7A2DF54071A7CD71CF2FA237
  PBXBuildFile     15CDD8C29D37E4AC5A92C305  fileRef = 7A2DF54071A7CD71CF2FA237

Tests/CoreTests/WebhookSameEventRetryTests.swift
  PBXFileReference 0D083E1F4ED6A74E36B6FF7A
  PBXBuildFile     0857DFB463DD54B6613DCBA9  fileRef = 0D083E1F4ED6A74E36B6FF7A
```

Paste example (Core kernel only):

```
		"B967E4281054092D40D1BF28" = {
			"isa" = "PBXFileReference";
			"lastKnownFileType" = "sourcecode.swift";
			"path" = "Core/ImmutableReceiptProducer.swift";
			"sourceTree" = "<group>";
		};
		"A533EC68B202FE78859E47C7" = {
			"isa" = "PBXBuildFile";
			"fileRef" = "B967E4281054092D40D1BF28";
		};
```

## 3. 不要做

- 不要改 `AppSession`、`AppCompositionRoot`、pbxproj、localization catalogs、IM send/receipt 公共协议、journal、RouteEffects、TopicRouteRuntime、CmsTopic、PlayExperience、HTTPTransport、URLSession。
- 不要把 UNKNOWN 投影成 APPLIED，也不要为恢复 mint 新 requestId。
- 不要把 APPLIED+CURRENT / VISIBLE 当前投影当成原回执或审核通过。
- 不要接受非 `fixture-` token / HMAC key，不要打开套接字，不要做 DNS，不要跟随真实重定向。
- 不要重写 v12.docx / 232.pack / e2d86c4 未签名原文。

## 4. 验证

```bash
python3 -m unittest Tests.ContractChecks.test_c09_notify_webhook_projections
```

Must run from the chengyin-ios worktree cwd (not `/tmp`). Swift XCTest: authored, **NOT_RUN** on Linux. Not 100%.

## 5. Parent addendum 2026-10-23 17:13 America/Los_Angeles

`WebhookSameEventRetryTests.testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueDeliverApplies`：未见 `evt-retry-never-c09` 的 `recoverOriginal` 保持 `UNKNOWN_NOT_RECOVERED` 且 `originalByEventID` 仍空；后续唯一 `deliver` 才是第一笔 DELIVERED。`recoverOriginal` 对未见 id 不 mint 新 request。

XCTest NOT_RUN on Linux. Not 100%.
