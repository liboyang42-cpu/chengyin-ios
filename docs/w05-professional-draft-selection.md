# W05 saved merchant draft to professional node

## Scope

This increment adds the owner-only draft chooser to the existing professional node fields: an existing chapter node, a temporary first-node candidate, and a pending-material node. It assigns only the existing `ProjectEditNode.templateID`. The node title, content, coordinates, media and unknown metadata are unchanged. It uses the existing local envelope and V2 save path. It does not create another publisher, draft store or content schema.

The companion backend producer is required. AppSession composition, the dedicated bilingual `ProjectMerchantDraft.xcstrings` catalog installation and generated Xcode project are integration proposals outside this narrow patch; this isolated patch is not a complete App configuration. Both exact read grants are empty by default. No deployment flag, production account or provider has been enabled.

## Actual source contract

The backend creates the original W05 CMS draft through `MerchantAuthoringRecordService.confirm`. The saved creation receipt is historical. The generic `/api/template/my-list` can return owner drafts, but carries no W05 source linkage; publishing's `.templates` request sets `is_quote=1` and instead lists approved, published references. Neither is used here.

The companion seven-file owner-read producer runs only with the existing authoring and facts-confirmation profiles and its independent default-false switch. It reuses the existing unique current merchant-owner check, source/candidate integrity checks, current CMS draft row and separate W18 marker/sidecar rejection. It creates no confirmation, binding, approval or publication.

- `POST /api/merchant/authoring/draft-selection/list`: exact `{beforeSourceId: null | positive}`. Descending source-ID keyset, 20 rows plus one lookahead. No offset or total/snapshot claim. Unavailable source rows count toward the cursor, so an unavailable page cannot hide later pages. New inserts require Refresh. Owner, source or merchant ambiguity fails closed. The existing table lacks an owner composite index: bounded output does not establish bounded database scan cost.
- `POST /api/merchant/authoring/draft-selection/resolve`: exact existing four-field W05 source reference, `memberTemplateId`, and observed `templateContentHash`. Rechecks the same current owner/source/unchanged draft and returns a current-at-read projection. This is not usage or publication authority.
- Both responses explicitly retain historical merchant-facts freshness and false approval/usage/publication proof. READY rows have the real CMS ID, source, current content hash and title. UNAVAILABLE rows expose only the owner's historical IDs and their unavailable state.

The final save/review/prepare/publish paths remain responsible for current ownership, source closure, merchant-facts confirmation and publication checks. A client `resolve` response is never sufficient write authorization and is not serialized as a grant.

## Native fences

The two new features are `merchantDraftSelectionList` and `merchantDraftSelectionResolve`. Both exact paths must be granted before the chooser opens or dispatches. The existing outer authenticated composition route parser rejects query parameters, unknown fields, wrong content types/methods, invalid hashes and adjacent routes. Publishing/project grants cannot substitute.

A presentation freezes the complete editor lease, raw JSON bytes, complete session, reader identity, node identity and monotonic draft/candidate revisions. Refresh retires old page/selection identity. Pages refuse overlap, duplicate template IDs and merchant replacement. Apply synchronously claims the selection before its async resolve. A second click cannot dispatch again. Cancel, old dismissal, account/epoch/viewer/configuration replacement, changed node bytes, and edit-then-restore ABA retire the old action. A failed or stale resolve cannot change the node. Close and reopen starts with no retained page or proof.

The three new revision counters are in-memory only. They do not change persisted schemas, autosave, pending recovery, media journals, or previous assertions. Copy-for-mode retains the optional reader, whose complete session checks still apply.

## Separate prior native14 dependency

The earlier `w05-bound-node-source-picker-native.patch` is a distinct 14-path increment based on tree `7a3fdb77e98640022940798ecf9b69f3fe5976cc`, result `8ce2650e81d31d517d789efe69701924ca0ee161`, SHA256 `d310460a7497f317b08c54b0d7db00f8de2da9b96fc3ebf52f85a891689e3cd7`. It lists historical facts confirmations for W05 nodes already bound to a topic. It is not present in the published e8eaf/f463 baseline. Its direct replay on f463 fails at AppSession; it must be rebased as a union, including its route/feature/catalog hunks. This increment neither applies nor silently depends on those new native14 types. Completion of the later bound-node confirmation/review UI still requires that separately reviewed integration.

## Verification limits

The two native HTTP fixtures are byte copies of the companion producer's real local H2/MockMvc responses, not invented samples. The new Core and AppUnit tests cover exact wire parsing, list/empty/unavailable pages, duplicate/out-of-order pages, rights separation, current resolve, unauthorized/changed sources, cancellation, repeated taps, lifecycle/ABA fences, and the existing local save/restore path.

No Swift compiler or Apple SDK is available in this task. XCTest, Swift type checking, app build, simulator flows, accessibility and on-device testing remain NOT RUN. Supplementary Tree-sitter and local Python contract checks are not App tests. Real MySQL, production schema/data, deployment, provider and final business acceptance are separate gates.
