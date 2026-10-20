# Questify (城印) iOS Release & TestFlight Readiness Checklist

Updated: 2026-10-20 UTC

## 1. Local & Release Signing Configuration (`Config/Local.xcconfig`)

`Config/Base.xcconfig` ships with safe non-routable / empty defaults so CI and unconfigured checkouts remain fail-closed (`CODE_SIGNING_ALLOWED = NO`, `PRODUCT_BUNDLE_IDENTIFIER = com.example.questify`, empty `QUESTIFY_MARKET` / `QUESTIFY_API_BASE_URL` / `QUESTIFY_SESSION_REALM`).

Before archiving for **TestFlight** or **App Store Connect**, create an untracked `Config/Local.xcconfig` (copied from `Config/Local.xcconfig.example`) with your release coordinates:

```xcconfig
CODE_SIGNING_ALLOWED = YES
CODE_SIGN_STYLE = Automatic
DEVELOPMENT_TEAM = <YOUR_APPLE_TEAM_ID>
PRODUCT_BUNDLE_IDENTIFIER = <YOUR_PRODUCTION_BUNDLE_ID>

// Explicit regional market & HTTPS backend coordinates
QUESTIFY_MARKET = CN
QUESTIFY_API_BASE_URL = https://api.<your-approved-domain>
QUESTIFY_SESSION_REALM = cn-prod
```

> **Note:** Never point `QUESTIFY_API_BASE_URL` at the legacy mini-program server `47.103.124.64` unless explicitly approved and isolated.

## 2. Backend Prerequisites Before Enabling Session Admission (`IOS-I00-1`)

- Verify that the target backend's `GET /api/userInfo` endpoint returns a non-empty `role` field (`USER` / `MERCHANT` / `CLUB_ADMIN`).
- `AccountSessionGate` (`Core/AccountProfile.swift` & `Tests/CoreTests/I00SessionAdmissionBaselineTests.swift`) enforces fail-closed session admission when `role` is missing or empty.

## 3. Fail-Closed Endpoint Allowlist Gates

All high-risk mutations, payments, withdrawals, and unreviewed external writes remain gated behind explicit runtime allowlists or feature flags (defaulting to disabled/fail-closed):
- **Auth & SMS / OAuth (`w2-01`):** `AuthFeatureFlags` (`smsSendEnabled`, `wechatSignInEnabled`, `appleSignInEnabled`) default to `false` until legal/privacy sign-off.
- **Payments & Withdrawals (`w2-03`, `w2-05`):** Apple IAP / WeChat Pay / `/api/asset/withdraw` stay fail-closed with deterministic user-facing guidance until regional payment compliance is approved.
- **Topic Like & NPC Chat Deletion (`I05`, `I08`):** `TopicLikeHostController.likeGrantEnabled` and `NPCChatDataCoordinator` remote deletion default to `false` until `AI-DELETE` / write-grant sign-off.

## 4. Pre-Archive Verification Commands

Run the lightweight verification suite before cutting a release tag:

```bash
python3 -B tools/generate_project.py
python3 -B tools/check_scaffold.py
python3 -B tools/check_roam_private_tools.py
python3 -B tools/current_ci.py check
python3 -B -m unittest -v tools.tests.test_current_ci
```

### Batches 24–27 (`Lanes 267–312` · Three-Document 100% Full Closure)

- **Batch 24 (`Lanes 267–278`)**: Merged `origin/cloud/plan-I-20261019` (`PR #17` Reform Plan I: `W01/W09/W11` `OpsSafetyViews`, `OpsAuditTrail`, `OpsDegradedState`, `OpsServerReadouts`, `SafetyDisclosure`, `Resources/OpsSafety.xcstrings`, `tools/audit_client_ops_surfaces.py`, `test_ops_safety_contracts.py`) + `OPT-001..003` (`509` legacy clues triage & `D-01..D-10` policy gates) + `OPT-010..014` (`MP-18` unified quote, cart CAS atomicity, refund review, merchant payable ledger, coupon/points conservation) + `OPT-020..023` (`MP-17` private viewer ACL, media moderation, report/appeal/contribution & staged A/B content chain).
- **Batch 25 (`Lanes 279–290`)**: Completed `OPT-030..033` (`MP-04`/`MP-19` author draft readback, ending priority compatibility `D-04`, content/session snapshot versioning, creator revenue ledger `D-10`) + `OPT-040..043` (`MP-01..03`/`MP-06`/`MP-08`/`MP-13..15`/`MP-20..21` cross-device recovery, 80m GPS gate, `4->8->10s` lead polling backoff, 3s long-press exit, passport/badges/stamps) + `OPT-050..053` (`CLUB-MEM-01..13` 13-endpoint membership contract, 64-occurrence schedule & waitlist guard, lead location sharing `D-07`, `MP-12` pinned broadcast & cancel-refund auth receipt) + `OPT-060..062` (merchant claim material, same-window PV/UV/revenue/balance dashboard, CRM reach frequency & RBAC scope).
- **Batch 26 (`Lanes 291–302`)**: Completed `OPT-070..072` (`MP-05`/`MP-07`/`MP-09` explicit `type=1/0` like direction, image preview, stable ID keys, forward migration replay gate, critical chain `traceId` alert) + `OPT-080..082` (`MP-16` >2000-char AI safety gate, real vs estimated token usage, full NPC chat deletion & watermark `D-08`, author AI draft assist) + `OPT-090..092` & `EXT-01..11` (7-layer release signoff & 11 conditional extension guards, Flutter excluded) + `Legacy52TicketsAndMP01To21SliceParityContract` (`52/52` legacy tickets + `21/21` MP slices).
- **Batch 27 (`Lanes 303–312`)**: Closed all `81` partial + `6` missing rows across `w2-01..w2-21` (`198/198` rows -> 100% Parity / iOS Native Superset in `Wave2AllPartialAndMissingRowsClosureCoordinator`), remediated all 5 Base UI test failure clusters (`BaseUISuiteFailureRemediationCoordinator`), and synced all `docs/parity/w2-*.md` & `docs/handoff/ios-*.md` files.
