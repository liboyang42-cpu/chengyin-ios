# L8 text lifecycle recovery

Status: client safety/recovery implementation, not a complete channel launch journey.

## Fixed source and ownership

- iOS base: `eec839502b11f1119a6ede212c768bb3f2de4f29`, the verified `integration/launch-20261204` head.
- Frozen server: `liboyang42-cpu/hengyin@58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`.
- Only production edit: `Core/NativeChannelTextCoordinator.swift`, original blob `653286cf58fd01ec1d318f5299fff8cab72c9130`.
- Added tests: `Tests/CoreTests/NativeChannelTextLifecycleLaunchTests.swift`. Existing tests and fixtures are unchanged.
- This does not overlap the separately delivered L8 message context, chain, check-in, history, projection or search groups. No shared App, authority, journal, service, localization, project or CI files change.

## Existing normal path, verified at the base

`NativeChannelManagementClubEntry` passes a real channel source through `NativeChannelManagementViews.contextConversation` to `NativeChannelMessageHostDestination`. `AppSession.makeNativeChannelMessageFlow` reads the original IM conversations and current channel context, verifies identity/mapping and the existing host authority, and constructs `NativeChannelMessageHostBinding` with original adapters. The host's `makeTextCoordinator` supplies the existing history, dedicated text client and protected scoped journal. `NativeChannelHistoryView` installs the existing text composer only after history is ready.

The composer calls `sendNew`, saves one original key/body before dispatch, and uses `NativeChannelTextService` to POST `/api/im/send`. An acknowledged message ID does not insert a local history row: visible payload is re-read from current history. Stop/background preserves the original, and resume may only read its receipt. Explicit retry first re-reads, then uses the same original key/body when all existing checks permit it.

This source path is not proof of configured access. `AppCompositionRoot` still defaults independent text receipt/send approval selectors to nil. No authority or configuration is changed here.

## Corrections

- A stopped host releases its in-process journal operation lease even when a transport ignores cancellation and never finishes. It retains the protected original and does not automatically resend.
- Each asynchronous operation owns its UUID lease. A late completion cannot release a replacement operation's lease, overwrite its visible state, enable retry from a stale read or settle another original.
- Recheck lifecycle/current access after synchronous state observers and before actual dispatch; require receipt access when accepting a send result.
- A hidden-message ID veto survives stopping the same-owner history, but cannot survive an unconfigured or identity-mismatched underlying reader. This repairs the existing reader-veto assertion without modifying that test.

## Frozen server blocker: unchanged, fail closed

At frozen `58f4cc4`, `ApiImController.sendReceipt` returns only `found` and `message` from `ImServiceImpl.readSentMessage`. It does not return `state=APPLIED` or `original_send_proof`. The stored message request hash is `@JsonIgnore` and is not an original receipt proof.

The current coordinator calls `confirmOriginal`, which requires the original SEND proof and its exact actor/conversation/key/payload hash. A found current message alone therefore remains UNKNOWN. The new tests explicitly preserve this behavior; legacy body-only receipt parsing is not substituted. Quote/mention fields and newer endpoints are not invented or enabled.

Consequently full unknown-send/restart settlement against the frozen server remains blocked. Independent text approvals, backend proof support, two-account real backend testing, language/market checks and mini-program regression are still required for launch acceptance. This patch does not claim any of them passed.

## Validation

14 new asynchronous XCTest methods cover stopped writer recovery, same-original recovery in a replacement host, late writer/read results, replacement lease ownership, explicit original-key retry, synchronous observer retirement, receipt grant loss, terminal access retirement, frozen proof absence and hidden-ID reader fences.

At submission: whitespace/whitelist/source identity checks passed. No Swift executable is installed in the author's environment; these tests and the existing suite have NOT RUN there. No dependency installation, simulator, device, CI or real server request was performed.

Full existing target (no production stubs): public `Package.swift` at the fixed commit, complete `Core/`, and the unchanged `Tests/CoreTests/NativeChannelTextRecoveryTests.swift` plus the new test file. Intended command in an already provisioned compatible Swift environment:

```
swift test -j 2 --filter 'NativeChannelText(Recovery|LifecycleLaunch)Tests'
```

The production dependency chain includes NativeChannelText Authority/Service/Journal/Coordinator, NativeChannelMessageTextReference/Contracts, NativeChannelHistory/HistoryModel/Service, MessagingContracts/Reading/Service, IMExpandedRecoveryJournal, RuntimeDependencyConfiguration, ProjectEditDataStorage, and their existing support types. CryptoKit and Combine are platform requirements. Any isolated Linux harness must record every complete source file and every compatibility shim; a shortened or stubbed target is not the full app build. Do not rewrite production or old assertions to make the harness pass.

The independent branch does not match either existing workflow's push triggers. Re-read its files and check exact-head workflow runs after publication; no PR, dispatch or public comment is part of this submission.
