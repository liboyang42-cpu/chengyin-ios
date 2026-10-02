# M1 / M2 / T1 reference reuse

Base: `7203de129c5daedc1836ea95e3d34d11aca735cb`. Isolated source packet only; integration owner applies the finite patch and regenerates the project. No new package, image asset, network client, grant, publication or provider configuration.

## Actual reference inspection

- exyte/Chat README demonstration, https://github.com/exyte/Chat: inspected the supplied 300 × 600 animated reference at its final frame. Reuse is limited to sender/body/time hierarchy, side-aligned bubbles and a bottom composer. No source code, avatar, sample message or dependency was copied
- Duolingo official App Store screenshot, https://apps.apple.com/us/app/duolingo-language-lessons/id570060128: inspected the supplied 157 × 340 screenshot. Reuse is limited to a top progress summary, one clearly separated current task, and a primary action. Thumbnail inspection does not establish pixel-level accessibility or contrast

## Finite changes

- M1: shared generic `ChatMessageBubble`, sender/body/time order, full text wrapping, accessibility-size gutter removal and keyboard dismissal. Existing history `scrollPosition`, prepend anchor, detail/media/poll navigation, privacy identity gates, send coordinator and pending/retry semantics are unchanged. No delivery/read ticks are inferred from a fetched message
- M2: the node NPC's Form transcript becomes a scrollable bubble conversation with a pinned question composer. AI disclosure remains above the transcript. Exact-content review remains a separate visible step. Cancel retains the draft; only a successful reply to that exact reviewed draft clears it. Regeneration still requires review; voice/microphone/grant and scene/scope cleanup remain with their existing owners. Merchant NPC uses the same presentation shell and a pinned composer, but keeps its own row identity, moderated reply, bounded retry and resource-review flows
- T1: `PlayTaskSummaryPresentation` projects only existing snapshot counts and authority. A determinate bar needs both a positive known denominator and a consistent known numerator. Otherwise it displays phase-only copy. One uniquely eligible visible node may appear as the current task; multiple playable nodes remain a choice. Completed/locked/waiting verification/unknown labels come from existing server facts. Opening the highlighted task navigates to the existing detail; it does not issue a command
- Existing `PlayPlayerAndCircleViews`, `PlayKitDecisionProgressViews`, `PlayerTaskEvidenceView`, message detail/media consumers, voice capture, and NPC/session coordinators were inspected and deliberately left unchanged. They already retain phase/unknown outcomes, known-goal progress, distinct evidence review, scope checks or permission boundaries; rewriting them would enlarge the batch without a reference-led benefit

## Shared integration boundaries

`Resources/ReferenceChatTaskLocalizations.fragment.json` contains exactly ten additive bilingual keys. Merge those keys into the current catalog, never replace the full catalog. The isolated worktree catalog is test input only, excluded from the integration patch. Preserve publisher 7203de1's localization repair and all W1/W2/C1 additions. `App/AccessibilityFixtureOptions.swift`, map/card files and shared root routing are untouched. The NPC fixture locally recognizes the same `--uitesting-max-text` convention as W1/W2/C1; it does not replace or require changes to the shared modifier. Regenerate `Questify.xcodeproj/project.pbxproj` after integrating all packets; the generated worktree project is not an integration payload.

## Authored coverage

- 10 Core tests: known counts, absent numerator/denominator, inconsistent and zero total, server completion, multiple candidates, locked/unknown nodes, merchant verification, unavailable sessions and hidden branch nodes
- 3 app-hosted tests: English/Chinese long bubble sizing at accessibility5 in both alignments, selected-locale count formatting, reduced-motion maximum-size summary construction
- 16 UI tests: NPC review cancel/reopen, failed/unknown/pending results, scope invalidation, Chinese maximum type/dark/reduced-motion/keyboard, IM keyboard/unknown/rejected/pending/pagination/detail-return/account-switch, known/unknown/completed/failed task summaries, merchant AI identity and navigation reopen
- 12 Python source contracts. These only inspect source; they do not run or typecheck Swift

Existing ShopNPCFlowTests (4), MerchantNPCFlowTests (3), PlayExperienceFlowTests (7), ModuleFlowTests and the existing Core coordinator tests remain relevant regression gates. No old fixed-count test suite was expanded in place.

## Apple acceptance gates: NOT_RUN

Linux has no Swift/Xcode/Apple SDK or simulator. Core runtime, Swift typechecking, iOS builds, app-hosted tests, XCUITest, current rendered screenshots, VoiceOver reading/focus order, exact keyboard and small-iPhone maximum-text behavior are NOT_RUN. The authored tests are not execution evidence.

Run the new suites plus existing affected suites against the exact integrated commit. Capture iPhone-small and CI-primary screenshots for English/Chinese, regular/accessibility5, light/dark and Reduce Motion on/off. Verify NPC review is scroll-reachable above its pinned composer, voice remains off without grants, background/return cannot resurrect content, IM pagination keeps the visible anchor, cancel/reopen preserves only authorized content, and pending/failed/unknown outcomes never acquire accepted or completed labels. Keep provider/device/live acceptance separate from synthetic UI evidence.
