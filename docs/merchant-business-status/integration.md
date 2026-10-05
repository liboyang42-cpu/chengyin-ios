# Merchant business status: source-backed dormant native slice

The existing mini decor home switch is bound to `toggleBusiness`. The handler calls
`POST /api/merchant/business-status/update` with the single form field
`business_status=0|1`. The current controller exposes the dedicated
`POST /api/merchant/business-status` read, requires BASIC_READ for reading and
PROFILE_WRITE for writing, and derives the merchant from authenticated access.
Its contract explicitly calls this display-only. It changes neither approval nor
account-disabled status, nor booking, payment, registration, or access eligibility.
See `source-receipts.json` for exact source refs and blobs. Relevant source ranges:
mini decor JS 740–764; controller 304–347; decor WXML home business switch.

## Native behavior

- Ordinary Merchant → Operations → Business status entry. Conservative editor
  visibility requires active access with both BASIC_READ and PROFILE_WRITE.
- Strict typed Open/Closed decoding. Missing/null/string/Boolean/unknown wire values
  do not become a valid status. A null database value is defaulted by the server,
  not guessed by the client.
- Owner-bound local draft. Merchant ID is a local fence, never sent in the form.
  User selection is local; existing frozen review and confirmation are retained.
- Exact dormant URL-encoded POST body with only `business_status`. Existing
  deployment/account/path approval, fresh authority and baseline read, session
  revision checks, durable storefront pending journal, no-retry unknown handling
  and explicit rejection handling are reused.
- On acknowledgment, stale draft/baseline are cleared. A dedicated owner-scoped
  status read supplies the authoritative displayed value, which may differ from
  the requested value. Readback failure or owner mismatch remains distinct from
  unknown write outcome and never silently resends. Reload is read-only.
- Session/role revision changes, late prior reads, stale confirmations and view
  dismissal retain the existing generation fences. Status and profile-hours
  fixtures are independent.

## Media audit boundary

Logo/cover/gallery selection, upload review, local Use, gallery add/remove and
save review already exist through MerchantRetainedImageDocumentOwner and
RetainedImageSelectionView. Production remains blocked by nativeSelectionEnabled
false, uploader enabled false, and an empty approved-origin set. File bounds,
metadata-stripping sanitizer, source/owner/privacy checks and durable ambiguous
upload locks remain unchanged. Mini logo 1:1 / cover 5:3 and gallery 16:9 crop
flows were separately identified; this status patch does not claim crop parity.

## Verification limits

Python tooling/contracts and supplementary Tree-sitter parsing are structural
checks, not Swift compilation or app execution. All authored Core/App UI XCTest,
Swift type checking, Xcode builds, simulator/device, visual/accessibility and live
service acceptance are NOT_RUN here. No live write, upload, new production grant,
provider activation, push or deployment was performed.
