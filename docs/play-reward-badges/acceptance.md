# Play completion badge collection readback

## Source and actual gap

Baseline native commit `1161bf975172091f49ba6b33fe49ce515ff9eca4`, tree `0ed2ed6d6ac55a13e54fa2e7b6c1e6286776acfc`. The frozen source was copied independently; its inherited local Git HEAD is not the publication identity.

Read-only current mini-program source:
- `pages/play/index.js`, blob `1252e763ef2b4e77efff7bf46ed8ae40006c85ef`, lines 4410–4419 and 4482–4492: completion `newBadges[].code/name`; persistent completion card; explicit collection and Continue actions.
- `pages/play/index.wxml`, blob `b2bc3ff897217c5399028e4733ed67bfbfc92318`, lines 737–750: reward card and two visible next actions.
- `subpackageP3/pages/badge-wall/index/index.js`, blob `b1a5116900d1098e49c10a3d6b26f046e173a6b8`: POST `api/badge/wall-v2` identity collection and POST `api/medal/wall` achievement collection; preserve stable `badgeCode`. Not every growth badge belongs to this wall.

The native baseline's `PlayRewardSection` displayed XP, puzzle score, completion mode and medal name, but did not consume `newBadges` or route its stable code into any collection readback. Existing `ProfileReading.profileBadges()` already supplies both typed authoritative collections and explicit medal-lane partial status.

## One visible increment

After an actual completion response, its valid badge targets appear with View collection and Continue playing. Missing/invalid targets create no reward entrance. Names are receipt hints; they never confirm collection state. Repeated stable codes have one navigation identity. Original reward values remain unchanged.

View collection performs a fresh existing profile read and matches exact code, never display name or template ID. It shows authoritative identity-card name/state/details or achievement name/date. Locked cards remain locked. A complete wall without the code, a partial wall without a match, and duplicate/conflicting matches have different explanations. None asserts non-issuance. Existing Growth Center remains available through its normal read destination; this packet does not add a claim, award, payment or redemption endpoint.

The same native reward card is reachable from the normal orientation host and free-exploration overview. No task is locally completed and no reward is locally minted. Source structure is expressed as native stacks, rows and navigation, without recreating a mini-program web overlay.

## Lifetime and permissions

Collection targets capture the current ProfileReadIdentity, including account, epoch, viewer revision and approval revision. A different owner cannot read an old receipt target. Cached results and errors disappear synchronously when identity or configuration stops matching. The destination also checks the original Play coordinator’s current identity, which becomes unavailable on runtime permission/viewer/context retirement. Current ProfileSessionReader retains transport/credential/401 validation; this feature has no token access or new grant.

Refresh retires the prior read. Back cancels actual reader work and invalidates publication; queued retry operations cannot reactivate a dismissed screen. Reappearance explicitly reactivates and fresh-reads. An immutable same-owner result can remain in the unmounted view so native navigation is not torn down by lifecycle cleanup. Completion cards never auto-dismiss on a timer. Continue dismisses the currently rendered target card only, without changing server facts.

## Integration

Owned fragment: `Resources/PlayRewardBadgeLocalizations.fragment.json` (English and Simplified Chinese). The integrator merges it into the primary catalog and regenerates project membership. This packet intentionally leaves AppSession, CompositionRoot, PBX, CI and the main catalog untouched. There is no new UI-test budget or fixture-root registration.

`SessionPlayRuntimeView` only passes its already retained profile and growth readers through a destination factory. Existing NPC wiring, Play capabilities and every production grant are unchanged. No ordinary collection/Muse feature is touched.

## Verification and acceptance limits

Authored Core tests cover source receipt keys/order, missing/invalid/duplicate codes, identity/achievement separation, locked records, exact-code matching, partial/missing/conflicting results, overlapping reads, cancelled/dismissed work, queued retries, account/epoch/approval changes, logout/config revocation, and retry after failure. App-hosted unit tests cover construction without reads, empty suppression and bounded accessibility-size presentation.

Focused Python checks and supplementary Swift syntax parsing are source evidence only. Swift XCTest, Apple SDK/typechecking, unsigned builds, simulator, physical device, screenshots, VoiceOver, actual navigation timing and real backend issuance are NOT_RUN in this Linux workspace. No live backend request, actual reward issuance, payment, redemption, commit, push or release was performed. Unified E2E remains an integration gate.

## R1: queued dispatch authorization window

R0 is retained unchanged. R1 adds a second owner/lease check inside the actual reader Task, directly before `profileBadges()`, with no suspension between check and invocation. It covers active lifetime, generation, captured profile identity and current configuration, plus the original Play authorization predicate. The view task also rejects cancellation before activating its read owners.

Three new deterministic Core tests retire the Play lease (while Profile stays signed in and unchanged), replace profile account/epoch/approval, or revoke configuration after owner capture and before the inner Task runs. The fake reader's configuration accessor returns its captured value after the state change, and its immediate response prevents a regression from hanging the test. Each asserts **zero reader invocations**, distinct from the existing late-result suppression tests. No production-only test hook or new authority is added. Existing disappearance/task cancellation behavior is retained; it was not the independently identified defect.

R1 authored totals: 19 Core and 4 AppUnit methods, still NOT_RUN without Swift/Xcode. R0 baseline-known photo assertion remains unchanged.
