# UG / U gap table: owner hand-off package (2026-11-08, UI checklist v2.9) vs iOS app

Status: **DRAFT** (read-only static comparison; nothing was built, run, or exercised against a server).

- App code: `origin/wip/wave5-build` @ `3f4f60536` (detached worktree `/private/tmp/ugdiff`). Evidence is grep-based `file:line`.
- Backend: production = commit `014fc0d8` (confirmed to be an ancestor of the snapshot); snapshot = branch `integration/20261108/ios-backend-all` @ `f3aecb89` in `/private/tmp/be-merge`.
- Package: `/private/tmp/ownerhand/docs/owner-plan/handoff-20261108/` (先读我, 内容合同 v1, UI优化施工清单 v2.9, 来源与校验.json). The package says itself it is a document hand-off, "not runtime acceptance"; backend UG classes are source candidates, not compiled and not wired.
- Package scope: the checklist summary table (section 1) lists U02-01..05, U03-01..04, U04-01..04, U05-01..04, U06-01..04, U07-01..05, U08-01..05 and UG-01..12 (43 items). There are no other numbered UI items. Sections 16 to 18 (commerce, video bounty, host tips, attribution; M3 to M7) are unnumbered and are covered under "Cross-cutting findings" and "Unnumbered".

## How backend status was determined

- `ios-backend-all` contains **zero** matches (Java, docs, SQL) for: `play/help`, `hintLadder`, `hintFreeUsesPerRun`, `HangmanGameplay`, `AccusationTemplateSupport`, `ClueTransformSupport`, `QaOptionMediaSupport`, `missingCapabilities`, `ContentCapabilityRequirements`, `PlayCommandErrorContract`, `video-bounty`, `host-tip`, `post-game-outcome`, `public-catalog`, `paidTicketMissing`, `settlementSummary`, `revenueState`, `bindingIssues`, `aggregateOwnedCampaign`. Its `be-gNN-report.md` files cover merchant authoring, club, friend graph, IM, channels and city-game (G01..G36, `backend-integration-report.md`). None covers UG, U02..U08 or M3..M7. Per `backend-integration-report.md` section 6, the workshop paid purchased/install stack was not merged.
- Because `014fc0d8` is an ancestor of the snapshot, a term absent from the snapshot is inferred absent from production. Marked "missing (inferred)".
- Present in production at `014fc0d8` (verified by `git show`): `ApiPlayProgressController.java` with `GET /nodes` (:39), `GET /action-receipt` (:78), `POST /puzzle/reveal` (:146), `POST /puzzle/hint` (:166), `POST /arrive` (:230), `POST /hint/unlock` (:308); and `GameSessionRuntimeServiceImpl` (`PLAYER_HINT`). Nothing else was checked against production. Production runtime behaviour is **UNVERIFIED**.
- The package's own backend evidence (G0..G7, B2..B8, M3..M7) is not in the snapshot, so for those items the answer is "package-claimed, source candidate, not in ios-backend-all".

## Capability strings: what the package actually defines

Contract v1 section 3 / appendix A and B define only the shape `clientPlatform`, `clientVersion`, `supportedCapabilities[]` (client to server) and `{supported, missingCapabilities[]}` (server to client). The only strings written out are examples: `node.photoCheck@2`, `node.scan@1`, `node.compass@1`, `engine.zodiac@1`, `hint.ladder@1`, `node.voiceAnswer@1`. The UI checklist adds `compatibility{supported, source, missingCapabilities[]}` on `GET /api/play/nodes`, with `source` in `UNDECLARED` / `MALFORMED`. **The package gives no capability string for hangman, image options, accusation, early closure, skip, clueTransform, publish-status, seats, delivery and so on.** The column below says "not defined" in those cases. I have not invented names. The App declares nothing today: zero matches for `supportedCapabilities|missingCapabilities|clientPlatform|UNDECLARED` in `App/` and `Core/`.

Status legend: EXISTS, NEEDS CHANGE, WAITING ON BACKEND, NOT PRESENT (not an iOS surface, or no app code at all and no backend).

## Gap table

Column "MP risk" is the mini-program consistency risk. "Min iOS change" is always behind a capability check or a server-supplied availability fact; no mock data; UNKNOWN/UNBOUND/null must never render as 0.

### U02 template and city

