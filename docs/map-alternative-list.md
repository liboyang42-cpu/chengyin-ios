# Supplied-pin alternative list (MV09)

The online Search and Roam map renderer now offers a place-list control before the Map accessibility subtree. It lists every unambiguous pin already supplied by its caller, including offscreen pins. It does not query a provider, load other business data, infer hidden points or ask for location access.

Rows preserve the caller's business identity, ordering, full title and hint. Same-ID duplicates and empty IDs are omitted rather than merged or arbitrarily selected. Coincident coordinates and equal titles never merge business identities in this list. List and map share the parent's selected ID. Selected rows expose both visible text and the selected accessibility trait. Selection does not move the camera; the existing explicit focus-selected action remains separate.

The list can be collapsed and reopened without changing selection. Its show/hide control requires a one-shot request from the current visible lifetime. Before appearance and after disappearance it cannot issue requests. Returning creates a new lifetime: retained pre-departure callbacks remain invalid, while fresh show/hide actions work. An empty current snapshot shows an empty message rather than old rows. A current snapshot replaces titles and other pin metadata immediately. Selection uses a one-shot local revision gate. Close, disappearance, input refresh, same-ID replacement, selected-ID changes, interaction-scope changes and read-only transitions invalidate old callbacks. Read-only previews retain readable rows with disabled selection and an explanatory accessibility hint.

English and Simplified Chinese strings are provided. Titles and supporting copy wrap with Dynamic Type, with no imposed line count. Buttons have at least 44-point targets and selected state is not color-only. No new animation is introduced.

## Verification boundaries

- Existing Core/UI methods remain intact; 8 Core and 3 UI methods were authored.
- New UI tests use the actual alternative-list component in a synthetic offline host. A labeled synthetic point event witnesses parent-to-list selection; list-to-parent selection is also asserted. The fixture never mounts MapKit or fetches tiles.
- Tests cover long bilingual titles at accessibility5, selection/clear, duplicates, current-title refresh, pin removal, close/reopen, empty results, read-only rows and an actual synthetic navigation departure/return. Dedicated Core negative controls reject retained toggle requests while hidden and after return, then accept a fresh request.
- These are authored tests, not executed Swift or XCUITest results. Tree-sitter and Python source-contract checks are supplementary source evidence only.
- Apple compilation, real MapKit point-to-list synchronization, VoiceOver order and gestures, device layout/contrast/Reduce Motion, provider behavior and performance remain unverified.
- The whole-method timing fragment is an unmeasured scheduling allowance, not a measured duration. The integrator must rebind current source hashes and rerun the actual all-method partition without shortening existing methods or discarding older costs.

## Current native integration and scheduling

The reviewed R2 source is integrated on native commit `9581ea7f6248eec531f80f74fb845bfdb6c69e67` (tree `ed4c525e52ee002634d321b3519a1b233bc071fc`). The existing localization catalog is preserved with nine added bilingual keys.

The three new complete UI methods and all their helpers move unchanged into the direct `SearchMapAlternativeListFlowTests: XCTestCase` class. The published `SearchMapFlowTests.swift` remains byte-identical. Their full unmeasured allowances remain 360, 240, and 210 seconds, respectively. All 661 published UI methods, their identities and complete costs remain unchanged. All 647 run117 observations retain their original source/run identities.

The central source-bound plan discovers 664 methods in 108 classes. Deterministic 39-shard planning has a maximum forecast of 1738.315 seconds including the entire 300-second startup reserve, leaving 61.685 seconds against the 1800-second deadline. The dedicated map class costs 810 seconds; the original SearchMap class remains 670.135 seconds. At 38 shards the same split forecasts 1780.047 seconds, so the extra shard provides a planned margin beyond the startup reserve without reducing any method allowance.

Historical planning tests reconstruct the exact published profile and source/workflow inventory before checking earlier evidence. Current-plan tests independently check complete source inventory, full-method/helper preservation, old-cost equality, unchanged observations, source hashes, deterministic partitioning and corruption negative controls. These forecasts are scheduling estimates, not Apple execution results.

The current integration also preserves the separately published run119 actor-initialization repair, its default/injected-model AppUnit tests and all prior Debug guards. The project is regenerated from the complete union source. No source-only check establishes that the Apple compile failure is resolved at runtime.
