> Current integration: the runner entry is now active, including UI52 and the separately approved UI37/UI40 increment. See `run138-ui37-ui40-readiness.md`; earlier activation-boundary wording below records the original isolated-candidate stage. Apple execution remains unperformed.

# Run138 editor readiness candidate

Base: published `4bf6667f`, tree `82e9abd1afa6180815ef7ea5ea314d6eb692e036`. Apple execution is not available in this Linux workspace.

## Inspected evidence

Actual retained pixels were inspected for each scoped failure:

- UI1 `EBEEAB56-ADC3-4E98-847E-3E33D473927C.png`: review is open; prepared-node content precedes the offscreen draft name. The image does not establish the name's AX label.
- UI1 `DB633B59-E536-4F2A-A454-407A4286FEDB.png`: whitelist editor is loaded; readback/mode content precedes Basics.
- UI33 `1DF20B43-306F-4A42-934A-6CB4D4464ED0.png`: Chinese maximum text makes the DEBUG sign-out/reopen controls very tall; fixed editor actions also consume the bottom region.
- UI35 `77FEB275-93EA-4720-A93E-D083E34A38DF.png`: the same loaded Chinese maximum-text root editor, with an additional small observation probe. The name is below the visible region. Screenshot artifact 11562206354 SHA-256 `cc0fffd0017ad7abfd91c61cc8f6cb52916fab566955302234cc5f398d78cf9f`; failure artifact 11561504901 SHA-256 `9bf88319b02075b9886c5b4f58038cfaec723482ebb09f67e93520307c9a7dc8`. The retained PNG SHA-256 is `c2dd3d17db15322d7c806b074d7022a329ded115ec8579b29541e58cc6a4df5a`. Both ZIPs were materialized from GitHub's returned file references through Library and verified. Failure JSON has `complete=false` and `records=[]`; no AX hierarchy proves successful reveal.
- UI56 `D4AF9367-4604-42FF-B85E-1945B50BB534.png`: fresh Chapter is at the top with name, chapter-role and color controls filling the viewport; story gaps follow below. PNG SHA-256 `78b8de4d66f5d2ba829dffbd7a99516096ad8f726e9627f02c34f96328f01ac8`; verified screenshot ZIP SHA-256 `2b52d2141d49e665d5ffa8ca5d1357df6b02829941ab6344f98a6ceba9a9cf16`. The log shows ten gestures toward the already reached top before the missing-gap assertion fails. Only the first gap call in `open(before:)` changes to the existing default downward search. The ten-swipe bound and all assertions stay unchanged; no new operation is introduced. UI60's storage error is outside this patch.

## Readiness and accessibility scope

One bounded reveal is added before each original failed UI1/UI33/UI35 name assertion. Review reuses the unchanged shared helper and exact string. Root-name readiness reuses the Form-gutter/actual-action-frame approach already present for ticket reveal: intersect the actual Form with the window, exclude navigation, exclude the earlier top edge of Save and Review plus 24 points, and exclude any keyboard. Both gesture endpoints stay inside this viewport. Ambiguous Form/navigation containers, unusable geometry, or exhaustion fail without a fallback tap or selector.

The root helper adds no wait or sleep and retains the shared helper's default ten-gesture bound. The DEBUG sign-out/reopen HStack alone gets the `.large` size already used by neighboring diagnostic probes. Production editor/actions, NavigationStack, maximum-text launch flags and effective `.accessibility5` assertions are unchanged.

The entire UI1 review method moves to `ProjectEditReviewReadinessFlowTests`; launch, text replacement, cancel reveal and teardown helpers are copied byte-for-byte. Its assertions, waits, Cancel and no-false-success checks remain intact. The migration keeps 736 complete methods and yields 163 classes. No journey is split.

All selected-cover/current-task/original-receipt/reopen/sign-out/probe assertions remain intact. If the review's exact StaticText cannot resolve after reveal, the test fails with AX text and the existing failure screenshot. There is no substring alternative or assumed composed-label fix.

## Validation and acceptance

The exact source inverse and independently runnable current cost plan are described in `run138-editor-readiness-planning.md`. They are local source/geometry/planning proofs, not Swift compilation or runtime UI evidence. The existing CI runner/profile/workflow and historical gates are unchanged; activation needs a reviewed entry adapter.

On an approved Apple runner, run the complete migrated UI1 review class, remaining ProjectEditFlowTests, UI33 selected-cover class, UI35 current-review class, and affected story-template classes on the exact rebuilt candidate. Capture real viewport coordinates, exact-name AX behavior, effective maximum text, and all original post-readiness business assertions. Launch-only success does not establish these journeys passing.