| Item | Title | App status and evidence | Backend | Capability | MP risk | Min iOS change |
|---|---|---|---|---|---|---|
| U02-01 | Template detail states adoption conditions | NEEDS CHANGE. Detail read exists: `Core/DiscoveryService.swift:42,47` (`topic-template/list`, `info`); `App/TemplateDetailParityFixtureHost.swift`. No city, people, support or licence summary fields found. DRAFT: UI fields not walked. | B2 `contract-v2` fields: missing (inferred) | none defined | MP shows "待补充" for missing fields; iOS must not show empty tags | Decode the added fields as optional; show "to be supplied" when absent |
| U02-02 | Adopt: keep location or change city | NEEDS CHANGE. `Core/TopicTemplateUse.swift:5,22,40,62` decodes only `copied(topicId:)`. None of `bindingIntent`, `targetCityCode`, `pendingRebindSlotKeys`, `bindingIssues`, `sourceTemplateTopicId`, `sourceConfigVersion` exist in `Core/`. `adopt-draft` is used only in `Core/ModInstallationTemplateEdit.swift`. | `/use` extras: missing (inferred), `bindingIssues` 0 hits. `/use` itself: present. | none | Rule to copy: only `level=error` blocks publish, `warn` only hints. Two entry points (`/use` vs `adopt-draft`) must not be mixed. | Add optional decode of the extras. `warn` is advisory only. Do not send a change-city param until the backend ships it. |
| U02-03 | Location to-dos and on-site re-confirmation | EXISTS (partial). Place pickers: `App/ProjectNodePlacePicker.swift`, `Core/ProjectNodePlaceSelection.swift`, `App/ProjectPendingNodePlacePicker.swift`. No "affected items after city change" list. | location contract: missing (inferred) | none | MP reads from the same binding projection | Wait for the contract; no local derivation of affected items |
| U02-04 | Source version and adoption update | WAITING ON BACKEND. No lineage fields in `Core/`. | lineage: missing | none | Old data must show "history source to be checked" | Show lineage only when returned |
| U02-05 | Attribution, language and public preview | NEEDS CHANGE (DRAFT). Media review exists: `App/TemplateMediaReviewPanel.swift:8,18`, `Core/TemplateAuthoringMediaIdentity.swift:14`. Requested vs actual language and licence fields not found. | unverified | none | Preview must not leak route answers | Display licence and language fields when supplied |

### U03 publish

| Item | Title | App status and evidence | Backend | Capability | MP risk | Min iOS change |
|---|---|---|---|---|---|---|
| U03-01 | Publish check with exact location | EXISTS (list only). `Core/NativeAttributeAuthorChecks.swift:4-24` parses `level/code/nodeId/message/field` only; `Core/ProjectEditIssueLocation.swift`; `Core/NativeAttributeAuthorService.swift:23` (`api/topic/publish-check`). No `blockKey/fieldPath/kind/status/checkVersion`; `UNVERIFIED` is not representable. | Existing list: present (`publish-check`). Field-level: missing (the package itself calls it a proposal). | none | MP maps `field` locally; do not fake chapter/block positions | Add optional `kind/status` decode only once a contract exists; `UNVERIFIED` is not `warn` and not pass |
| U03-02 | Publish result with next step | WAITING ON BACKEND. No `publish-status` consumer anywhere in `Core/`/`App/`. Result views exist: `App/TemplateAuthoringPublishResultPresentation.swift`, `Core/TemplateAuthoringPublishReceipt.swift`. | `publish-status` five-part projection: missing (the only hit is an unrelated `PmsProductController`) | none | MP shows commercial review separately | Render five segments (draft/review/visibility/sale/playable) from the server. Never derive one from another. |
| U03-03 | My projects: consistent status | NEEDS CHANGE. `App/TemplateAuthoringMineView.swift:87,90,142` and `Core/TemplateAuthoringShelf.swift:75-93` collapse to `publishStatus == 1` plus a `market` enum. The package says one status must not stand for everything. | five-part projection missing | none | MP shares one mapping across list, detail and result | Move list to the same five-segment mapping when available; unknown value is not success |
| U03-04 | Admin audit and template status | NOT PRESENT (Vue admin `chengyinhub-ui`, out of iOS scope). | n/a | n/a | n/a | none |

### U04 full play

