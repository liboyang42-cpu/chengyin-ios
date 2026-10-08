# Merchant customer detail: participation and follow-up

## Delivered scope

An existing merchant business customer list row opens the existing customer detail query. Its SwiftUI detail now has customer overview, participation, tags and notes, and follow-up/outreach sections. The summary uses the existing counts and permission-gated paid amount. It makes no new request and enables no production write.

Participation groups only exact `registration-[0-9]+` keys. Each group retains all source facts; the latest status is chosen only when all group timestamps are parseable and the greatest instant is unique. Notes, corrections and campaign receipts remain independent history items. The most recent note likewise requires complete, unambiguous timestamps. Missing/invalid/tied times show an uncertainty message and retained source records, rather than silently presenting a definitive latest status. Equal-time presentation order is stable by source position. Unrelated participation keys never coalesce; duplicate history IDs remain malformed.

The document retains the exact input payload for write-review equality. Only the customer assembly changes: action-bearing timeline rows contain original note/correction/campaign records, and participation is a separate projection. Existing add/correct/hide note and add/remove tag actions remain on the guarded page; this change adds no write adapter or capability.

## Source trace

Base native commit: `37b49e2602da58a33a5d2b7fa0a679aec6059e22`.
Independent working-copy tree verified as `583a803d314ec40152063647547278177c6d3738` before edits.

Source repository: `liboyang42-cpu/chengyin`, commit `ce61c0bbace743ff835cb297ef41c89b52181636`. Source content was fetched by the blob IDs recorded in the complete tree and verified against Git blob SHA, rather than relying on page names or completion claims:

- `chengyinhub-xcx/pages/merchant/customer/detail/index.js`: `ba72ce2e8a1617803fa9ebfb31b7782a000d9e7e`, existing detail POST and access read.
- `chengyinhub-xcx/pages/merchant/customer/detail/index.wxml`: `220d3c0ea70cff5dd2e615113945b3f3e8fd35c5`, identity/paid amount/participation/tags/notes/history sections.
- `chengyinhub-xcx/pages/merchant/customer/detail/view-model.js`: `54c03e023837eb768527589a041509a0f1b5730f`, participation grouping, independent history and latest-note selection.
- `chengyinhub-xcx/utils/datetime.js`: `2163e57af3d7d8cc47b879970a2e96d3c4371ed7`, Shanghai civil strings and explicit-offset ISO instants.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantCrmController.java`: `61ab0645b60800f9b8edf7f61fd5690b3b7c33f2`, POST `/api/merchant/crm/customers/{customerMemberId}/detail`.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantCrmAppServiceImpl.java`: `e83de32e964301fb2c5395fdbeb012a578c12e58`, CRM_READ/owned-customer validation, sensitive amount stripping and at most 50 returned recent timeline records.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/domain/vo/MerchantCrmTimelineItemVO.java`: `d0efc410ae73e12fd9794e43d1299edbcc9e0be6`, raw key/type/title/description/Date and note identifiers.
- `chengyinhub-system/src/main/resources/mapper/business/MerchantCrmAppMapper.xml`: `1b95e06b64fffae2f487b1c548480271b81ea175`, REFUNDED only from `payment_status = 4`; ARRIVED from `verification_status = 1` otherwise REGISTERED. Its timestamp is verification time or registration creation time, not refund completion/bank-arrival time. The UI labels it as record time and states this limit for refund records.

This is a bounded W06 merchant customer/registration readback increment; it does not complete W06 transaction fulfillment, W07 ledger or W17 reward flows.

## Time, privacy and lifecycle

Ordinary record dates parse to absolute instants and render in the current phone timezone, updating when that timezone changes. Strict Shanghai `yyyy-MM-dd HH:mm:ss` and ISO seconds with explicit offset (optional 1–3 fraction digits) are supported. Unsupported source forms remain unknown, never device-zone guesses. No refund/payment deadline, completion timestamp or future date is invented.

The customer component requires CRM read permission. Paid amount additionally requires CRM sensitive-read permission even if an erroneous response included it. Null and zero remain distinct. No phone reveal, contact transmission, export, persistent cache, clipboard or logging is added. The component is rendered only from the page's current snapshot, with existing account/authorization/disappearance invalidation and late-read fences.

## Validation and integration boundaries

- Authored core XCTest covers registration-only grouping, absolute-time sorting, unknown and tied timestamps, retained campaign/correction history, unchanged payload/action baseline, wrong-customer rejection, exact existing API, timezone/day/DST behavior and non-inference of refund status.
- Authored app-hosted XCTest covers current permission gates, null/zero amounts, account/logout/authorization drift, dismissal/cancellation, older read versus refresh, and permission failure after a prior detail.
- Python contract checks and Tree-sitter parsing are supplementary source checks, not Swift execution or visual verification. The private source comparison is explicit `NOT_RUN` unless `CHENGYIN_CUSTOMER_DETAIL_EVIDENCE` points at the separately verified evidence directory.
- The existing merchant Home whole-file guard adds one exact inverse adapter for this customer-only hunk. Original settlement, aftercare and Home inverses, hashes and assertions remain in place.
- New strings are supplied only as `Resources/MerchantCustomerDetailLocalizations.fragment.json`. Integrator must merge the fragment and regenerate project membership before Apple builds; this candidate does not edit the main string catalog, project file, AppSession, composition root or CI.
- Swift/Xcode, simulator, VoiceOver and visual checks have not run in this cloud workspace. No live account/customer data or real payment/redemption/reward action was used. All tests are synthetic. No push or deployment.
