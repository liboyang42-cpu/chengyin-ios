# Rich chapter-flow authoring follow-on

This extends the earlier [V2 contract repair](project-edit-v2-contract.md). The initial repair remains separately reproducible; this follow-on closes its locally implementable rich-block, narrative-beat and legacy-ending omissions. It does not activate publication or claim Apple/runtime acceptance.

## Exact source-backed scope

### Rich block shapes

The existing native chapter form now authors, restores, orders, deletes and reviews every block kind accepted by the inspected `ChapterFlowCompiler`: text, node, image, audio, dream, mood, thought, voice, odd and reveal.

- Dream: 1–6 URL/caption rows, optional title; URLs up to 500 UTF-16 units, captions up to 80, title up to 20. Empty untitled local placeholders are omitted exactly as in the mini editor
- Mood: DEFAULT/BLUE/RED/YELLOW/WHITE; stored NIGHT/ARCHIVE/NEON/MOSS aliases normalize to the current values
- Thought: a named thought key matching the source format, with no duplicate grant in one chapter; existence remains a server-owned journey-rule check
- Voice: one of the five source voice identities, nonempty text up to 200 units and optional supported tag/thought condition
- Odd: integer effect level 0–3
- Reveal: nonempty text up to 500 units, optional speaker up to 20

Type-specific allowlists prevent known fields of the wrong kind from being dropped. Unknown types/fields still fail closed; no arbitrary JSON authoring or arbitrary new endpoints were introduced.

### Narrative beats

Text blocks may attach to a selected local node as brief, route, enter, outcome, deliver, unlock or revisit. Readback translates the stored nodeId to the same local node identity used by node blocks. Serialization translates both to indexes in the reordered node list, with stable block keys retained.

The pure contract validates:

- Source beat/field combinations and nonempty narrative text up to 200 UTF-16 units
- Before/after-node placement, valid node reference and source singleton slots
- Q/A IDs, unique IDs, matched pairs and at most six questions per node
- NPC IDs only on enter/outcome, positive numeric IDs and consistent NPC within one segment
- At most eight carry rows, eight facts and six revisit changes
- Conditions only on brief.carry/outcome.fact/revisit.change
- claimLater only on deliver, and a reward block whenever deliver is present
- Exact comparison operators, registered-key/system-variable shape and integer values −99…99; narrative HAS_TAG accepts tag.*, while ending/display conditions also accept thought.*.done as defined by their separate source validators

Removing a node also removes its attached narrative blocks, while preserving unrelated prose/media. Changing a narrative field clears only now-inapplicable known metadata. Rich forms use the retained ProjectEditModel and FULL-scope/session/pending-lock guards; immutable review continues to cover the final payload. Review now displays rich content, narrative node/speaker/condition metadata, opening/ending roles and ending conditions.

### Legacy ending conversion

Current mini source converts rows without a matching saved chapter into new ending chapters using their title, summary and fallback/conditions. Native now performs this conversion with deterministic local chapter/block identities so identical fresh readbacks remain equal. Empty summary is valid for an ending chapter. Matching existing chapters retain their original source IDs.

The source mini rule for journeyStory is retained: remove the old ending object only if it contains solely the legacy endings list; otherwise retain its additional epilogues/exhibits/etc for server validation and replacement. Other journeyStory sections are preserved. The backend generates the replacement ending codes and saved chapter IDs; native does not fabricate them.

## Source proof

Sources are the same reconstructed current backend/mini and Flutter snapshots as the V2 repair. Exact additional source file SHA-256 fingerprints are in the integration packet; no private implementation file is copied into the public native tree.

- `ChapterFlowCompiler.java:29–36,165–403,569–668`: all ten kinds, limits, type-specific validation and persisted shape
- `ChapterNarrativeBlocks.java:43–271,282–326,424–439`: seven segments, field allowlists, placement, uniqueness/counts/Q&A/NPC/conditions and nodeId materialization
- `AdvancedGameConfigValidator.java:75–82,170–177,1787–1832,2146–2182`: narrative condition shape and numerical bounds
- `JourneyStoryValidator.java:35–65,280–318,444–534`: ending-condition grammar and contextual server checks
- `ChapterAtmospherePreset.java:22–65`: canonical atmosphere and stored aliases
- Mini `pages/publish/utils/publish/pro-editor-story.js:240–362`: stable-key restoration and rich payload construction
- Mini `pages/publish/utils/publish/story-ending.js:142–217` and `pages/publish/fabu/index.js:6236–6258`: bound/unbound ending conversion and preserving other ending fields

## Precise remaining acceptance gates

- All publishing/backend/provider grants remain off. No real backend request or external mutation was performed
- Swift typechecking, XCTest, SwiftUI result-builder/SDK checks, simulator navigation/accessibility, screenshots and devices are **NOT_RUN** here; Linux parser/scaffold checks cannot establish those outcomes
- Server authority still checks thought existence, state-key registration, NPC/node ownership, template eligibility, content moderation, business readiness and quota. These cannot be inferred from syntactically valid draft fields
- The inspected rebuild path clearly remaps a narrative block’s outer target nodeIndex to a newly generated nodeId. Endings have an explicit old-to-new NODE_COMPLETED remap. Equivalent remapping of nested node-dependent beat conditions (NODE_COMPLETED and sys.* node references) was not established in the inspected write path. A backend contract test/readback on the approved deployment is required before enabling that capability; native preserves the source shape and never guesses future IDs
- Media controls use existing references only. This follow-on does not activate upload, download, provider credentials or new grants

## Integration and verification

New source files: `Core/ProjectEditRichStoryContract.swift`, DEBUG-only `Core/ProjectEditRichStoryFixtures.swift`, and `App/ProjectEditRichStoryForms.swift`. Existing chapter/review forms and read/write contracts are extended. Bilingual fragment: `docs/project-edit-rich-localizations.json` with 101 additions; merge these into the current app catalog without replacing unrelated entries. The existing project localization check reads the additional fragment. Regenerate the Xcode project after integration.

Local validation on the isolated follow-on:

- 7 new rich-flow offline source/wiring checks passed
- Full ContractChecks: 463 run, 455 passed, 8 optional-source checks skipped
- 19 new pure Swift test cases and 3 new synthetic XCUITest cases authored: **NOT_RUN**
- The integration owner’s separate CI48 compiled the earlier V2 implementation and executed its Core suite; that run found a stale legacy fixture in one existing coordinator test, corrected by a separate test-only patch. The rich-flow changes in this packet have not run on Apple
- Tree-sitter/scaffold results are separately recorded in the integration packet

The previous V2 packet is immutable; this packet is an exact post-V2 delta for the single integration owner.
