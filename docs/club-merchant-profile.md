# P045 merchant discovery → public merchant profile

## Source and exact preimage

- Base: `94bced23ae734bcd8a5e236c8b992294bd15b14a`. No overlay dependencies. Sealed batches 1–8 are unchanged.
- Master: `MASTER-v10-extracted-text.txt`, P045 lines 1652–1655, `loadMerchants`, `onMerchantKeyword`, `goMerchantProfile`.
- Mini: `f859cd6e2618f618a53f5cd33949259828e86313`, `pages/club/detail/index.js` lines 785–815 and 1465–1472; WXML lines 552–588. The card passes `item.memberId`; `goMerchantProfile` uses the shared merchant-home helper and reports a missing target.
- Exact helper: `utils/merchant-home-link.js`, Git blob `022fa26d8ebfd6ad74ca7230c760a02facd906a0`. The canonical target is the merchant owner's member ID and the About profile, with no cooperation/topic context in this directory entry.
- Verified gap: the existing owner-only local merchant search rendered text cards without any profile action. The existing public merchant-home reader and view were already available.

## Complete flow

Ordinary `ClubDetailView` retains its existing `ClubMerchantDiscoveryView` / cooperation reader inside `SessionClubMerchantProfileHost`. This observes the actual AppSession and injects `session.publicMerchantHomeContext`. No change to AppSession or service configuration is required.

A valid visible merchant card opens the existing `PublicMerchantHomeView` in a native large sheet. Its reader receives only `.ownerMemberID(memberId)`. Positional directory IDs and merchant row IDs are never used as owner IDs. Missing or invalid member metadata leaves the readable card with explicit unavailable feedback. Native positive-integer validation is deliberately stricter than the Mini helper's nonempty-string check.

The existing public-home screen supplies loading, retryable failure, unavailable status and public About/cooperation-capacity information. This entry injects only the existing public reader and optional approved image renderer. It creates no invitation intent, topic context, write permission, payment or external public URL. It does not independently enable other public-home destinations.

Close and interactive dismissal retire the presentation synchronously. Reopening the same rendered card gets a new presentation UUID, so a suspended old request cannot become valid again. The directory remains mounted beneath the sheet; local search, current rows and list position are retained on normal return. No directory reload is triggered by closing the sheet.

## Isolation

- Selection requires the currently visible accepted row, visibility permit and directory read generation.
- Opening and each profile read check the current club/cooperation reader identities, account/epoch/session, owner-bound context and accepted row.
- The normal host also captures session revision, content revision and public-reader scope, covering same-account relogin, role/region/content composition changes.
- The read wrapper rejects a wrong request target before dispatch, checks scope/currentness after await, and verifies both returned owner identity and a positive merchant-row identity.
- Context binding, source refresh, owner loss, source disappearance, profile-scope replacement and close retire the old destination. Existing club ownership re-read rules remain unchanged; no live ownership subscription is invented.

## Registration and acceptance

`club-merchant-profile-registration.fragment.json` lists the two new app/Core sources and the two test files. Merge its two bilingual localization keys centrally. PBX, shared catalog, shared CI, shared fixture hosts and all service/permission code are unchanged.

Executed in the current Linux task workspace:

- 18 focused structural assertions: PASS.
- Exact Mini helper Git hash, five action vectors, WXML member-ID wiring and filter → open → restore metadata: PASS (Node).
- Existing merchant-discovery contract suite: six PASS; its older pinned filter oracle is SKIPPED because that earlier source revision was not supplied. The current exact f859 action/filter oracle above ran separately.
- Seven changed/new Swift files: Tree-sitter syntax PASS, no recovery or diagnostics. This is not Swift typechecking.
- `git diff --check`, exact patch reconstruction, reverse-apply check and sealed-prior SHA verification: PASS.

Authored: ten Core selection tests and nine app-hosted reader/presentation tests. **All 19 Swift tests are NOT_RUN**: no Swift or Xcode toolchain is available here. No native build, simulator UI/VoiceOver test, screenshot, real-account request or production/backend acceptance occurred. Existing runtime public-home configuration remains authoritative; source integration does not claim a live deployment is enabled.

Native acceptance after central registration: search → open exact merchant → retry if needed → close → same search/position → reopen; rapid double taps; interactive dismissal during a held read; same-card close/reopen before old completion; source refresh, owner loss, account/epoch/role/region changes while covered; wrong returned merchant identity. Check both phone and compact-sheet adaptation with Dynamic Type/VoiceOver.
