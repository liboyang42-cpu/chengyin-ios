# Optional-module management (P036)

## Source and gap
The sole master P036 lists openAddSheet, closeAddSheet, addModule and removeModule. Real Mini temp-index.js 1960–2019 provides reward/story/voice clearMap and add behavior; WXML 1250,1327,1375 exposes each remove action and1402–1405 the add entry. Base49 has module enable switches and single-field clears in the delegated forms, but no inspect/clear/remove/re-add optional-module workflow. This is separate from packages1–17. Confirmation is a native local destructive-edit safeguard, not claimed Mini behavior.

## Complete usable local flow
In the existing template editor, open Optional modules → choose reward/story/voice → inspect the fields to clear → cancel or confirm. A confirmed removal disables that module and clears exactly the mapped fields. Add brings the module back without restoring the removed fields. An ordinary native disable switch still retains content; adding such a disabled module preserves it. Save uses the existing owner-scoped local store. Existing validation continues to flag re-added blank reward or voice configuration until edited in their existing forms.

Reward maps couponId to0, feedbackText/medalImg/medalName to empty, and medalStyle to glow. Story maps Mini storyBeats reset to native empty storyJson plus explicit timeline marker, clears storyText, and preserves legacy storyImg with an explicit notice. Existing TemplateStoryEditor supplies the blank editing beat on opening; the manager does not fabricate a persistent beat. Voice clears audioUrl and uses native optional audioDuration=nil for Mini’s empty duration input. Source UI-only audioFileName/audioFormat/selectedCoupon names/rw flags have no native draft fields and are not invented.

Finish removal is excluded: native advanced/preference/sensor completion contracts are separate and have no safe source-equivalent module reset here. No production dependency is needed for the three optional modules. Upload, playback, camera, sensor, server writes, grants, rewards and publication are not used.

## Safety and integration
A Core snapshot is exact sorted JSON bytes, rejecting Unicode normalization drift and unrelated edits. One controller lifetime is captured to owner/session/media-generation. Draft emissions, lifecycle retirement, lock or stale review invalidate intentions; cancel/duplicate confirmation and old sheet dismissal cannot affect a newer review. A narrow model commit helper retires media reviews and old story editor generations before applying the accepted local change. Parent review-only changed() refresh can rotate actions without losing committed state.

Only App/TemplateAuthoringView.swift is shared: six helper lines and four navigation-entry lines are additive to49. Use the incremental patch and preserve root’s newer lifecycle seams. Other eight files are new; PBX/catalog registration is supplied only as fragments.

## Verification boundary
Core and App XCTest sources are authored, but NOT_RUN: this environment has neither Swift nor Xcode. Python tests are source-contract checks, not Swift execution. Node tests run the extracted original Mini methods in a minimal local state harness, not the Mini application. No simulator UI, image/audio/network or production behavior is claimed. Tests cover clear scope, retained-disabled content, cancel/confirm/re-add, stale snapshots/ABA/callbacks, owner/locks/lifecycle, media/story leases and existing local save/restore.
