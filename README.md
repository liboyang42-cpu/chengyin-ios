# Questify · native iOS

SwiftUI-first iOS app, with UIKit bridges only when a feature needs them. Independent of the preserved Flutter app, which remains a candidate Android client. This folder is a new implementation, not a completed migration.

## Current implemented slices, with limits

Development is on `migration/native-ios`, not the foundation-only `main`. See [current branch checks](https://github.com/liboyang42-cpu/chengyin-ios/actions?query=branch%3Amigration%2Fnative-ios) and `PROGRESS.md` for exact commit/run evidence. This is not a finished migration or a release-ready application.

- Player/merchant entry intent, persistent English/Chinese/System language, separate CN/US operational profiles
- Home feed, activity and route/topic detail, templates and read-only route previews
- Owner ACTIVITY/TOPIC saved-draft browser in Account, with scoped read-only metadata and bounded historical installed-module receipt summaries, honest unavailable/editor states and default cloud-read approval disabled
- Account-scoped local play-template authoring, seven advanced game configurators, story previews and separate prefab narrative-state preview; production publishing remains disabled
- Personal orders, ticket wallet/detail, participants, badges and limited profile editing
- Source-backed order progress/refund readback, immutable local action reviews and dormant payment/redemption contracts with live dispatch disabled
- Club browsing, join/application/leave and limited application/member management; guarded create/edit/settings/admin-role review and scoped dormant operation adapters with production writes disabled
- Merchant permissions/dashboard/orders/projects, guarded application/status forms, source-backed store/resource catalogs and dormant exact save adapters with partial-story replay locks
- Coupon publication drafts/reviews, owned definition list/detail and stop-distribution reviews, with exact dormant HTTP adapters, account-scoped durable replay locks and no invented claim route
- Manual-area roaming, conversation/history and text-composition foundations
- Registration form/quote/status and play-session/task foundations, with unverified write capabilities gated
- Source-backed dormant Play branch/run/leader/advanced/player/circle runtime, native review/readback screens and local timing/device-provider state machines; live hardware, persistent write journals and remaining specialized widgets still need acceptance
- Official-event discovery/detail, joined events, publisher history/stats and invitation inbox as separate read-only destinations
- Square feed/detail/comments, following the exact source routes rather than assuming deployed readiness
- Public profiles, invitation history with honest partial-reward states, play guide/info, and source-backed social action review with default live writes disabled
- Message image-preview infrastructure with explicit loading and gated production media origins
- Native content cards and restrained motion, Reduce Motion handling and synthetic accessibility presentation scenarios
- Dormant Project/Club/Merchant/Team HTTP adapters, scoped persistent replay locks and distinct acknowledgment/unknown outcomes; default production capabilities remain off
- Pure Swift domain tests, synthetic XCUITest flows, unsigned CN/US builds and secret scanning

These are partial module slices, not complete source-page or business-flow parity. Static implementation, authored test counts, passing tests and live acceptance are separate measures.

The backend address and approval registry are intentionally empty. Login remains unavailable without independently approved deployment/capability checks. The retained legacy password endpoint needs a WeChat-code prerequisite that a username/password-only native request cannot satisfy; the normal native composition cannot enable it, even with a verification flag. The [CN native session contract](docs/cn-native-session-contract.md) instead mounts the existing SMS-code path only under independently reviewed phone/deployment capability evidence, with authoritative account readback before persistence. Its source alignment does not establish real SMS readiness. US Apple challenge/exchange/protected-session code does not establish real Apple readiness. The US adapter remains hard-off and unmounted. Merchant entry intent never grants merchant permission.

Production registration creation, payment/payout, QR redemption, complete gameplay, media/realtime messaging and substantial publishing/administrative workflows remain incomplete or gated. Live backend/accounts/data, provider configuration, legal content, full visual/accessibility coverage, physical devices, signing and distribution still need acceptance. Review individual module documents for their exact limits.

## Latest offline closeout

See [native safety and app-unit closeout](docs/native-closeout/integration.md) for the latest local integration, exact hashes and finite activation gaps. App-hosted unit-test wiring is present; Apple execution remains unverified. NPC voice configuration, upload reconciliation and WeChat SDK limitations are explicit. All production grants remain off.

## Build and test (requires an approved toolchain)

Minimum provisional deployment target: iOS 17. Pure-domain Swift Package tests require macOS 14 for Observation. Final supported OS range is still to be confirmed. The Bundle ID is deliberately a non-production placeholder. No signing team is configured.

Use the Apple toolchain recorded by the current CI run (currently GitHub-hosted macOS 26 / Xcode 26.6), rather than assuming every older Xcode is compatible:

```sh
xcodebuild -project Questify.xcodeproj -scheme Questify \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
swift test
```

Open `Questify.xcodeproj` for the SwiftUI previews. Test English/Chinese, system language, reopen after choosing a language, text sizes up to accessibility maximum, VoiceOver, dark mode, role-sheet dismissal and repeated selection. Device and live-backend validation remain separate gates.

Project structure and resource checks available in this cloud workspace:

```sh
python3 tools/generate_project.py
python3 tools/check_scaffold.py
```

These Python checks do not compile Swift or demonstrate a working iOS app. See `PROGRESS.md` for the latest verified revision, `docs/verification.md` for earlier evidence, and `docs/migration-plan.md` for scope.

Public CI runs native-local Python contracts without copying the external Flutter checkout. Source-parity comparisons that need the optional sibling `../app-audit` checkout report explicit `SKIPPED` / `NOT_RUN` results when it is absent; they are not source-verification passes. Mixed native/source checks are separated so missing external evidence does not suppress their native assertions. The newly separated comparisons also accept `CHENGYIN_FLUTTER_SOURCE_ROOT` as an explicit checkout root. An explicitly supplied missing root, or missing/malformed files inside a present root, fails those comparisons rather than skipping them. No workflow currently fetches an external Flutter baseline.

## Repository and security boundary

Target repository: `chengyin-ios` (public). Flutter history, deployment scripts, signing material and third-party artwork have not been copied. No open-source license has been assigned to this new code without an ownership decision.

## CI scope

`Native iOS checks` runs on pushes to `main` and `migration/native-ios`, PRs and manual dispatch. It uses GitHub-hosted macOS for pure Swift tests, unsigned simulator/device compilation and targeted simulator UI tests, plus a separate read-only Gitleaks job. It does not connect a production backend, sign a distribution IPA or upload to a store. No release credentials or installable distribution artifacts are used. Explicit synthetic UI screenshots are retained for one day; they are not real business data or release packages. A successful compile or limited UI suite is not complete product acceptance.

Development stays on `migration/native-ios`; one overall PR follows completion of the full migration and its acceptance gates.
