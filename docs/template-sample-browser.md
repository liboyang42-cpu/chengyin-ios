# Sample browser before configuration (P036 batch25)

## Completed local flow
The advanced authoring catalogue gains Explore local samples. Three source-aligned groups expose text question, choice question, number estimate, random card, profile, note and typing challenge. View sample makes a fresh value copy and mounts the existing TemplateCreatorRehearsalView; its existing controls/reset/local feedback are reused. Close/swipe dismissal drops the sample. Reopening starts fresh. Open editor navigates to the original family editor, with no automatic enable, mode switch or example insertion.

## Source contract
P036 previewGameFromSheet calls node-game-catalog.applyToConfig with demo:true before rendering advanced-game-preview. The verified Mini source keeps its DEMO inside a cloned hypothetical configuration and inserts example fields only when their current values still equal pristine defaults. The new native helper follows that rule against native schema defaults. Current values different from defaults, absent fields, whitespace strings, ordered row arrays, numeric strings and unknown data stay intact. A field deliberately reset to its pristine default is indistinguishable from an untouched field and receives an example in the preview copy, as in Mini. No edit-history inference is made.

The copy enables only its selected family and adjusts TYPE/PICK for the selected question preview; no change reaches the authoring model. Because the reused native renderer takes a family directly, siblings remain in the copied draft rather than being disabled for a priority-selection algorithm. This preserves the native coexistence contract. Native default shapes differ from source in some optional fields; source-derived sample field values are used only when native current/default fields match.

## Deliberate limits
This is a before-configuration sample browser for the existing non-media local rehearsal renderer. It is not the entire Mini catalogue, a new gameplay engine, or full Mini player-UI parity. Hardware/media-heavy games and unsupported topic-only entries are excluded. Existing native local match/miss feedback is retained; it is not a real outcome. Demo copy stays local; source Chinese example text remains unchanged, while navigation and boundary messages are bilingual. No sample is copied into storage or a request. No permission, sensor, upload, remote media load, network grant, publishing or registration capability is added.

## Freshness
Session/identity, exact current-draft bytes, metadata/media generations, busy/review and action generations fence open actions. Model changes retire active samples. Owner mismatch hides the value snapshot. Background/departure retire it. Old close/swipe callbacks cannot dismiss a newer sample. Damaged or absent family objects are preserved and show an unavailable message.

## Integration
Base077273784d7fed5397f84f17b2a659723f3f3b22. One additive four-line section in App/TemplateAuthoringDetailForms.swift, inside TemplateAuthoringAdvancedView; all prior lines remain unchanged. Merge this hunk, not the complete standalone after file. Existing20 legacy-question and22 attachment hunks must remain. Register2 sources,2 tests and18 bilingual strings from fragments. Public project, Package.swift, CI and catalog are untouched. Private original Mini source modules are evidence only, outside the product patch.

## Verification limits
Source checks and an original Mini pure-function harness are distinct from native execution.10 Core and10 App XCTest cases are authored but NOT_RUN without Swift/Xcode. Tree-sitter only parses syntax. Real compile, SwiftUI navigation/sheets/reset/lifecycle/VoiceOver, simulator/device and persistence are unverified.
