# Run130 exact revision accessibility label

Base11800193/tree30cd. UI3/job112840749683 executed3 complete methods:1passed,2failed. Both owned-editor methods now find projectRemote.version.value but its actual label is `Editing version, fixture-r2`; the unchanged exact UTF8 assertion expects only the true revision `fixture-r2`. The earlier .contain/identifier change therefore did not fully resolve native LabeledContent association.

The single-line candidate explicitly assigns the value Text's accessibilityLabel from model.draft.baseRevision using Text(verbatim:). The visible localized Editing version label, true revision, LabeledContent layout, existing identifier and .contain policy remain. The original tests retain their exact UTF8 assertion, with no contains/prefix removal, hardcoded production revision or weaker locator. All other source and budgets remain unchanged.

Apple runtime validation is NOT_RUN. SwiftUI may still associate LabeledContent metadata at a higher native element; this candidate does not promise the final UIKit label will remain separate. The original full methods must validate it in the next reviewed CI batch.

Read-only fallback analysis, NOT IMPLEMENTED: if the framework still merges the child label, expose one deliberate semantic accessibility element with localized label `Editing version` and accessibilityValue equal to the exact baseRevision. Then query that single identified element and assert its value's exact UTF8 bytes, retaining a separate assertion of the localized description. That is a separate proposed semantic change, not a contains check or string-prefix normalization, and must be reviewed before implementation. Both approaches are not applied together.