| Item | Title | App status and evidence | Backend | Capability | MP risk | Min iOS change |
|---|---|---|---|---|---|---|
| U04-01 | Full story in order | EXISTS (DRAFT on block order). `Core/PlayContracts.swift:241-262` (`chapters`); `Core/PlayExperienceContracts.swift:94-100` (`chapterStories`); `Core/ChapterStoryContracts.swift`. | `GET /api/play/nodes` present (`ApiPlayProgressController.java:39`, in production) | none | Same content identity, same order | Verify against shared fixtures; unknown required structure blocks |
| U04-02 | Choice, evidence, ending payoff | EXISTS (DRAFT). `App/PlayThemeBackpackView.swift`, `Core/PlayThemeBackpack*.swift`, `Core/PlayContracts.swift:62` (`completionMode`). | present | none | Same receipt must not pay twice | none beyond fixtures |
| U04-03 | Capability check before buy or start | WAITING ON BACKEND. No `compatibility` field decoded for `/api/play/nodes`. (`Core/ModInstallationWire.swift:23` and `Core/H5SourceSubmissionInspection.swift:64` are different, unrelated capability shapes.) | `compatibility{supported,source,missingCapabilities}`: missing (`ContentCapabilityRequirements` 0 hits) | `clientPlatform`, `clientVersion`, `supportedCapabilities[]`; response `supported`, `missingCapabilities[]`, `source` (`UNDECLARED`/`MALFORMED`); example `hint.ladder@1` | Contract section 7: undeclared = "unconfirmed", not blocked | Declare real capabilities; `UNDECLARED` is not "unsupported", `MALFORMED` is not "supported"; no placeholder card as playable |
| U04-04 | Media, audio, reading position | EXISTS (DRAFT). `Core/PlayReading.swift`, `Core/ChapterStoryContracts.swift`. Not walked. | n/a | none | Reading position is not progress | none |

### U05 recovery

| Item | Title | App status and evidence | Backend | Capability | MP risk | Min iOS change |
|---|---|---|---|---|---|---|
| U05-01 | Arrival failure reasons | WAITING ON BACKEND. No `errorCode/reasonCode/retryable/refreshRequired/newActionIdRequired` handling for play (grep 0 hits). Client-side accuracy gate elsewhere: `Core/RoamLiveService.swift:64` (80 m). | `/arrive` present (`ApiPlayProgressController.java:230`). Stable reason codes (`PlayCommandErrorContract`): missing. | none | Do not widen the fence on poor accuracy | Branch on codes once returned; retry only the original intent |
| U05-02 | Closed place and approved fallback | WAITING ON BACKEND. Only on-site reject payload in `App/PlayDirectorView.swift:202,206`. No fallback fields. | missing | none | No unconditional skip-with-reward | Show only server-approved fallbacks |
| U05-03 | Unknown submit and restart recovery | NEEDS CHANGE. Game-session path: `Core/PlayGameSessionRuntime.swift:119` (`api/game/session/receipt`), `:154` (stale on session switch), `:207` (`PENDING` becomes `unknown`); `Core/PlayGameCommandJournal.swift:11,25` keeps `requestID`. Classic hints use a different path (see UG-05). The package names `GET /api/play/action-receipt`, but **no Swift file calls `api/play/action-receipt`**; production serves it (`ApiPlayProgressController.java:78`). `receiptState/intentTerminal/newActionIdRequired` are not parsed. | `action-receipt` present in production. B5 terminal/unknown definitions: missing. | none | MP uses `receiptState=UNKNOWN/PENDING` as "to be confirmed", never failure | Add the B5 terminal/unknown rules to the one recovery path; new actions reuse the same `requestId` |
| U05-04 | Download and limited offline reading | NEEDS CHANGE (DRAFT). No player-side per-resource download state found (only audit files such as `Core/ImageAndVideoDiskCacheBudgetAudit.swift`). | n/a | none (package says offline package is not verified) | Offline must not show paid/competition/settlement as done | Per-resource state with retry; never present offline as server fact |

### U06 multiplayer

