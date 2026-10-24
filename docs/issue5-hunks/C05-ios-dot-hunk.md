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
