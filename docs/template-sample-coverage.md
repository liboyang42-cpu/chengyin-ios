# P036 remaining usable local sample coverage (batch26)

## Whole increment
From the25 sample browser, More local samples opens all four remaining source-backed examples that can reuse usable native local rehearsal: predict, pricePair, dice, d20. Predict and pricePair reuse TemplateCreatorRehearsalView. Picture-choice shows names only and never loads images; the limit appears both in the picker and presentation. D20 reuses TemplateD20RehearsalView. D6 uses the existing TemplateD6Rehearsal core through a small immutable snapshot adapter, because its older page requires the real mutable authoring model. Source fixed values are5 /5+4; there is no new dice algorithm. Close/reopen and the existing/reset controls are local only.

Open editor navigates to the real existing editor without enabling, mode switching or inserting an example. The seven25 choices remain unchanged. No original renderer is edited. No camera, sensor, media fetch, permission, production transport or persistence is added.

## Exact data boundary
Source DEMO fields from the pinned original catalogue replace only values currently byte-equal to native defaults in an isolated copy. Edited values, absent fields, whitespace, unknown row keys and sibling configurations remain exact. Resetting a field to default makes it eligible again; no edit history is inferred. D6/D20 preview selection changes the copied mode only. Changing into D20 uses the existing native setDiceMode initializer to add its missing mode defaults before comparison. Already-D20 missing fields are not repaired and fail closed under the old validator. Existing D20 validation can also reject unrelated invalid/unknown legacy fields: this is inherited and not repaired here.

Every model objectWillChange retires the controller snapshot before new model values arrive. Exact draft bytes, session/owner/identity, metadata/media generation, busy/review, action generations, background/departure and stamped close/swipe callbacks fence stale samples.

## Exhaustive audit
Pinned node-game-catalog contains32 primary entries and10 modifiers; all42 have individual evidence in the delivery audit.
- Seven already covered by25: qaText, qaPick, estimate, random, profile, note, typeIn.
- Four covered by26: predict, pricePair (name-only), dice, d20.
- branch: original DEMO supplies option key/next but native consumes id/nextStepId; targets in/alley are absent. Do not invent terminal nodes or silently adapt an incomplete graph.
- sort/match/classify: actual source has no DEMO entry and defaults have empty prompt/labels. Native mini preview rejects them; no invented content is seeded.
- album/hidden: existing native path loads linked images. scan can load IMAGE/OVERLAY and otherwise only describes an external scanner; excluded.
- qaShot/photoCheck/objectCard: native view is provider/frame text, not usable photo/card interaction. steps only shows goal/provider, not source progress interaction.
- shake/quiet/compass/shout depend on hardware or have intentionally disabled native sensor previews; excluded without requesting grants.
- coin/react/countdown/stopwatch have no author-local rehearsal renderer in this baseline; generic player views are not substituted.
- check is explicitly Encounter-only in source and has no preview builder; bingo is theme-level and lacks native author rehearsal.
- All10 modifiers are not primary catalogue demo entries. They are separate existing configuration/root flows, not additional source sample choices.
These exclusions are interface/content gaps, not claims of completed full Mini parity. They are reported to the root, not fixed in the feature line.

## Verification and integration
Base077273784d7fed5397f84f17b2a659723f3f3b22 plus sealed25. Only one4-line addition in App/TemplateSampleBrowserView.swift; merge that hunk, never overwrite cumulative hosts.2source leaves,2XCTest,9bilingual strings have registration fragments only. No public registry change. Private original Mini modules stay in prior evidence and are not copied into this product patch.

12Core and10App XCTest cases are authored, NOT_RUN without Swift/Xcode. Static contracts, original Mini pure functions and Tree-sitter syntax are separate checks; no Apple typecheck, compile, App UI, simulator/device, VoiceOver or real persistence validation is claimed.
