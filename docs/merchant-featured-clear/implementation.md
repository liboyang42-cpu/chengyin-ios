# P079 clear featured content in the local store draft

The decoration screen now offers the source-supported clear-featured action and a restore action for the featured pair from the same currently loaded draft session. Clear sets exactly `featuredType = 0` and `featuredID = nil`, which the existing encoder emits as `0` and JSON `null`. It edits a copy of the current draft, preserving every other field. Restore copies only the prior featured pair and preserves other newer edits. Neither action saves or makes a request.

Both actions check current access/scope, busy and unknown-write state, absence of an active review, draft identity, loaded baseline and original current draft. A control captured before reload, discard, account change or another draft edit cannot apply stale settings. The frozen review explicitly says that saving will turn off featured content and reads only `confirmation.draft`. Existing fresh-permission/readback/baseline checks and default-disabled production save remain unchanged.

The existing empty-decoration check previously ignored the explicit clear pair, blocking review when the store contained only featured content. Its only new exception is `featuredType == 0 && featuredID == nil`. The decoded type remains optional: a missing or null type is `nil`, not zero, so a completely empty object still fails. A supplied zero type is an explicit clear signal; missing versus null ID both have the backend DTO's nil semantics, and the native clear action always emits explicit JSON null. Invalid pair and oversized-gallery checks still run before the exception. No general empty-object save is enabled.

## Verified source

The same saved construction plan SHA-256 `eb23c8aefc22954bcd6f73ef800c32b763e7f8c4e3d4c68b0a0956756fd50133`, P079 paragraphs 1787–1790, lists `clearFeatured`. The caller calls the saved file v9; its cover still says edition 8. The plan remains unchanged.

Private repository `liboyang42-cpu/chengyin`, commit `ce61c0bbace743ff835cb297ef41c89b52181636`, read only:

- `chengyinhub-xcx/pages/merchant/decor/index.js`, blob `36f0d912f63369d8d110b56757387c66ae81d307`, lines 909–911: clear uses `featuredType: 0` and `featuredId: null` through existing decoration save.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantController.java`, blob `ac739a411d2de90de83bebecf482508e1d363a2a`, lines 668–714: existing PROFILE_WRITE-scoped save and featured fields; lines 1008–1012: zero type accepts only a null ID. This work adds no activity/coupon query, new endpoint or permission.

This is the clear/restore interaction only. It does not implement a replacement featured-content browser or perform a production save. Private code is not copied into this candidate.

## Integration and checks

Base tree `5ccd7376afd3e7337f46d99985fa078db690437c`, after the tag picker. Existing `App/MerchantOperationsEditor.swift` has only small featured-control/description and frozen-review hunks; `Core/MerchantOperationsContracts.swift` has only the one empty-decoration condition change. Separate hunks preserve the independent category and NPC additions in the aggregate candidate. Do not replace either full file from this isolated postimage. Register the new App/Core-test/AppUnit files through the central project generator and merge the five unique bilingual keys. No UI methods, budgets or CI timeouts change.

Five focused Python checks and five affected-file Tree-sitter parses passed, together with exact-base replay and whitespace checks. Three Core and seven AppUnit XCTest cases are authored but unrun. Swift/Apple compile, runtime, UI/accessibility, aggregate checks and live acceptance remain deferred. No prior feature suite was repeated.
