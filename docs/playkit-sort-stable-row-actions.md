# Stable sort row actions

Base: public iOS HEAD `3971086a1feb3dc765a44153542c1d52eb9e4775`, verified with `git ls-remote origin HEAD` on 2026-11-08. Work uses a clean detached worktree, separate from both the previous QA-image candidate and the parent's uncommitted integration tree. No AGENTS.md or sorting/matching owner registry was present in the checked-out repository. Existing reasoning-result work and its tests were inspected before this repair.

## Confirmed gap and repair

`PlayKitReasoningForm` originally captured the enumerated list index in both sort buttons and VoiceOver row actions. With `[a, b, c]`, B's controls capture index 1. If B moves up first, the current order is `[b, a, c]`; invoking B's retained down action using index 1 would move A. Likewise, an old up action for B can move A after B reaches the first position.

The controls now capture B's existing item ID. `PlayKitSortMovement` resolves that ID in the current order and moves the same item one adjacent position. Missing/ambiguous identities and out-of-bounds moves are refused. The existing `enabled` guard still applies; successful movement still sets the existing dirty state and hides the old retry feedback through `onDirty`. Buttons now include the item label in their accessibility label so repeated up/down controls have context. No new localization keys or visual style were introduced.

The helper changes only the player's local ordering. It neither reads a solution nor determines pass/fail, attempts, completion, score, or rewards. Sort continues to submit `SUBMIT_SORT` with `order` containing the original public item IDs, through the original input validator, frozen review, and coordinator. No new `itemId` wire property is added.

## Matching and image boundary

The current matching form already removes the old pairing when a right-side ID is reassigned, resets placement when left/right identities change, and validates a complete one-to-one `pairs` payload. That behavior and the existing `SUBMIT_MATCH` action are unchanged. The existing scope cleanup and background draft-preservation policy are also unchanged; this repair does not add persistent drafts or change unknown-command recovery.

The inspected public projection reads `items[].id/label` for sort and `left/right[].id/label` for match. There is no verified image projection available to this work. No `imageUrl`, `oid`, correctness field, image-kind alias, image loader, or author configuration is inferred. This fixes one existing shared row interaction that future verified image rows can reuse; it does not claim to implement or accept the full image sorting/matching journey. No overlap with per-slot work, puzzle prompts, QA image choices, or backend G0–G6 is included.

## Verification and integration

Four new XCTest methods cover retained actions after another move, edge/removed target rejection, malformed movement, and unchanged original sort payload/terminal gates. They use existing IDs and synthetic public labels, with no network or backend result generation. Existing sort/match contract tests and reasoning feedback/lifetime checks remain in scope.

The new Core source needs additive Xcode app-source registration by the integration owner. The new Core test is discovered by the existing Swift package path; Apple test-target registration is also the integration owner's step. No PBX, AppSession, composition, runtime, backend, production configuration, CI or shared localization file was changed. No push or CI trigger is authorized or performed.

Swift/Xcode are absent in this Linux executor. XCTest, Swift typechecking, iOS build, VoiceOver behavior, rendered UI, rapid-tap scheduling and image/production acceptance remain NOT RUN. The source-level regression demonstrates the positional failure mechanism; it does not establish its frequency on a device. Executed supplementary checks and exact artifact hashes are recorded in the delivery manifest.
