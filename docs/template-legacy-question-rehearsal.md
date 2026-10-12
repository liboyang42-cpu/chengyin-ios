# Legacy question rehearsal (P036)

## Confirmed source and gap
Master P036 names onPvAnswer/onPvSelectChoice/pvUseHint/pvSubmitChallenge/pvPrev. Real temp-index.js _applyPvStep resets the attempt and projects the first hint; answer/choice events clear the wrong flag, hint shows the configured text, and submission advances only after the text alias or correct option matches. WXML1475–1515 exposes that complete legacy question flow. Published5dd TemplateAuthoringPreviewView shows legacy questions/options read-only; its delegated advanced.qa rehearsal uses a different answer contract and is not reused as a substitute.

The existing legacy completion form now links to an owner-scoped current-draft rehearsal. No sample/default question is inserted. Only finish-enabled text/choice methods without a recognized primary advanced game are available, using the same existing primary-game projection as legacy hints. Timer modifiers do not replace the question. Incomplete question/answer/choice configuration does not produce completion. Existing two-to-four native option letters are reused, so duplicate labels cannot select the wrong occurrence.

## Source semantics
Text aliases split on 、,，;； and ECMAScript whitespace. Each alias and the typed input uses source trim plus lowercase. Comparison is exact bytes after lowercase, not Swift canonical-equivalent String equality. BOM is whitespace; NEL/zero-width space are not. A stored nonblank answer made entirely of separators produces an empty alias list and, like Mini, accepts any nonempty input; the UI explicitly explains this source behavior instead of silently changing it. Missing/empty answer configuration cannot start.

Choice selection is single, letter-specific, and selecting the same letter does not unselect it. Wrong submissions remain on the question; new input/selection clears the error while a shown hint remains. Hints honor existing enable intent and source priority hint1 then answerReveal; hint2 alone is not exposed. Correct submission shows local-only completion and clears ephemeral answer/selection/hint as Mini’s next-step projection does. Restart resets the attempt and never restores or edits a saved field.

## Local-only safety
The controller reads the actual current draft and holds its exact snapshot with owner/session/media/generation fences. External draft emissions, equal-value ABA, locks, ownership changes, leaving or backgrounding retire the attempt. Reload is explicit and starts fresh. Parent review-only refresh retains the current typed answer but retires captured button callbacks. No mutation method is called on TemplateAuthoringModel, coordinator, storage, server or player runtime; no attachment is fetched/played. The existing local saved draft remains unchanged and can be restored into a fresh rehearsal.

## Integration and tests
Base5dd includes earlier5–15 and root fixes. Four lines are added to App/TemplateAuthoringDetailForms.swift, after legacy hint fields. All other feature files are new; packages16–19 are not dependencies. Central registration/catalog are fragments only.

14 Core and14 App XCTest are authored but NOT_RUN without Swift/Xcode. Targeted Python checks inspect source; Node invokes the actual Mini methods using a minimal isolated state harness and a harmless method-label stub. Neither is native SwiftUI, production completion, reward, network or runtime execution. No claim of those capabilities is made.
