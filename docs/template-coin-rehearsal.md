# P036 creator-local coin-flip rehearsal (batch 27)

## Complete local flow
The coin configuration page now opens an immutable current-configuration rehearsal. The additional-samples browser offers the same component in source-example mode. Both sides and the source kicker are readable before interaction. HEADS is selected initially, matching the actual Mini preview builder. Authors explicitly choose HEADS or TAILS, show the matching label/action, try again with the same deterministic face, reset to an empty HEADS state, close/back and reopen. No animation timer, accelerometer, haptic, image, player session, payment, coin issuance, completion or reward is introduced.

The source live component receives a server-selected face and settles its corresponding label/action. Its real onFlip is idempotent once settled. Our again/reset controls are author-only inspection, not retries of a real player transaction. TAILS selection is an explicit local author extension; it does not claim that Mini randomly chooses this preview result. The source sample action strings are retained verbatim; clear boundary text states they create no payment or treat commitment.

## Configuration and source semantics
Current-configuration mode reads the raw draft without enabling or inserting anything. Source-example mode copies the coin family, enables only the copy and fills source DEMO kicker/heads/tails only when each whole field still equals its native pristine default. Edited nested data, missing fields, whitespace, unknown fields and sibling families remain unchanged. Reset-to-default is eligible like Mini; no edit history is inferred.

Kicker and each side use the existing exact ECMAScript sourceTrim helper. Empty kicker/labels fall back to the source strings; empty actions remain empty and receive a UI explanation rather than invented result copy. Missing side objects stay absent in the copied draft and display fallbacks only. Malformed objects or non-string text fail closed instead of using JavaScript object/number string coercion. No source or native authoring validator is modified. The preview deliberately works before publish validation and can inspect a disabled game.

## Stale actions and privacy
Controller snapshots capture owner/session/identity, exact draft bytes, metadata/media generations and mode. Busy/review and changed owner prevent reading. Every model objectWillChange retires state before the new value arrives; refresh explicitly captures a new snapshot. Background/leave retire state; re-entry starts fresh. Selection, show, repeat, reset and close have stamped callbacks. Old bindings cannot read or mutate reloaded state; old close callbacks cannot dismiss a new incarnation.

## Evidence and scope
Pinned source commit95e499471eaa39c28f77d16125f0cc17b8c37123. Catalogue blob22ca448703f05b9c846129f02614c74b29ad16a6, preview blob40156f8c3f7d12d69d0b301fa397d5a8f967ec2a, component JS blob5028680867954d92a5108666b27eeccdaed6628d and WXML blobe1b483f3438484c379beb15a378cb524fa731c90. Original private files stay outside the product patch. The source JS component harness uses explicit inactive mocks and never starts hardware or requests a live flip.

Only coin is added. Timers, other unimplemented categories and the other26 audit gaps remain incomplete. Existing25/26 choices and old configuration/renderers remain intact. Base077273784d7fed5397f84f17b2a659723f3f3b22 plus sealed25/26. Two precise additive host hunks, no public registration edits. Register2 source leaves,2 XCTest and14 bilingual UI keys using fragments.

## Verification limits
12 Core and12 App XCTest cases are authored, NOT_RUN without Swift/Xcode. Static checks, original Mini pure-function/component-reference tests and Tree-sitter parsing are not Swift typechecking, Apple SDK compilation, App UI, navigation/dismissal, simulator/device, VoiceOver or real persistence execution.
