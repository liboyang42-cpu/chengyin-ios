# C05-ios shared hunk for dot

Exclusive owner: Cursor C05-ios (`cursor/c05-offline-pack-nav-sidequest-e238`).
Base: `migration/native-ios` @ `76ce1b313af2595f9b7d7ace49040866209c7974`.
This file is the only shared hunk. Do not treat it as authorization to edit AppSession / pbxproj / Localizable / PlayNode / PlayExperience / original pause ops from the Cursor line.

## Why this hunk exists

Issue 5 C05: 30 的 PlayNode / PlayExperience 原会话修复及 35 工厂需合并 hunk，不另写。
New Core types are SwiftPM-visible (`Package.swift` `path: "Core"`). Xcode `check_scaffold.py` still requires every `Core/*.swift` file to be listed in `Questify.xcodeproj/project.pbxproj`. C05 must not edit that project file.

Inventoried, not rewritten:

- `App/PlayNodeDetailView.swift` — existing PlayViewModel session surface
- `Core/PlayExperienceCoordinator.swift` — original session / paused dispatch
- `Core/PlayExperienceService.swift` — `pausedRequest` and 20 original pause ops owner
- `Core/PlayRecoveryStorage.swift` — `PlayPausedStorage`
- `Core/RoamExperienceCoordinators.swift` — `RoamTileMemoryPager` exploration memory
- `Core/WalkingNavigationContracts.swift` — in-app walking destination identity

## Dot-owned integration (do not apply from this PR)

1. **pbxproj** — from this SHA, run `python3 tools/generate_project.py` so these new sources join the Questify target:
   - `Core/OfflinePackOperation.swift`
   - `Core/OfflinePackLifecycleFlow.swift`
   - `Core/SideQuestAcceptHold.swift`
   - `Core/NavigationDestinationConsent.swift`
   - `Core/PresenceProofDistinctFromFog.swift`
   CoreTests are SwiftPM-only (`Tests/CoreTests`); they are not Xcode app-unit sources.

2. **PlayNode / PlayExperience session merge** — side-quest complete/fail/exit recover uses exclusive `originalRequestID`. Do not invent a second session writer. When wiring a live play loop, consume C05 holds/proofs from the existing PlayExperience session / 35 factory. Do not let C05 own `PlayExperienceSession` construction or `PlayPausedStorage`.

3. **Twenty original pause ops** — remain `PlayExperienceCoordinator` + `PlayExperienceService.pausedRequest`. Exclusive offline pack pause/resume is a different operation id machine (`OfflinePackOperation.resume(operationID:)`). `hijackOriginalPauseOps()` is a typed refusal.

4. **qmod / volume-12 / T41 original writers** — not in this public tree. Default exclusive commits throw `WAITING_SOURCE` for:
   - `qmod.finalOpsContract`
   - `vol12.offlinePackResumeWriter`
   - `t41.scoringWriter`
   - `t41.fullLoopUnproven`
   Do not invent those routes here. When the original pack/scoring writer exists, inject it behind the exclusive WAITING_SOURCE seams.

5. **AppSession / composition** — do not wire C05 into `AppSession` from this candidate. In-app navigation destination consent is not location-share consent and is not a walking-coordinator replacement.

6. **Localizable.xcstrings** — not edited.

## C05 already landed (do not rewrite)

- Exclusive offline pack: download / pause / corrupt / full-disk / update / keep-old / expire / delete / resume same operation id
- Answers and hidden coordinates are refused before retain
- Independent side-quest: discover compliant place → capacity hold → GPS/QR/photo/AR or approved alternative → complete/fail/exit → original record recover
- Fog tiles are exploration memory, never presence
- In-app nav destination purpose split from location-share
- No fake GPS, no CLLocationManager

## Verification note

Linux: Python contract `Tests/ContractChecks/test_offline_pack_and_nav_consent.py`.
Swift XCTest: authored, **NOT_RUN** on Linux.

## Addendum 2026-10-23 18:07 America/Los_Angeles

HEAD `c13aa74c`. Class-level occupancy without inventing `recoverOriginal` on Navigation or OfflinePack:

