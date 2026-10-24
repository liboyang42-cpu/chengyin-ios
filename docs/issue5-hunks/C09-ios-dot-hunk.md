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
- `Core/NativeChannelMessageActionEntry.swift` — 发送/编辑/撤回/置顶同一入口；nil 端口等待；不另开搜索链
- `Core/AttachmentReviewProducer.swift` — 恰好 16 类附件审核原回执；可见投影不是通过
- `Core/DevicePushRegistrationLifecycle.swift` — `fixture-` token；SANDBOX / PRODUCTION_LABEL；撤权后停止再投
- `Core/WebhookDeliveryLogProducer.swift` — 注入 RecordingTransport（永不打开套接字）；签名体含 signature、不泄漏 raw key
- `Core/WebhookSameEventRetry.swift` — 同 event 保留 eventId / `dlv-{eventId}` / nonce / signature，只增加 attemptCount
- `Core/WebhookSsrfHopGuard.swift` — 每跳 https/443/无 userinfo；缺解析 fail-closed；不 DNS、不跟随真实重定向

Tests（SwiftPM `Tests/CoreTests`，隔离 `testFirstJourney…RecoverOriginal`）+ `Tests/ContractChecks/test_c09_notify_webhook_projections.py` + 本文件。

- `Tests/CoreTests/NativeChannelMessageActionEntryTests.swift` — 四动作各调用一次或等待；合法 request id 不裁成另一个 id；空白正文无效；`message_unavailable` 且无消息 id 仍为 UNKNOWN

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

## 6. Parent addendum 2026-10-23 19:08 America/Los_Angeles

HEAD `34a00334` tests. Did not invent recoverOriginal.

`DevicePushRegistrationLifecycleTests.testUnusedRevokeOfNeverSeenDoesNotOccupyThenUniqueRegisterApplies`：未见 `dev-revoke-never-c09` 的 `revoke` 抛 `originalMissing` 且 `originalByDeviceID` 仍空；后续唯一 `register` 才是 ACTIVE。

Parent python `Tests.ContractChecks.test_c09_notify_webhook_projections` **9/0**. XCTest NOT_RUN on Linux. Not 100%.

## 7. Parent addendum 2026-10-23 19:13 America/Los_Angeles

HEAD `3f6583aa` tests. Did not invent recoverOriginal.

`AttachmentReviewProducerTests.testUnusedDecideOfNeverSeenDoesNotOccupyThenUniqueSubmitApplies`：未见 `att-decide-never-c09` 的 `decide` 抛 `originalMissing` 且 `originalByRequestID` 仍空；后续唯一 `submit` 才是 PENDING。

Parent python `Tests.ContractChecks.test_c09_notify_webhook_projections` **9/0**. XCTest NOT_RUN on Linux. Not 100%.

## 8. Parent addendum 2026-10-23 19:15 America/Los_Angeles

HEAD `898390ed` tests. Did not invent recoverOriginal.

`ImmutableReceiptProducerTests.testUnusedOfflineReopenOfNeverSeenDoesNotOccupyThenUniqueAcceptApplies`：未见 `c09-reopen-never` 的 `offlineReopen` 抛 `originalMissing` 且 `originalByRequestID` 仍空；后续唯一 `accept` 才是 ACCEPTED。

Parent python `Tests.ContractChecks.test_c09_notify_webhook_projections` **9/0**. XCTest NOT_RUN on Linux. Not 100%.

## 9. Parent addendum 2026-10-23 19:18 America/Los_Angeles

HEAD `159c09f5` tests. Did not invent recoverOriginal.

`WebhookDeliveryLogProducerTests.testUnusedRequireOriginalOfNeverSeenDoesNotOccupyThenUniqueDeliverApplies`：未见 `evt-req-never-c09` 的 `requireOriginal` 抛 `originalMissing` 且 `originalByEventID` 仍空；后续唯一 `deliver` 才是 DELIVERED。

Parent python `Tests.ContractChecks.test_c09_notify_webhook_projections` **9/0**. XCTest NOT_RUN on Linux. Not 100%.

## 10. Parent addendum 2026-10-23 19:20 America/Los_Angeles

HEAD `a36c6b9d` tests. Did not invent recoverOriginal.

`WebhookSameEventRetryTests.testUnusedRetrySameEventOfNeverSeenDoesNotOccupyThenUniqueDeliverApplies`：未见 `evt-retry-unused-c09` 的 `retrySameEvent` 抛 `originalMissing` 且 `originalByEventID` 仍空；后续唯一 `deliver` 才是 DELIVERED。

Parent python `Tests.ContractChecks.test_c09_notify_webhook_projections` **9/0**. XCTest NOT_RUN on Linux. Not 100%.

## 11. Parent addendum 2026-10-23 20:40 America/Los_Angeles

`recoverFromJournal` 只读既有 `im.readSentMessage` 合同。缺 journal WAITING_SOURCE。`persistOriginal` 缺 `im.send` WAITING_SOURCE，本组不发 IM。未见 clientMessageId 保持 UNKNOWN，不占 `originalByRequestID`。XCTest NOT_RUN on Linux. Not 100%.

## 12. Message action entry

`NativeChannelMessageActionEntry` 把 send / edit / recall(withdraw) / pin 收成一个入口，各自调用已有 producer 端口一次；端口为 nil 时 WAITING_SOURCE。匹配 `[A-Za-z0-9_-]{16,64}` 的 request id 不裁成另一个 id。空白正文是 `invalidMessageContent`。端口返回前结果保持 UNKNOWN，不写本地回执。`message_unavailable=true` 且没有消息 id 的重放有效。搜索仍走既有 NativeChannelMessageEntry，本入口没有第二条搜索链。未改 AppSession / AppCompositionRoot / project.pbxproj。XCTest NOT_RUN on Linux. Not 100%.

## 13. Message page actions

`Core/NativeChannelMessagePageActions.swift` — 现有频道消息页的四个动作转发到原异步命令。发送调用 `NativeChannelTextCoordinator.sendNew(_:)` 一次。编辑、撤回、置顶各调用 `NativeChannelMessageCoordinator.submit(_:)` 一次。同步字典端口不是 writer。同一请求从原 journal `restore` 读回。不同请求、空白正文、缺证明保持 UNKNOWN，且不清除 journal。`message_unavailable` 且没有完整 MessagingMessage 不因此拒绝，也不补造 MessagingMessage。request id 不改写。`appear()` 不发送。无本地回执库。不新增搜索。

`Tests/CoreTests/NativeChannelMessagePageActionsTests.swift` — 同上。SwiftPM。XCTest NOT_RUN on Linux. Not 100%.

页面接线在 `docs/issue5-hunks/C09-message-page-actions.hunk`，不应用到 AppSession / AppCompositionRoot / project.pbxproj。History wiring 与 PBX 保持未应用。

```
Core/NativeChannelMessagePageActions.swift
  PBXFileReference 0FA89D803B5E5E9AC7B5A858
  PBXBuildFile     312C10DEC5985439C33E12D8  fileRef = 0FA89D803B5E5E9AC7B5A858

Tests/CoreTests/NativeChannelMessagePageActionsTests.swift
  PBXFileReference 5CC3940DF2FCCB13251BCF0A
  PBXBuildFile     534B1834E420FDCD212E27DD  fileRef = 5CC3940DF2FCCB13251BCF0A
```

Do not edit pbxproj from this PR. Not 100%.