| Item | Title | App status and evidence | Backend | Capability | MP risk | Min iOS change |
|---|---|---|---|---|---|---|
| U06-01 | Invite, seats, members | WAITING ON BACKEND. `Core/TeamContracts.swift:8,17,24` has only `joinedCount/maxMembers`. Block codes already handled for nearby teams: `Core/NearbyTeamContracts.swift:143-152`. No `seats.*/invite.*/viewer.*`. | B6 `seats`: missing (`paidTicketMissing` 0 hits) | none | The removed fields `claimable`, `reservedApplications`, `unpaidOccupied`, `viewer.memberId` must never be reintroduced | Decode only the listed seat fields; do not compute claimable seats; last-seat race is decided by the write response |
| U06-02 | My role and private clues | EXISTS (DRAFT). `Core/PlayGameSessionRuntime.swift:40-48` (role confirm gating); `App/PlayPlayerTeamStatusView.swift`. | present (projection) | none | Hiding a button is not authorization | none |
| U06-03 | Leader offline, leave, takeover | WAITING ON BACKEND. `LEADER_HANDOVER_FAILED`, `TEAM_STATE_CHANGED` have no Swift hit. | B6 codes: missing | none | Do not add reserve seats or takeover entry | Map codes when delivered |
| U06-04 | Organizer, merchant, shared result | EXISTS (DRAFT). `App/TeamOrientBoardView.swift`, `Core/TeamOrientBoard.swift`. | n/a | none | Club total is not one run's participants | none |

### U07 trade and after-sales

| Item | Title | App status and evidence | Backend | Capability | MP risk | Min iOS change |
|---|---|---|---|---|---|---|
| U07-01 | Product and quote delivery | WAITING ON BACKEND. `Core/OrderLifecycleContracts.swift:3-25` has `purchaseKind` as a String, `payableAmount`, no `delivery{...}`/`paymentChannels`. (`Core/ProfileContracts.swift:90` types `purchaseKind` as Int; the two disagree.) | B7 `delivery`: missing | none | Mixed-ticket orders: `delivery` fields are null, show "per ticket type" | Decode optional; null means "per ticket type"; `refundRule=null` never shows "refundable" |
| U07-02 | Verify order after payment return | EXISTS. `Core/OrderPaymentVerifier.swift:9,12,41` (SDK result is not entitlement; reconcile against server). | present (registration detail) | none | SDK success with pending order must not open entitlement | none |
| U07-03 | Purchased workshop install | WAITING ON BACKEND (BLOCKED). Client contract exists: `Core/WorkshopPurchasedContracts.swift:53` (`PAID_INSTALL_AUTHORITY_UNAVAILABLE`), `Core/WorkshopPaidInstall*`. Must show "unavailable". | missing; `backend-integration-report.md` section 6: stack "NOT merged" | none | No fake install | Keep the unavailable state; do not call paid-install endpoints |
| U07-04 | Cancel and partial refund impact | WAITING ON BACKEND. Only `App/CooperationInviteDetailView.swift:116` ("refundPending" label). No `refundStage`/`refund*Amount`/`amountsComplete`. | `settlementSummary`: missing | none | `amountsComplete=false` means the total is not a fixed value | Show amounts only if complete; "accepted" is not "arrived" |
| U07-05 | Finance and creator revenue | NOT PRESENT for creator revenue on iOS (Vue admin is out of scope). iOS merchant dashboard uses `MerchantMoney.display` (`Core/MerchantContracts.swift:209-211`: nil becomes an em dash, good). No `revenueState` decoding. | `CreatorRevenueLedger`/`revenueState`: missing | none | AVAILABLE/UNKNOWN must not surface as text; show "accrued" (应计) wording, never "withdrawable" | If added: UNKNOWN shows "revenue unavailable", never 0 |

### U08 after the game

