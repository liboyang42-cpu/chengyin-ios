> Verification correction recorded by the subsequent account/marketing/entry integration: the retained `repair-merchant-final.txt` and `repair-objects-final.txt` executions were FAIL, despite the PASS wording below. Their raw logs are unchanged. Dynamic localization-family validation was corrected and independently rerun PASS in `account-marketing-door/checks/`; see `account-marketing-door/integration.md`. The original execution must not be represented as passing.

# Native repair batch integration — 2026-10-02

Integrated into the current main working tree, preserving the completed IM additions. No remote, actual backend, device or permission action was performed. Runtime action/media/device grants remain off.

## Integrated scope

- Object collection native account route, account/epoch-bound observable host, latest-40 source contract, synthetic module fixture and richer badge wall. The account subtree now resets on session revision so pushed details cannot survive same-account relogin. Object API service remains nil in the normal host; optional bounded media remains nil.
- Nearby apply/withdraw/handle executable adapters, immutable/fresh evidence checks and durable replay locks, with nil default write grant and evidence loader. This explicitly supersedes earlier fake-only mutation coverage. No join-mode setter or receipt endpoint was invented.
- Five cooperation protected adapters via exact endpoint-scoped grants and offline-only transport marker; defaults unchanged, no production execution route. Existing scoped evidence and old unknown locks are preserved.
- Merchant engagement CRM/campaign/broadcast/export/contact/operator-invite/evidence-selection source implementation, normal merchant workspace, deployment-scoped export recovery and isolated DEBUG host. Photos/camera/Files/contact/backend actions remain separately disabled. Conservative unknown-outcome repairs applied to existing MerchantBusiness and scanner coordinators.
- Publishing and wallet approved-read adapters now bind exact captured credential/session identity before and after dispatch. Unbound requests fail closed. Identity registration read errors/malformed responses remain errors rather than being rendered as authoritative false.

## Reconciliation

Cooperation and merchant preimage hashes matched before narrow patch application. Nearby source replacements matched original packet files; the integrated checker's existing module-only glob was retained. The approved-read patch applied by hunks over the current AppSession, retaining IM additions. No old whole shared-host snapshot was copied.

Merchant supplemental checks were narrowed to its module, and its isolation-only absence assertion was replaced with a real normal-host default-off assertion. Dynamic localization key construction was corrected to runtime string concatenation before LocalizedStringKey conversion. All localization fragments were merged into current catalogs; camera-purpose text preserves scanning and adds user-selected evidence without enabling permission prompts. Xcode project was regenerated and determinism checked.

## Verification

- PASS: 343 aggregate source contract tests, 16 tooling tests, 14 parser advisory tests
- PASS: scaffold, 13 existing module check scripts and four packet gates (12 object, 12 nearby-write, 33 cooperation protected-dispatch, 18 merchant engagement assertions)
- PASS: 56 changed/new Swift files in focused Tree-sitter parse, zero recovery diagnostics. The edited MerchantHomeView has one preexisting parser recovery and is included in the unsuppressed full run instead of that zero-recovery set
- Full Tree-sitter: FAIL, 645 Swift files, 6 files with recovery, same 10 historical diagnostics. Full raw log retained; none suppressed or reclassified as a pass
- PASS: git diff whitespace check, exact fragment/catalog equality and six-shard discovery coverage
- NOT_RUN: Swift typecheck, compilation, XCTest, Xcode, simulator, Apple frameworks, accessibility rendering, physical devices, backend/provider acceptance. Python and Tree-sitter results are supplementary only

Final authored inventory: 1,758 Core test methods; 263 UI methods across 43 classes; 231 App + 261 Core Swift files; 4,549 bilingual keys. Six UI shards have 44/44/44/45/43/43 methods. See `native-repair-batch-inventory.json`, `native-repair-batch-changed-files.json` and `native-repair-batch-checks/`.

## Remaining source and integration boundaries

- Object source contains no bundled mesh/model asset or model endpoint: 2D frames/static badge previews are source-supported; real 3D is not claimed
- Platform router still must mount MerchantOperatorInvitationLandingView after approved scheme/host validation. This batch does not invent an external host or claim an incoming-link consumer is connected
- Aftercare evidence receipt remains a one-use scope/refund/store-bound local result; a receiving response form can consume it, but no automatic response/refund is submitted
- Invitation store/role preview, export-token renewal and unknown-write reconciliation have no verified source endpoints. Missing contracts remain explicit
- Runtime grants, real device behavior, persistent-journal acceptance and production activation require separate authorized validation
