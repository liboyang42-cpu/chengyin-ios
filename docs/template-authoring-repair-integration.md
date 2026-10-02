# Exact TemplateAuthoring HTTP / own-shelf repair

## Outcome and boundaries

This package repairs the executable adapter and exact own-shelf path; it does not replace the already implemented public template hierarchy or the generic PublishModes manager. The AppSession factory is untouched and continues constructing `TemplateAuthoringAdapter()` with no transport. The newly introduced HTTP transport itself defaults `enabled` to false. No endpoint, credential, URL session, or live capability is created. No backend/network/remote action was performed.

Source authority: `app-audit/lib/data/api/template_api.dart:63–89,113–160`; actual source Templates tab in `feature/publish/my_projects_page.dart:410–450,765–774,833–841`. Compare separately `data/api/my_project_api.dart:96–115`: that generic contract correctly uses `id`. Do not replace it with the own-shelf `template_id` contract.

## Apply only this module's changes

Copy the files listed as changed/new in `template-authoring-repair-manifest.json` into corresponding host paths. Compare recorded baseline hashes first; if an owned file changed concurrently, merge its small additions instead of overwriting. The changes preserve current authoring coordinator, secure local storage and synthetic fixture behavior. `TemplateAuthoringMineView` moves out of `TemplateAuthoringDetailForms.swift` into its own file; do not leave the old declaration in the host.

Add the new Core/App Swift files and new UI test file to the existing project generator inputs, then regenerate using the host's normal generator. SwiftPM discovers new Core/CoreTests files automatically. Merge the 20 bilingual keys using the supplied additive label helper on `Resources/Localizable.xcstrings`. Existing dictionary/catalog labels remain intact. Include both source-check scripts and repair docs in the host.

The existing `TemplateAuthoringLaunchView` already calls `TemplateAuthoringMineView` with `session.templateAuthoringEditor()` and the current session revision; that route requires no signature change. The parent may add an exact own-template shelf link from Account/Publishing, using the same existing coordinator factory. Do not replace the generic project management screen, mutate its descriptors, or add new taxonomy. Do not change public Discovery hierarchy, home sections, topic shelves, or public template adoption.

## Explicit dormant injection contract

For an authorized offline harness, construct `TemplateAuthoringHTTPTransport(configuration:http:session:enabled:credentials:)`, passing an injected fake `HTTPTransport`, one captured `TemplateAuthoringSession`, and a closure returning that same current session plus its token. Passing `enabled: true` is deliberate; omit it to remain disabled. Wrap it in `TemplateAuthoringAdapter(transport:)` and pass that adapter into the existing coordinator with the same session source and secure local store. Never persist tokens in journals or labels. No factory in this package activates this injection in the shipped app.

The HTTP adapter validates account/namespace/epoch/authorization revision before request construction and after response, as well as token stability and cancellation. The host must recreate its coordinator/transport when the captured session changes. It must provide its already approved no-redirect transport and scoped configuration if live activation is separately authorized; do not activate HTTP as part of applying this source package.

`canSimulate` remains DEBUG-only. `canSubmit` also recognizes deliberately injected HTTP, so the reviewed draft/publish path is now executable in an offline HTTP harness. A real HTTP `code:200` is recorded as acknowledged, never as synthetic or as proof of public publication/approval. Terminal authoring pending records retain their lock, and an optional backward-compatible `acknowledged` field distinguishes the result on recreation. No name/title-based reconciliation and no guessed owned-edit API is introduced. The wire builder rejects existing `id` on HTTP draft/publish requests; existing local public-template adoption and source payload descriptors remain intact.

## Exact own-shelf control lifecycle

1. Read POST `/api/template/my-list` as multipart with exactly `is_quote=""`, `keyword=""`, `category_id=""`, `pageNum="1"`, `pageSize="100"`.
2. Reject duplicate/invalid IDs or over-100 rows. Prepare an immutable review from the returned own-shelf row, displaying its title, exact template ID, action and desired status. Public detail rows cannot be supplied to this API.
3. Explicit confirmation consumes the review. Re-read the exact own shelf immediately before dispatch and compare the entire immutable baseline row by ID. A changed or missing row requires a new review; no mutation is sent.
4. Persist an account/namespace-scoped own-shelf pending record in the existing secure store before the mutation. Only one pending shelf change per account/namespace is allowed, conservatively blocking both actions.
5. Delete uses only `template_id`; library status uses only `template_id` plus desired `publish_status` derived from the reviewed current `publishStatus == 1 ? 0 : 1`. No generic `id`, title target, request ID, operation receipt or guessed endpoint is sent.
6. Acknowledged HTTP writes trigger a fresh shelf read. Library success requires the exact ID with desired status. Delete requires exact ID absence in a response shorter than the 100-row cap. A full page cannot establish deletion. The displayed result says the acknowledgment and readback match, not that an unknown request was reconciled.
7. Unknown/error/5xx/malformed/session-interrupted mutation results retain the durable lock. Matching titles, IDs or later status cannot clear an unacknowledged record. A previously acknowledged request with interrupted readback may be completed by a later successful exact readback. No automatic write retries.
8. Explicit API rejection/401/not-sent releases the pending record only after durable cleanup. Storage errors keep the flow blocked; failed readback remains unresolved. Synthetic mutations display only a simulation result and never claim deletion/library publication.

No live delete/recoverability behavior was verified. The UI explicitly warns that deletion may not be reversible. The host still owns live authorization and runtime acceptance.

## Validation and limits

- 12 focused source/structure checks and 21 inherited source/structure checks executed and passed
- Supplementary Tree-sitter parse passed for 12 package Swift files; this is not a Swift compiler or typecheck
- 18 added XCTest core/fake-HTTP tests authored, NOT_RUN
- 6 added synthetic UI tests authored, NOT_RUN; use existing `--ui-template-authoring` fixture with `--template-author-shelf`
- Existing synthetic fixtures and existing authored core/UI tests preserved
- Swift compilation, Apple SDK build, simulator/device, XCTest, XCUITest, live acceptance: NOT_RUN

Before activation, run host aggregate checks after integration, Swift tests, Apple build and both language/large-text UI suites, including repeat taps, cancel, leave/reopen, failed persistence, truncated shelves, account/region/token changes and out-of-order responses. No Apple runtime or screenshot evidence is claimed by this package.
