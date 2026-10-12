# Template publish receipt and result navigation

This increment closes the ordinary template publish completion path: existing review → existing confirmed request → verified publish receipt → result panel → own template library. It requires the combined template 34–37 feature group. Save-draft results remain independent.

## Audited contract

Source commit: `95e499471eaa39c28f77d16125f0cc17b8c37123`.

- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiTemplateController.java`, blob `11a3ab9a9baa3ff6d09aedae860e6d29702127c5`: `/publish` returns `success(id)` only for a positive service `Long` ID.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/TemplatePublishServiceImpl.java`, blob `62cb313c28e0d49f38f4b546962e37b45825bae7`: canonical member-template persistence, status 0 / draftStatus 1 / checkStatus 0, review submission, member-template ID returned. This is not a public library projection ID or approval.
- BaseController blob `a98f981ca9a3ea2b6a1139c919adb3b893ae8d98` and AjaxResult blob `634231bafaed45e8122140a2cfaf2a73d93a9a4a` establish the code 200 + numeric data envelope.
- Mini `chengyinhub-xcx/pages/publish/temp/index.js`, blob `76e39df5c326aaf029bda8da21562072fb352553`: ordinary positive-ID publish callback opens a 2,000 ms result sheet; closing navigates to `/subpackageMember/mytemplate/mytemplate`.

No private modules are copied into this increment. The existing backend request, status checks, authorization, production transport and outcome classification are unchanged. Numeric positive integral IDs are accepted only for `/api/template/publish`; strings, booleans, objects, absent IDs and nonpositive/out-of-range values cannot create a receipt. Missing IDs retain the legacy acknowledged outcome without a success panel or guessed navigation.

## Persistence and UI

PublishReceipt is independent of SavedDraft and bound to the exact request hash, operation, owner and local identity. It occupies the existing terminal pending record, with durable readback before exposure. Old records without the optional field decode unchanged. Dual receipts or mismatched receipts are rejected. Unknown outcomes remain locked and are not reconciled through titles or guessed list rows.

The normal launch keeps TemplateAuthoringSaveFlow and adds a publish-only modifier using the same coordinator and existing library destination. Project-return callbacks are untouched and excluded. A current editable visit must be observed before a fresh receipt can show. An old terminal journal restored on entry never auto-presents. Close and the existing controllable 2-second clock use owner, identity, metadata, revision, exact draft, generation and presentation checks; background cancels, foreground starts a fresh delay, leaving retires the admission. Opening the library causes no additional mutation, journal cleanup, approval, task credit or reward.

The result text means submission for review, not public availability. The five EN/ZH keys use the dedicated CreatorPublishResult table. Both App leaves, the Core leaf, the App unit-test leaf and catalog are registered; Core tests use existing Package directory discovery.

## Verification boundary

Necessary source/registration/tree checks and a memory-only execution of pinned Mini callback bodies are recorded in the delivery evidence. Authored native tests cover strict IDs, old journal decoding, durable receipt failure, separate draft receipts, fresh result admission and retained callback isolation. Swift/Xcode are unavailable in this environment: real compilation, native Core/App tests, simulator/device UI are NOT_RUN. No live publish request is made. This feature does not enable a disabled production publishing capability or introduce any new grant.
