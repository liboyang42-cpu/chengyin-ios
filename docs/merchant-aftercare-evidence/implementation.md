# Aftercare evidence attachment

## User flow

The response editor can open a focused, single-image evidence flow using the workbench's existing engagement reader, journal and export-recovery dependency. The image picker still requires the existing per-refund device gate. Nothing selects a photo on appearance.

The user selects a local image and requests an upload review. The review identifies the exact store, refund case, image and byte count. Only explicit confirmation invokes the existing upload coordinator. Successful upload leaves the response untouched. A separate **Attach to response draft and return** action, or **Replace evidence and return** when the original key was nonempty, consumes the receipt and assigns its object key. The normal aftercare response review remains separate. No opinion is submitted and no refund is issued by this flow.

Cancellation leaves the original explanation, decision and evidence key unchanged. Owned image bytes and unconsumed local receipts are retired when this flow closes or its owner becomes stale. It never deletes remote or shared images. Unknown upload results remain journal-locked; reopening cannot silently upload again.

## Existing contracts

Read-only source: `liboyang42-cpu/chengyin`, ref `ce61c0bbace743ff835cb297ef41c89b52181636`.

- `chengyinhub-xcx/pages/merchant/aftercare/detail/index.js`, blob `924cbbffa876fc060f6ef99a419e6b75d3012281`, lines 178–210: one image, refund-bound upload, local preview/removal, separate response submission.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiCommonController.java`, blob `c86ea8ba83bff12e97401c1746fb4ae1976efc06`, lines 103–132: validates current member/store/refund before upload and returns no public evidence URL.
- Existing native `MerchantEngagementService.actionRequest` already sends `refundId` in the multipart body. `MerchantEngagementCoordinator.takeEvidenceForResponse` already supports single-use refund/store/scope/authorization-bound receipt transfer. Both remain unchanged.

## Lifetime and authority

The page supplies its editor UUID, exact source snapshot, model revision, business scope/authorization and a live editor-ownership check. The flow also captures the engagement reader's scope/authorization and the raw UTF-8 draft content/key plus selected decision. Every action checks the original context. Review and attachment additionally require exact refund/access proof, selected image bytes/UUID, store and receipt context. A same-data reload changes the page revision and retires the old flow.

Upload uses the existing fresh-proof review, `canExecute`, production privacy checks, durable journal and idempotency behavior. No new authority, transport, API, dispatcher or privacy grant is introduced. Failed attach checks return before consuming any receipt. Once all checks pass, one-use receipt consumption and the nonfallible local State assignment are synchronous, with no suspension or navigation between them.

Backgrounding, observed owner/auth changes, draft changes, parent response review and disappearance retire this flow. A late selection or network completion cannot reopen it. An in-flight operation retired after reservation keeps its unresolved journal entry. Local cancellation never treats that reservation as completed.

## Scope and baseline

Composite base: `391ac97fee6983edd210c61cb4644acaffe59714`, reconstructed from published tree `6a3b946469ad8b2bf2c83ff5136b39f9cac309a1` plus the admitted redemption-filter patch `50ca5316c892a21cc3801cc9e235b8f445e671e3a0304c81ecbb357fa26fbbb1` and aftercare-decision patch `e5399d483eec46efdf643c3d8650b6c8beb83e809d0dd0b3e92714ad62b82d27`.

Four product paths only: new `App/MerchantAftercareEvidenceFlow.swift` and narrow mounts in `App/MerchantBusinessEditor.swift`, `App/MerchantBusinessViews.swift`, `App/MerchantHomeView.swift`. Exact inverse checks restore all three shared files byte-for-byte to the composite base, including note correction, aftercare decision and redemption filtering. Tests/localization stay separate. Merge the seven bilingual keys and generate the AppUnit project centrally; do not replace the shared files wholesale.

## Verification limits

- 13 focused source contracts pass, including the exact inverse and 20 unchanged dependency/configuration paths.
- 14 retained note/decision/filter behavior/localization checks pass. The prior packets' two whole-file inverse tests are intentionally not rerun against later admitted shared-file hunks; this packet's complete inverse check preserves those bytes.
- Four Swift files parse cleanly: new flow, editor, business views and hosted tests.
- MerchantHomeView retains the identical pre-existing Tree-sitter recovery on its multiline `Label` (base line 257, final line 264). No unrelated source rewrite was made. One parser subprocess crashed; one bounded retry reproduced the known diagnostic.
- 23 hosted XCTest methods are authored but NOT_RUN. No Swift/Xcode toolchain is available. Apple typechecking, SwiftUI/PhotosPicker presentation and dismissal ordering, scene transitions, accessibility and device acceptance remain NOT_RUN. In particular, source checks do not prove that presenting the nested picker leaves the outer sheet mounted on every supported OS.
- No broad aggregate or live/user-data upload was run. No remote, production, payout, grant or credential operation occurred.


## R1: owner fencing at the final dispatch boundary

R0 remains frozen. Independent review found that checking ownership before/after the asynchronous coordinator call was insufficient: its fresh proof could suspend while the response owner changed, allowing dispatch before SwiftUI observed the change.

R1 adds an App-local narrowing reader. Its dynamic scope becomes nil immediately when the exact editor, page revision, source snapshot or raw draft stops matching. The existing coordinator-minted authorization reads this narrowed scope, so the production transport’s final pre-forward validation also rejects stale ownership. The adapter checks around proof and composes the existing modern execute check without minting authority or changing Core. Post-reservation stale errors remain uncertain and preserve the journal.

Two additional hosted tests pause confirmation proof and the minted-authorization forwarding barrier, change owner/editor/raw draft without calling the view’s retirement method, and require zero upload dispatch. These tests remain authored/NOT_RUN without Apple tooling. The shared-file mounts, localization and all protected Core bytes are unchanged from R0.