- `testUnusedConsentDoesNotOccupyShareThenUniqueShareGrantApplies` — unused start does not occupy nav grant; unique nav grant does not occupy share; unique location-share grant is the first share write
- `testUnusedResumeDoesNotOccupyThenUniqueStartDownloadApplies` — unused resume of `op-class-never` throws `.notPaused` without occupying `operationID`; unique `startDownload("op-class")` is the first write

Parent python `Tests.ContractChecks.test_offline_pack_and_nav_consent` **13/0**. XCTest NOT_RUN. SHA256 digest-length-only; git whitelist unchanged.

## Addendum 2026-10-23 19:36 America/Los_Angeles

HEAD `a968bdab` tests. Did not invent recoverOriginal.

`SideQuestAcceptHoldTests.testUnusedSubmitProofBeforeHoldDoesNotOccupyThenUniqueSubmitApplies`：未见预占的 `submitProof` 抛 holdRequired 且 phase 仍 discovered、proof 仍空；后续唯一 acceptHold+submitProof 才是 proofPending。

Parent python `Tests.ContractChecks.test_offline_pack_and_nav_consent` **13/0**. XCTest NOT_RUN on Linux. SHA256 digest-length-only. Not 100%.

## Addendum 2026-10-23 19:39 America/Los_Angeles

HEAD `fbbb3da4` tests. Did not invent recoverOriginal.

`SideQuestAcceptHoldTests.testUnusedExitBeforeHoldDoesNotOccupyThenUniqueExitApplies`：未见预占的 `exit` 抛 holdRequired 且 original 仍空；后续唯一 acceptHold+exit 才是 exited 原文（无需 proof）。

Parent python `Tests.ContractChecks.test_offline_pack_and_nav_consent` **13/0**. XCTest NOT_RUN on Linux. SHA256 digest-length-only. Not 100%.

## Addendum 2026-10-23 19:41 America/Los_Angeles

HEAD `0dd490ec` tests. Did not invent recoverOriginal.

`OfflinePackOperationTests.testUnusedDeleteOfIdleDoesNotOccupyThenUniqueStartThenDeleteApplies`：idle `delete` 抛 invalidManifest 且 phase 仍 idle、operationID 仍空；后续唯一 startDownload+delete 才是 deleted。

Parent python `Tests.ContractChecks.test_offline_pack_and_nav_consent` **13/0**. XCTest NOT_RUN on Linux. SHA256 digest-length-only. Not 100%.

## Addendum 2026-10-23 19:46 America/Los_Angeles

HEAD `cf876e61` tests. Did not invent recoverOriginal.

`OfflinePackOperationTests.testUnusedExpireOfIdleDoesNotOccupyThenUniqueStartThenExpireApplies`：idle `expire` 抛 invalidManifest 且 phase 仍 idle、operationID 仍空；后续唯一 startDownload+expire 才是 expired。与 unused delete 的 deleted 占账不同。

Parent python `Tests.ContractChecks.test_offline_pack_and_nav_consent` **13/0**. XCTest NOT_RUN on Linux. SHA256 digest-length-only. Not 100%.

## Addendum 2026-10-23 19:48 America/Los_Angeles

HEAD `8886224e` tests. Did not invent recoverOriginal.

`OfflinePackOperationTests.testUnusedRecordCorruptOfIdleDoesNotOccupyThenUniqueStartThenCorruptApplies`：idle `recordCorrupt` 抛 invalidManifest 且 phase 仍 idle、operationID 仍空；后续唯一 startDownload+recordCorrupt 才是 corrupt（抛 corrupt 发生在占账之后）。与 unused expire 的 expired、unused delete 的 deleted 占账不同。

Parent python `Tests.ContractChecks.test_offline_pack_and_nav_consent` **13/0**. XCTest NOT_RUN on Linux. SHA256 digest-length-only. Not 100%.

## Addendum 2026-10-23 19:50 America/Los_Angeles

HEAD `5ac3c6d0` tests. Did not invent recoverOriginal.

