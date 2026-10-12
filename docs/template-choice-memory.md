# Automatic choice memory (P036)

The master P036 `toggleOptionMemo` and real Mini JS 922–935, WXML 412 and725 define this feature for QA PICK options and profile pick-question options. Earlier typed effects editing accepts manual op/value input; it does not implement this automatic memory lifecycle.

The existing option detail editor now exposes Remember this choice, displays every currently attached memory tag, and lets the author turn it off or enable it again. Turning on removes existing ADD_TAG effects whose string value starts with `tag.m_`, then appends exactly one `{var:"",op:"ADD_TAG",value:"tag.m_......"}` effect. Turning off removes only those memory effects. Other effects keep their original order and data. Opening never normalizes duplicate tags or rewrites the option.

Generated suffixes contain six lowercase alphanumeric characters with an alphabetic first character, matching the Mini generator's intended shape. The native generator uses system randomness with cross-draft reserved-tag checks rather than JavaScript Math.random. A full16 unrelated-effect list cannot enable memory; nothing is evicted. Existing over-cap lists containing memory can still turn that memory off. These safeguards honor the existing native effects contract. Unsupported historical shapes retain generic editing.

No new wire fields, runtime state or storage format. Option labels, answers, identifiers, unknown supported fields and all other families survive. The field wrapper adds memory only at QA option and profile option paths; other configuration forms are untouched. Reusing the existing save/restore flow persists the effect configuration, without applying a tag to any player or promising completion/rewards. Editing the generic effect list still remains available.

Captured parent-scope fingerprints exclude only the target effects array, so own memory edits remain usable while an option rename/reorder cannot retarget retained actions. The wrapper identity recreates the controller when parent scope changes. Session/identity/media/pending/lifecycle checks plus publication and metadata generations reject old actions, including same-value ABA. No permission or sensor grant is added.

Register new App/Core files and App XCTest using the registration fragment, and merge8 localized keys. No prior-package dependency. Apply this package additively to cumulative Creator UI.

Core and App XCTest are authored but NOT_RUN without Swift/Xcode. Python source checks and Node original Mini event checks are supporting evidence only. Native UI, local-save gestures, full Mini and player-effect/backend execution are not claimed as run.
