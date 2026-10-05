# Existing professional ticket editor: theme-date sync

Source-connected authoring slice, not a new publisher or a production activation.

## Source evidence

Pinned private source: `liboyang42-cpu/chengyin@11be8cb2f09073496f3a7d5130d558da60cf5439`.

- `chengyinhub-xcx/pages/publish/fabu/step3.wxml:268–290` exposes “与主题日期保持一致” only in the free-exploration ticket branch, hiding manual date fields while on. `index.wxml:393` includes this existing ticket form.
- `index.js:4998–5007` toggles the setting and copies theme dates when enabled; `4494–4503` updates synced tickets after date changes; `4933–4939` saves resolved dates and the flag; `6452–6463` spreads the ticket and resolves/normalizes start/end at submission.
- `pages/publish/utils/publish/publish-datetime.js:normalizeDateTime` supplies midnight for a date-only start and 23:59:59 for a date-only end; explicit wall-clock times remain unchanged. No device-timezone conversion is introduced.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/domain/OmsTicket.java:123–124` declares Boolean `syncWithTheme` and explicitly says storage/readback only, with server sync logic not connected. `OmsTicketMapper.xml:35`, insert/update bindings, and replacement assignment at line 235 persist it. Start/end timestamps are already supported backend fields.

Captures and independently rehashed Git-blob receipts remain in the private review packet; proprietary source is not copied into this public repository.

## Behavior and boundaries

The existing ProjectEditTicketView now exposes the switch for free-exploration tickets. Effective dates are shared by UI, validation, immutable review and existing payload construction. Changing theme dates updates effective validity while on. Turning off freezes the displayed dates into manual fields; repeated off leaves manual values alone. City tickets never apply date sync, including when imported metadata contains a true flag. The stored flag is retained rather than silently cleared.

The existing localMetadata envelope holds the setting, so older drafts need no new required decoding fields. Missing, null and Boolean settings are editable; unsupported types remain unchanged and lock the switch. Unrelated/unknown metadata remains intact in local drafts. The one existing source-backed `syncWithTheme` field is carried into ticket payloads; the unknown-sibling wire allowlist is not widened. Missing flags stay missing, null stays null until explicitly toggled, and matching dates never imply sync. Authoritative edit-detail decoding supplies the actual server flag; no inferred preference or fabricated readback is used.

Native strict date validation continues rejecting impossible dates and timezone-suffixed strings rather than copying mini's permissive prefix regex. This slice matches supported wall-clock normalization, not every malformed-input behavior. Unknown imported raw sync values are retained without asserting that the Boolean backend would accept malformed legacy data on a real write.

All scope/owner/session/epoch, local restore, revision/CAS, frozen review, explicit dispatch, unknown-outcome and reconciliation boundaries remain unchanged. WHITELIST returns before ticket fields. No new endpoint, capability, grant, login change, RBAC expansion, media upload, purchase eligibility, automatic server job, production write, push or activation is introduced. Backend storage of the flag does not mean the server will update tickets when dates change elsewhere.

## Verification limits

The review packet records exact Python structural/contract checks and supplementary Swift parser results. Four Core XCTest methods, two AppUnit methods and one synthetic XCUITest cover effective dates, theme changes, unsync/manual preservation, old/unknown metadata, authoritative decoding, readback flag retention, review invalidation/cancel, local restore, WHITELIST, stale epoch, removed row and city boundaries.

Apple compiler/typechecking, Swift XCTest/AppUnit/XCUITest execution, simulator/device rendering, accessibility, live API/database writes/readback and production deployment were NOT RUN in this Linux workspace. Authored tests and source inspection are not execution evidence. Existing Apple CI is still required.