`OfflinePackOperationTests.testUnusedRecordFullDiskOfIdleDoesNotOccupyThenUniqueStartThenFullDiskApplies`：idle `recordFullDisk` 抛 notDownloading 且 phase 仍 idle、operationID 仍空；后续唯一 startDownload+recordFullDisk 才是 fullDisk（抛 fullDisk 发生在占账之后）。与 unused recordCorrupt 的 corrupt 占账不同。

Parent python `Tests.ContractChecks.test_offline_pack_and_nav_consent` **13/0**. XCTest NOT_RUN on Linux. SHA256 digest-length-only. Not 100%.

## Addendum 2026-10-23 19:54 America/Los_Angeles

HEAD `bdb0db08` tests. Did not invent recoverOriginal.

`OfflinePackOperationTests.testUnusedApplyUpdateOfIdleDoesNotOccupyThenUniqueStartFinishThenUpdateApplies`：idle `applyUpdate` 抛 notReady 且 phase 仍 idle、operationID 仍空；后续唯一 startDownload+finishDownload+applyUpdate 才是 updating。与 unused recordFullDisk 的 fullDisk 占账不同。

Parent python `Tests.ContractChecks.test_offline_pack_and_nav_consent` **13/0**. XCTest NOT_RUN on Linux. SHA256 digest-length-only. Not 100%.

## Addendum 2026-10-23 19:57 America/Los_Angeles

HEAD `a7050d73` tests. Did not invent recoverOriginal.

`OfflinePackOperationTests.testUnusedFinishUpdateOfIdleDoesNotOccupyThenUniqueUpdateThenFinishApplies`：idle `finishUpdate` 抛 notDownloading 且 phase 仍 idle、operationID 仍空；后续唯一 startDownload+finishDownload+applyUpdate+finishUpdate 才是 v2 ready。与 unused resume 的 v1 ready、unused applyUpdate 的 updating 占账不同。

Parent python `Tests.ContractChecks.test_offline_pack_and_nav_consent` **13/0**. XCTest NOT_RUN on Linux. SHA256 digest-length-only. Not 100%.

## Addendum 2026-10-23 20:13 America/Los_Angeles

HEAD `8388b9a9`. Aligns with hengyin #580 `03df83ec9` for Dot C05 03:05Z: expire bound by expiresAt; payload SHA-256 finish; approvedAlternative requires attested+authority; PlaceCapacitySourcing missing is WAITING_SOURCE.

Parent python `Tests.ContractChecks.test_offline_pack_and_nav_consent` **13/0**. XCTest NOT_RUN on Linux. SHA256 digest-length-only. Not 100%.

## Addendum 2026-10-24 03:45 America/Los_Angeles

Signed lifecycle patch `complete.patch` is 6820 bytes, SHA256 `12b63255598eeb4d686522414855ed27929171e46cea4204a445eab168c0d2e0`. Local before matched `8c6148ba`: Core `7695284f6d5fb9a439bdd8629ed2bb008979c6894d960ed3493c0a67625fa8ac`, tests `3ef2502d72a75afb097db799ed7db3d6ddb12150d3afc6aba941e7f62407b54a`. After matches Core `bf8aa16fe06f270ec5e848ad14a0fd3389393e339e3b556efc5bb808e2d5d267` and tests `1186f86ddaa8e688b9d13b56321eabfba6b2652f906b5451b3036d20f399381c`. `git apply --check` was 0 on the clean owner tree. Clearing a retained prior also clears `priorFileAccepted`. Restore requires the retained pack id to equal the current pack id. Python 13/0. XCTest NOT_RUN. This is not a real file install. `offlinePack.payloadConsumer` stays WAITING_SOURCE. Not 100%.

## Addendum 2026-10-24 lifecycle entry

`Core/OfflinePackLifecycleFlow.swift` walks one ordered entry on the existing machine: begin, pause, resume, corrupt, fullDisk, expire, delete/exit. It does not rewrite `OfflinePackOperation` and does not create payload bytes. Corrupt, full disk, and expire report only that machine's previous good pack or its existing failure. Delete/exit stays deleted and does not claim installed. The single blocked action remains `offlinePack.payloadConsumer`. qmod final ops, the T41 scoring writer, and the volume-12 resume writer stay WAITING_SOURCE. XCTest NOT_RUN on Linux. Not 100%.
