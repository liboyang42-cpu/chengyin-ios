# Activity publishing result and owner-project readback

## Source scope

- iOS source baseline: `b2cc2d4b8a832e1cce3fbf088642684e795108eb`, tree `43e322f8346c7d5a61dd89d897a0350ab8d311dd`, branch `migration/native-ios`.
- Backend coordination read: `liboyang42-cpu/hengyin` at `60064301f61a72103e094cd9e5ec305bfe784b85`, `docs/plans/mini-codex-cloud-20261015/{IOS_START_PROMPT,IOS_HANDOFF,BACKEND_CHANGES}.md`.
- CY-HANDOFF: IOS, I03 author saving/publishing continuity. This change consumes the already present native `PublishingService`, `PublishingWriteOutcome`, `PublishingProjectsView` and persistent operation journal. It does not adapt a new BK contract or infer deployed backend readiness. Backend control is not a deployment revision; TEST_DEPLOYED remains NO.

## Implemented source change

The existing activity authoring form already supports selecting/creating a play template, local saving, review and guarded submission. Its previous submit completion only changed a message. The form now exposes each existing outcome and, when the current account and service remain available, a dedicated read-only My projects destination.

- `acknowledged` means the request was acknowledged. It does not mean the activity is published or online. The result explains that publication needs server readback.
- `unknown` preserves the original service/journal lock. The screen cannot send again and states that viewing projects does not resolve the original request.
- `notSent` and `rejected(reason)` remain distinct. A fresh review is still explicit; raw rejection text is displayed as text, never interpreted as a localization key.
- The service returns no created resource ID. No ID is invented and no list row is matched to the submitted draft by name, position or timestamp.
- The result destination shows existing server project titles/statuses and list filters. It hides and guards management actions and blocks resource-detail navigation, so it cannot lead into detail editors or publisher lifecycle writes. The normal management entry retains its existing behavior.

An occurrence-bound presentation owner checks exact draft bytes/identity, account/role/epoch, service instance, active scene and navigation lifetime. Duplicate starts are rejected. Late preparation results are canceled rather than shown in a new visit. Review confirmation captures the exact offered review. Modal coverage is distinct from leaving the hierarchy. An interrupted submission is conservatively shown as unknown; the UI never clears its journal or invents successful reconciliation. A newly created owner reads the existing account-wide activity-create pending lock before allowing a review. Lock read failure fails closed. Preparation errors distinguish invalid drafts from network/contract reads, permission rejection and storage failure; stale-session/canceled results are not displayed.

## Files and regression source

- `App/PublishingModesViews.swift`: result surface, existing project-route composition, operation owner and lifecycle anchor.
- `App/PublishingManagementViews.swift`: default-off read-only presentation mode and independent guards on row routing, prepare and submit.
- `Tests/AppUnitTests/ActivityPublishingLocalClearTests.swift`: added result-owner regressions within the existing registered source. Covers four outcomes, repeated taps, stale completions, account/role/epoch/service/draft changes, leave/reopen, modal coverage, inactive submission, persistent unknown-lock readback, storage failure, guest behavior and blocked detail navigation.

The existing `tools/generate_project.py` registers `App/*.swift` and `Tests/AppUnitTests/**/*.swift`; no new runner, workflow or test entry was added or executed.

## Verification limits

Source inspection and original-file hash comparison only. Tests, Swift compilation, simulator, device, App launch and CI are **NOT_RUN** for this change. No live backend, real account, real request or publication status was verified. Default production approvals remain unchanged/off. There are no backend edits, credentials, media uploads, payments, rewards, DDL or deployment changes. Full runtime acceptance, including modal transitions and interrupted requests, remains outstanding.
