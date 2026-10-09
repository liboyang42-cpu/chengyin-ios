# CI138 coupon, Square, and frozen-cover driver candidate

Scope: three UI test files against commit `4bf6667f8c5d9d2d59a8063d7d54eaef7a338865`, tree `82e9abd1afa6180815ef7ea5ea314d6eb692e036`. Apple execution of this candidate is **NOT_RUN**. No production code, shared helper, old planning contract, profile, workflow, fixture storage, or grant changes are included.

## Artifact-grounded repairs

- UI53, job 113373676593: screenshot ABD867E2-28DC-464A-AC25-6B740C8956DC.png in artifact 11564449672 shows an adaptive one-action confirmation popover. Use the existing safe outside-popover dismissal helper; retain native Cancel on sheet presentations. Await dismissal before verifying zero issuance/no QR, then reopen and explicitly confirm. Fresh-consent/back/reopen checks remain intact.
- UI16, job 113373676296: screenshot 61522D95-3B80-4286-BCAC-28173B21686D.png in artifact 11565447906 shows the Chinese Form scrolled below Save Local with the Pinyin keyboard open. The log first finds the button, then overshoots. Replace the local one-direction full-app swipe loop with the existing keyboard-aware, frame-aware helper; keep existence/hittability checks. Do not query a missing element's identifier while constructing failure text. Exact newly saved body, Chinese status, no-alert, and suspended-recovery assertions remain intact.
- UI30, job 113373676425: screenshot 2BA6F24C-C96A-4241-92B9-10E2EB70FACD.png in artifact 11565843299 shows the unconfirmed paragraph clipped at the bottom, immediately before the request ID row. Reveal the initial request ID with at most 10 swipes and await existence before reading. Preserve original-ID byte equality, frozen-cover facts, receipt/status/no-retry checks, original submission acknowledgment, and sign-out invalidation.

## Complete-method cost proposal

These are conservative **unmeasured** complete-method allowances, not successful runtime observations. Failed partial durations are excluded. Existing costs are retained in full, without subtracting the old driver's work.

| Complete method | Previous | Additive bound | Candidate |
| --- | ---: | ---: | ---: |
| OwnedCouponCodeJourneyUITests.testOwnedListDetailCancelConfirmBackAndReopenRequireFreshConsent | 360 | 5 native-cancel resolution allowance + 5 disappearance wait + 10 geometry/query allowance | 380 |
| SquareWorkspaceFlowTests.testChineseComposerAndLocalDraftEntry | 41.034 | 3 helper calls × 11 iterations × 2 seconds = 66 | 110 |
| SquareWorkspaceFlowTests.testSuspendedRecoveryDisablesNewDraftTypingAndCompetingResume | 72.018 | 2 helper calls × 11 iterations × 2 seconds = 44 | 120 |
| ApprovedTopicFrozenCoverPublicationFlowTests.testApprovedCoverConfirmationAndUnknownPublicationRestoreOriginalManifest | 908 | 11 iterations × 2 seconds + 5 existence wait = 27 | 940 |

Round each complete method upward to the next 10 seconds. The 2-second reveal-iteration value is an explicit planning assumption, consistent with the existing planning convention, not an Apple-measured upper bound. Default Square workspace remains 19.197 seconds; Square's class total becomes 249.197 seconds. The two suspended-recovery helper calls are charged even though the originally observed failure was in the Chinese method.

The 940-second frozen-cover proposal **requires an explicit new source-bound exception**. The old 908-second exception is unchanged and does not authorize 940 seconds. No scheduling integration is activated here.

Standalone shard totals become UI16 1389.197, UI30 1287.912, UI53 1280 seconds. With the unchanged 300-second reserve, these stay below 1800 seconds individually. The planning editor must recompute the combined plan with every other candidate; this is not aggregate acceptance.

## Exact inverse and integration boundary

`tools/ci138_coupon_square_publication_driver.py` accepts only the three exact candidate postimages and reconstructs each original file byte-for-byte. The immutable candidate contract records pre/post SHA-256 values and exact inverse spans. Unknown, partial, repeated, or altered source fails closed. Shared helpers, relevant production sources, and existing planning files are bound as unchanged.

This standalone module is deliberately not imported by `run_ui_shard.py`. The planning editor must add a separately reviewed aggregation layer, validate combined postimages, and project exact prior bytes before calling the retained historical layers. Do not replace old hashes, infer timing evidence from failed runs, relax semantic assertions, or edit the existing profile/workflow to make this isolated candidate appear integrated.

Run focused checks with `python3 -m unittest tools.tests.test_ci138_coupon_square_publication_driver -v` and `python3 tools/ci138_coupon_square_publication_driver.py`. Python source contracts do not establish Swift compilation or simulator behavior.
