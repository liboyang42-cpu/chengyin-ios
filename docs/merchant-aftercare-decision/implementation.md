# Aftercare decision-change draft protection

Switching the native aftercare picker previously retained the explanation written for the former decision. A rejection reason could therefore appear in an agreement review. The source mini-program explicitly clears that text when the decision changes, while retaining evidence.

The picker now creates a local pending decision proposal. Choosing the current option is a no-op. A different allowed option with a nonblank explanation requires an explicit discard confirmation; keeping the current opinion leaves decision, text and evidence unchanged. Confirming changes the decision and clears explanation/error only. Empty or whitespace-only explanation does not require the dialog. Evidence is never rewritten or cleared.

A pending proposal captures the editor context ID, exact refund row and snapshot, previous decision and raw explanation/evidence bytes. It can apply only while those inputs still match, and the proposed option must be in the existing server-supplied allowedDecisions. A missing snapshot, different document/customer/refund, different editor case, changed snapshot or changed raw Unicode draft invalidates it. The snapshot is a local fence, not new authority.

Context/snapshot/input changes, disappearance and review preparation retire the pending proposal. Existing parent-host account/authorization changes close the editor; its disappearance and context fence prevent a retained old dialog from changing a replacement editor. The dialog also retires on dismissal. Actual SwiftUI dismissal/event ordering remains an Apple runtime acceptance requirement.

## Source contract

Read-only verification at `liboyang42-cpu/chengyin` ref `ce61c0bbace743ff835cb297ef41c89b52181636`:

- `chengyinhub-xcx/pages/merchant/aftercare/detail/index.js`, blob `924cbbffa876fc060f6ef99a419e6b75d3012281`, `onDecisionTap`: a changed opinion clears explanation; an unchanged opinion preserves it; already-entered evidence remains. Native adds explicit confirmation to avoid silently discarding typed explanation.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantAftercareServiceImpl.java`, blob `e81d7e573cb5d92a805e4ca608d9a6d423a53147`: valid decisions remain AGREE/REJECT/EVIDENCE, reject requires explanation, evidence requires an uploaded object key, and the existing server permission/role/ownership checks remain authoritative.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantAftercareController.java`, blob `be97f358f8a2edd0d71f3d9ee564ecfedb9adaa6`: the response endpoint appends merchant opinions/evidence; it does not change approval or payout state.

The outer source receipt records verified URLs, blob hashes and exact base metadata. No private implementation was copied into native product code.

## Scope and integration

Frozen input tree: `6a3b946469ad8b2bf2c83ff5136b39f9cac309a1`. Only one product file changes: `App/MerchantBusinessEditor.swift`, for the local aftercare picker, pending-dialog lifecycle and its local proposal helper. The exact inverse assertion restores the complete original editor bytes, including the already-integrated customer-note correction behavior.

No request generation, permissions, role policy, review payload/authority, evidence string, journal, unknown outcome, save, refund or payout behavior changes. The existing note-correction dialog, title and request fields are preserved. Four bilingual keys are supplied as an independent fragment. Merge them and regenerate the central project for the new AppUnit test only in the integration owner's workspace. Frozen source and previous packets stay untouched.

## Verification

Passed: six focused Python source contracts, five retained note-correction contracts, two Swift Tree-sitter parses, exact editor inverse, whitespace, protected-file comparisons and forward/reverse exact-base replay.

Seven hosted XCTest methods are authored but unrun: blank/nonblank handling, same/unavailable option rejection, original context/draft matching, missing/different owner snapshot, different editor/document rejection, raw Unicode/evidence retention, and no request mutation. Swift/Xcode are unavailable. Apple compilation, runtime dialog ordering, hosted tests, UI/accessibility, aggregate and live acceptance are unverified. Source checks are not evidence of executing SwiftUI. No remote writes, grants, credential use or production actions occurred.
