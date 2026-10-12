# P080: complete NPC text-field editing flow

The actual Mini ai-npc page opens name, greeting, persona and knowledge in one field editor. Their limits are 32/60/500/2000 UTF-16 units; persona and knowledge use multiline input. Input is temporary. Close preserves changed text until Keep editing or Discard. Changed Apply uses the source JavaScript trim whitespace; unchanged historical values are an explicit no-op. Other fields, avatar and audit metadata are preserved byte-for-byte.

The ordinary native merchant character page now opens these four editors through its existing characterField helper. Apply is explicitly labeled as local draft preparation. It calls the existing document edit once and retains the existing whole-character review/save gates. Mini persists an existing profile or creates a first profile on saveField; this package does not introduce direct saves or claim persistence. Missing name/avatar and all whole-draft requirements remain enforced by the original review flow.

Sessions bind to current authenticated owner scope, revision, draft identity, full original/baseline text and metadata. Reload, sibling edit, review, account changes and lifecycle transitions invalidate old buffers. Presentation generation and route identity reject old Open/Close/dismiss callbacks. Dirty interactive dismissal is disabled; Cancel asks about this field only.

Structured knowledge drafts, greeting preview, preset/avatar/media/voice/map flows remain unchanged. No API, network operation, permission, persistence or production configuration is added. The feature reuses the existing offline operations fixture; test actions never submit business saves.

Source: liboyang42-cpu/chengyin commit 95e499471eaa39c28f77d16125f0cc17b8c37123, chengyinhub-xcx/pages/merchant/decor/ai-npc/index.js (d0088bf4d71158bc2b5cc19e7b4e1db32c4fc0b3) and index.wxml (1145bb5bf8dab349bb2208d103e10ce38d3f8222). Private source is excluded from this patch.

Native Swift compilation, XCTest, simulator/device and accessibility checks are NOT_RUN here because Swift/Xcode are unavailable. Source/contract and tree proofs are supplementary and are not native acceptance.
