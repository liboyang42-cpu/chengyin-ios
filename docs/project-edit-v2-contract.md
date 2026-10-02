# Project editor: current V2 story contract

The later [rich-flow follow-on](project-edit-rich-story.md) closes the rich-block, beat-metadata and legacy-ending omissions described in this initial repair. Its source/UI changes and remaining acceptance gates are documented separately.

## Finding and bounded implementation

The current mini editor chooses `/api/topic/v2/create` or `/api/topic/v2/update` for professional city stories and professional opening/ending chapters. The audited Flutter implementation still uses legacy create/update for every professional submission. The native baseline inherited that choice while already emitting chapter blocks. This is an actual contract conflict: both legacy backend entry points explicitly reject block payloads; legacy update also rejects already-materialized flows. Legacy plain/simple requests remain supported.

The native editor now conditionally selects the version from its immutable reviewed payload. Full V2 payloads materialize legacy description/nodes into schema-1 blocks, retain stable block keys, source chapter/node IDs and client node keys, preserve route configuration/CAS versions, and validate the supported story schema. No new detail endpoint exists: readback remains `/api/topic/edit-detail`.

Two server-backed differences from the mini routing expression are intentional:

- WHITELIST removes product/publish markers from its body. Native uses the bound snapshot, freshly rechecked before dispatch, to select V2 for story content; it still sends only the original seven whitelist fields plus ID. This avoids the legacy materialized-flow rejection without relaxing the edit window
- A known stored free-explore flow stays on V2 because the backend explicitly supports V2 free-explore blocks. Only an explicit absent stored flow whose returned text/node blocks exactly match its legacy projection can remain on the legacy path. Changed or uncertain block content is never silently flattened

## Source evidence

Audit source snapshots: backend/mini baseline `fad4d6bd7e3c3e501441fe19c8de9a9cd78230fc`, followed by the parent-provided axios-only `6a130da` update; Flutter `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`. Reconstructed local snapshots do not contain complete Git metadata; the audit handoff includes SHA-256 fingerprints of the exact inspected source files.

- Mini `pages/publish/fabu/index.js:6414–6437,6524,6530–6540,6553–6558`: non-story stripping, chapter materialization, configVersion, whitelist body and conditional route
- Mini `pages/publish/utils/publish/pro-editor-story.js:240–362`: legacy materialization, stable keys, node ordering, empty audio omission, schema=1
- Mini `pages/publish/utils/publish/story-ending.js:142–217`: ending chapter shape, fallback count, readback mapping
- Flutter `lib/data/api/publish_api.dart:42–64`: legacy pro create/update and numeric create result
- Backend `ApiTopicController.java:320–327,593–595,600–671,714–814`: shared login/scope/security gates, V2 routes, bundle response and unchanged detail route
- Backend `CmsTopicServiceImpl.java:3624–3640,3990–4063,4073–4110,4167–4177,4301–4314,4776–4798,4893–4903`: both legacy rejections, owner lock, whitelist/full windows, review result, published flag, CAS and V2 compilation
- Backend `ChapterFlowCompiler.java:29–36,103–240,392–403`: version/limits, opening/ending restrictions, one reference per node, stable keys and story-game requirements
- Backend `ChapterDTO.java`, `ChapterBlockDTO.java`, `NodeDTO.java`, `TopicCreateDTO.java`, `TopicBundleSubmitResultVO.java`: field names and types
- Backend `ChapterBlockReadSupport.java:49–75,98–115`: stored-flow versus synthesized legacy readback

These references document contracts only. No backend implementation source or secrets are copied into the native repository.

## Wire/schema behavior

- V2 requires chapter `schemaVersion=1`, `required=1`, at most 200 blocks, every node referenced exactly once, in-range integer node indexes and unique valid stable keys
- Text/description/media/serialized-block limits are validated conservatively; the backend remains authoritative after node-ID materialization
- Opening is first-only and cannot recruit merchants. Ending cannot contain nodes, recruit, or also be opening; an ending collection has exactly one fallback
- Direct story-game nodes require an existing template and no place coordinates; location-required nodes retain the native coordinate checks
- Supported conditional text retains `who`, `level`, `when`; conditional text is not projected into public chapter description
- `configVersion` remains a positive source number when present and is part of snapshot equality, including when updateTime did not change. No version is fabricated
- The V2 result is a typed bundle acknowledgment with topic ID, optional audit task ID, review state, strict published Boolean, and template IDs. `PENDING`/`ESCALATED` and `published=true` can coexist in the current backend. The UI retains neutral acknowledgment copy and never claims review approval
- Server ownership/scope/edit-window/quota/content/identity checks remain unchanged. The native path needs its own exact endpoint grant; a legacy grant never authorizes V2
- Durable dispatch-start locks remain unknown across restarts, session changes and later routing/grant changes. There is no automatic retry, fabricated idempotency key, or reconciliation endpoint

## Deliberate limits

This is a bounded contract repair, not all-rich-block authoring parity or live readiness. Native supports existing text/node/image/audio editing and preserves supported hidden story semantics. Unsupported dream/mood/thought/voice/odd/reveal blocks, beat narrative metadata, unknown block fields, and legacy endings without a bound chapter fail closed at readback rather than losing content in a replacement. Dedicated rich editors, non-chapter ending conversion and the remaining broader creator fields still require separate parity work. Existing story-first/native coordinate strictness is retained.

The acknowledgment carries review semantics through typed validation but displays the existing neutral acknowledgment message. No extra publication claim or approval state is invented. No localization additions are needed.

## Verification

- 7 new offline contract/wiring checks, with explicit current source root: passed
- 14 existing project editor contract checks and 8 existing operation adapter checks, with explicit Flutter source root: passed
- Complete local ContractChecks discovery: 456 tests, 448 passed and 8 explicitly skipped for unavailable optional external evidence
- 56 current mini story/ending unit tests: passed; these execute the source mini implementation, not Swift
- 6 changed/new Swift files: supplementary Tree-sitter parse passed, zero diagnostics
- Regenerated project + scaffold checks: passed in the isolated copy
- 22 new Swift XCTest cases authored, plus updated existing fake-transport cases: **NOT_RUN**
- Swift typechecking, Apple build/XCTest/simulator/device/accessibility and real backend/provider acceptance: **NOT_RUN**

Production publishing/backend/provider grants remain off. No external mutation, commit or publication was performed by this audit.