| Item | Title | App status and evidence | Backend | Capability | MP risk | Min iOS change |
|---|---|---|---|---|---|---|
| U08-01 | Result, private photos, sharing | EXISTS (DRAFT). `App/PlayOpeningCompletionSection.swift`, `App/PlayTaskOutcomePresentation`-family (`Core/PlayTaskOutcomePresentation.swift`). | present | none | Photo/end-time alone is not a valid completion | none |
| U08-02 | Next-route recommendation, feedback | EXISTS. `Core/PlayFinishRouteRecommendation.swift:1-12` (mirrors MP `finish-route-recommendation.js`, gated by `finishNearbyRoute`), `App/PlayFinishRouteCardView.swift`. | feature flag present in MP contract; prod UNVERIFIED | none | Click is not enrollment | none |
| U08-03 | Creator maintenance workbench | NOT PRESENT (maintenance chain). Creator views exist (`App/CreatorContentViews.swift`) but not the issue-to-close chain. | missing | none | n/a | Wait |
| U08-04 | Second-enrollment board | WAITING ON BACKEND. No iOS surface and no `post-game-outcome` anywhere. | missing (0 hits) | none | `mature=false` shows "immature", never 0%; `retainedMembers=null` shows an em dash | If surfaced, same rules |
| U08-05 | Leaderboard and content governance | EXISTS. `App/PlayPlayerLeaderboardView.swift`, `Core/PlayPlayerLeaderboardReadback.swift`. Package: leaderboard does not read score, so do not claim hints affect rank. | `LeaderboardRankPolicy` unchanged | none | Must not say net score decides rank | none |

### UG new gameplay

| Item | Title | App status and evidence | Backend | Capability | MP risk | Min iOS change |
|---|---|---|---|---|---|---|
| UG-01 | Hangman slots | WAITING ON BACKEND (no app code: zero hits for `hangman/SUBMIT_HANGMAN` in `Core/` and `App/`). Closest: type-in rehearsal only (`Core/TemplateCreatorRehearsal.swift:39`). | `HangmanGameplay`: missing (inferred); package: source candidate, not wired | not defined | Same `publicProjection` and action name; slot logic from server only | After capability exists: slot view from server `slots[]`; client never slices the answer; keep user input on error |
| UG-02 | Image options | WAITING ON BACKEND. Author side holds option `img`/`audio` references (`Core/TemplateChoiceOptionMedia.swift:5-26`, 500-char limit) but **no `alt`** (0 hits). Player side: `PlayKitOption` has only `id/label/raw` (`Core/PlayKitScreenContracts.swift:22-23`); `App/PlayKitQuestionForms.swift:14-16,33-34,62-65` render text only. | `QaOptionMediaSupport`: missing; MP: option img not wired in-game either | not defined | If `img` is not delivered, show text only; never show a raw `media-asset:` or broken image | Add `img/alt` to `PlayKitOption` with a text-only fallback; `optionId` submit unchanged; author alt is required when img is set |
| UG-03 | Accusation | WAITING ON BACKEND. No `accusation` anywhere (single unrelated comment `Core/SafetyDisclosure.swift:176`). | `AccusationTemplateSupport`: missing | not defined | Correct suspect derives from QA `correct`; no second answer | Cards, dossier, "final accusation" confirmation; confirm counts as the attempt, selection does not |
| UG-04 | Early closure | WAITING ON BACKEND. Endings have no three-state label. `recordAs` free text must never be shown. | missing | not defined | Not a failure, not a win | Three-state label from server only; "settling" while unknown |
| UG-05 | Hint ladder | WAITING ON BACKEND. Legacy hints exist and must stay when `enabled=false`: `App/PlayPlayerAndCircleViews.swift:81-87`, `Core/PlayGameSessionRuntime.swift:52-54`, `Core/PlayPlayerActionReview.swift:57-61`, `Core/PlayExperienceService.swift:118-125` (`api/play/hint/unlock`, `api/play/puzzle/hint` with a hard `1...2` level check), `Core/PlayExperienceContracts.swift:108-129`. No `layers[]`, no `GET /api/play/help`. | `play/help`, `hintLadder`: missing. Production serves only the legacy routes. | `hint.ladder@1` (example in contract appendix A; not confirmed as the final name) | Unknown `type` must degrade to unavailable; `DIGIT` conflict unresolved in package | Render `layers[]` dynamically; no layer count hard-coded; keep legacy path when `enabled=false` |
| UG-06 | Shared free quota | WAITING ON BACKEND. No `remainingFreeUses`/`hintFreeUsesPerRun`/`chargedPoints` anywhere. | missing | `hint.ladder@1` (as above) | Quota shared per run; price-0 layers always free and never consume it; do not infer from `freeQuota` | Display server `remainingFreeUses`, per-layer cost; no local decrement; insufficient points = nothing unlocked |
| UG-07 | Usage detail and net score | WAITING ON BACKEND. Only a raw `completionMode` string in `App/PlayNodeDetailView.swift:151` (`Text(verbatim: mode)`). No base/bonus/deduction/net fields. | `PlayHelpOutcomeSupport`: missing | not defined | Do not say hints change global rank (rank ignores score) | Localised labels, no raw enums; missing detail shows "detail pending", not 0 rows |
| UG-08 | Skip | WAITING ON BACKEND. No `help/skip`. `Core/RunAuthorityContract.swift:18` has a `skipped` node state (a different layer). Hazard: raw `completionMode` shown verbatim (`App/PlayNodeDetailView.swift:151`). | `help/skip`: missing; package says `action=SKIP` is rejected at runtime | not defined (button only when the server says available) | Skip is not "answered correct", "arrived", "scanned", or "success"; the MP read-side `SOLVED/REVEALED` allow-list risk applies to iOS too | Button only when the server says so; confirm text "0 points, assisted"; label "Skipped" |
| UG-09 | Unknown network: query the original receipt | NEEDS CHANGE. Machinery exists (see U05-03): `Core/PlayGameSessionRuntime.swift:119,154,207`, `Core/PlayGameCommandJournal.swift:11`. The new actions (hangman, help/use, accuse, skip) are not routed through it; `PlayPlayerCommand.Action` has 5 cases (`:60`). The help path uses form-POST without a journal. | `/api/play/help/use` `requestId` required: missing | none | Same `requestId` on retry; no `replayed` field | Route every new action through the same journal and receipt read |
| UG-10 | Clue transform | WAITING ON BACKEND. No `clueTransform`/mirror handling. | `ClueTransformSupport`: missing | not defined | Mirror flips only the clue text layer, not inputs or buttons; reverse renders the server string untouched | Mirror only the text layer; unknown `mode` shows the original text |
| UG-11 | Author hint panel | EXISTS (legacy only). `Core/TemplateLegacyHints.swift:4,7,18,27` and `App/TemplateLegacyHintFields.swift` (`hint1/hint2/answerReveal`). No `hintLadder` editor. | `hintLadder` save/freeze: missing | `hint.ladder@1` | Old fields merge into the new place; do not leave two forms | Hold the editor until save/freeze exists; no GEMS/COINS fields |
| UG-12 | Admin: review, quota, detail | NOT PRESENT (Vue admin out of iOS scope). | missing | n/a | n/a | none |

