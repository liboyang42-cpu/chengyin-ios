# Scan response authoring (P036)

## Source-backed gap
Master P036 lists pickScanKind, pickScanArMode, onAdvancedField and clearScanModel. Real temp-index.js256–268 declares TEXT/VOICE/IMAGE/OVERLAY and NONE/PLANE/MARKER;509–515 edits scalar fields,1669–1676 changes only the selected enum, and1067–1069 clears modelUrl. WXML440–487 presents conditional fields, overlayScale20–100 step5 and the model removal action. Published5dd exposes these as a flat generic form; its delegated rehearsal displays overlayUrl but does not apply overlayScale. This feature provides one guided, local reference configuration flow and actual linked-image sizing preview.

## Flow
Enable scan → open Scan response and reveal → choose response kind → edit reply and the relevant existing reference. OVERLAY exposes the percentage slider and AR configuration enum; MARKER shows its reference, non-NONE shows modelUrl with an explicit clear action. IMAGE/OVERLAY support explicit HTTPS image load/retry; the neutral two-dimensional canvas reflects overlayScale, while IMAGE uses full width. No fake scan, camera or AR result is shown.

Changing kind or AR mode changes only its own field, exactly as source. Inactive nonempty media fields remain editable in Retained settings; an incompatible retained AR selection stays reachable until the author explicitly chooses NONE. The existing validator continues to report conflicting model/AR fields, malformed addresses, required content and limits. Nothing is silently normalized or cleared. Model clear stores the source empty string; existing serialization removes it later. xp remains the existing generic field outside the new destination.

An ordinary local save uses TemplateAuthoringModel.save and the existing owner-scoped store. Preview does not autoplay/fetch on open, mode switch, reload or address edit. Relative paths are preserved without invented service bases; only bounded HTTPS references without credentials/fragment/control bytes can be explicitly loaded. Stale requests, URL/kind edits, external draft/owner/lock changes, background and dismissal retire previews. Continuous slider/text writes and parent review-only changed() preserve the current loaded request. No claim of verified transport cancellation is made.

## Integration and boundaries
Base5dd3e53c1de104735b26d75811cb4ff46b2a340f includes packages5–15 and root hotspot/PictureChoices fixture corrections. No overlay dependency on packages16–18. One shared file changes: TemplateCreatorConfigurationView wraps the existing configurationFields call with a supported scan destination and filters only its nine managed fields. Unsupported stored shapes retain the original generic editor. Registration/localization are fragments; central files remain untouched.

Camera/scanning, true AR plane/marker tracking, voice playback and media/model upload remain outside this authoring feature. The local configuration and image preview require no new capability grant. No default-nil factory or production authorization expansion is introduced. If future runtime wiring is desired, it must use the existing approved runtime contracts separately; this delivery does not claim those capabilities.

## Verification boundary
Authored12 Core and14 App XCTest are NOT_RUN without Swift/Xcode. Source assertions and extracted original Mini event checks are separately reported. Image callbacks in App tests are simulated inputs, not native networking, rendering or AR execution. Targeted package checks preserve root’s published fixes and prior package seams. No production network or write was executed during development.