## Counts

43 items, by primary status in the tables above:

| Status | Count | Items |
|---|---|---|
| EXISTS | 12 | U02-03, U03-01 (list part only), U04-01, U04-02, U04-04, U06-02, U06-04, U07-02, U08-01, U08-02, U08-05, UG-11 (legacy part only) |
| NEEDS CHANGE | 7 | U02-01, U02-02, U02-05, U03-03, U05-03, U05-04, UG-09 |
| WAITING ON BACKEND | 20 | U02-04, U03-02, U04-03, U05-01, U05-02, U06-01, U06-03, U07-01, U07-03, U07-04, U08-04, UG-01 to UG-08, UG-10 |
| NOT PRESENT | 4 | U03-04, U07-05, U08-03, UG-12 |

Several EXISTS rows are only "DRAFT, matched by file/symbol, not walked".

## Cross-cutting findings

1. **Capability negotiation does not exist on either end we can see.** The App sends and parses no capability fields. The snapshot has no `missingCapabilities`. The package defines only the shape and a handful of example strings. Needed before any UG item: names for each capability, the transport (header or body of `/api/play/nodes`), and the decision on the two contradictory rules (contract line 129 "reject on missing capability" vs BE-07 "undeclared = unconfirmed, do not block"). The package itself says the owner must rule on this (UI checklist 10.3). iOS must not pick one side.
2. **Hint quota and ladder.** Today the App has only the legacy two-level hint (`level 1...2` hard-coded in `Core/PlayExperienceService.swift:120`, button gated on `nextLevel` and `nextImpactLabel`). The final package rule is a per-run shared N free uses, with layers rendered from the server and price-0 layers never consuming quota (checklist 17.1). The package contains stale statements to ignore: the v2.5 per-layer `freeQuota 0|1` and "no remaining counter" text, and the early G7 "price 0 and quota exhausted means refuse". Several package places (10.1, 12) still list the older model, so the owner's v2.9 header is the arbiter.
3. **SKIP handling.** Backend route `help/skip` is a source candidate and `action=SKIP` is rejected at runtime per the package. The App has no skip. One existing hazard: `App/PlayNodeDetailView.swift:151` prints `completionMode` raw, so a future `SKIPPED` would show as a raw enum. Also check any iOS gate that allow-lists `SOLVED/REVEALED` (the package's own G6 risk note).
4. **Publish-status projection.** `publish-status` (five segments) is absent from the snapshot (the only hit is an unrelated product controller). The App derives library state from one integer (`App/TemplateAuthoringMineView.swift:87`, `Core/TemplateAuthoringShelf.swift:75-93`), exactly what the package says not to do. Fix once the projection exists; until then show unknown rather than infer.
5. **Commerce and analytics UNKNOWN vs 0 in our views.** Good: `MerchantMoney.display(nil)` returns an em dash (`Core/MerchantContracts.swift:211`). Risks found:
   - `Core/MerchantMarketingHome.swift:103`: `heroValue` is `compact(analytics?.stage("SIGNUP")?.currentCount ?? 0)`, so missing analytics renders "0".
   - `Core/MerchantContracts.swift:11,46-50,189-190`: dashboard counts default to 0 with `?? 0` when the key is absent (pending orders, verified, refunds, signup and view counts).
   - Attribution (`UNBOUND`/`OWNER_NOT_SET` carry null counts) and the `?? 0` ban in checklist section 18 G have no iOS surface yet; add the rule when one is built.
   - Two Swift types disagree on `purchaseKind` (String in `Core/OrderLifecycleContracts.swift:18`, Int in `Core/ProfileContracts.swift:90`).
6. **Receipt endpoint mismatch.** Package and production use `GET /api/play/action-receipt`; iOS never calls it (game session uses `api/game/session/receipt`, `Core/PlayGameSessionRuntime.swift:119`). Confirm which path each play mode must use before routing new actions.

## Unnumbered (checklist sections 16 to 18: M3 to M7, video bounty, host tip, attribution, public catalog)

All of: single/pack/gift products, combos, video bounty, host tips (`/api/host-tip/*` returns 501 until a channel exists), attribution reads, public catalog. These are **WAITING ON BACKEND** (missing: 0 hits in snapshot) and have no iOS code in `Core/` or `App/` (grep for `video-bounty|host-tip|public-catalog|OWNER_NOT_SET` found nothing). Rules to carry when built: never show "paid out" for bounty or tips; `null` counts mean unknown, no `?? 0`; no client-side fee or discount computation.

## Questions for the owner

1. Which capability strings (exact names and versions) apply to hangman, image options, accusation/early closure, hint ladder, skip, clueTransform, publish-status, seats, delivery? Only `hint.ladder@1` appears, and only as an example.
2. Resolve the contradiction: reject-on-missing-capability (contract line 129) or unconfirmed-do-not-block (BE-07). The checklist says the UI must not choose.
3. Which exact backend commit/SHA delivers G0..G7, B2..B8, M3..M7? None of it is in `ios-backend-all` (`f3aecb89`), and the package says everything is NOT_RUN. Are there executable fixtures (`playkit-server-actions.json` extension, `content-schema.v1.json`)?
4. Is `GET /api/play/action-receipt` the intended receipt path for iOS, or `api/game/session/receipt`? Which applies to the new help, hangman and accuse actions?
5. Is `DIGIT` hint type allowed? (G5 lists it as optional, G4 records that G5 does not allow it.) Is `SKIP` in `/use` or only a separate `/help/skip` route?
6. Is the `hintLadder` free quota `hintFreeUsesPerRun` at run level confirmed as the final field, and what does `GET` return for remaining uses on legacy runs without a ladder?
7. Does a `publish-status` contract (field names, enum values) exist yet beyond the five segment names?
8. Is the iOS client expected to ship the admin-only items (U03-04, U07-05 admin, U08-03, UG-12)? Treated here as not iOS.
9. The `purchaseKind` type conflict (String vs Int) between the order and profile contracts: which wire type is real?

## Unverified or DRAFT in this document

- Every EXISTS row marked "DRAFT" was matched by file/symbol, not by running or reading the UI end to end.
- Production state beyond the play routes in `ApiPlayProgressController` and the existence of `GameSessionRuntimeServiceImpl` was not checked. "missing (inferred)" relies on the ancestor relationship plus zero hits in the snapshot.
