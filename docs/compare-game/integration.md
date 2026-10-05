# Native timeline comparison

This source-backed slice adds the backend `compare` family to native player and creator flows. It does not enable production gameplay or establish Apple/device acceptance.

## Exact contract

- `SUBMIT_COMPARE` uses the existing advanced-action endpoint and the single payload field `marked`, an array of opaque IDs from either timeline
- Order does not affect server correctness; duplicate or unknown IDs are rejected. An empty selection is a valid attempt
- Both timelines keep server/configuration order. IDs, time labels and entry text are neither guessed, shuffled nor lexically sorted
- The server compares the complete marked set against its private answer. Only a whole-answer receipt is rendered; no per-entry correctness or answer is reconstructed
- `finished` ends the comparison even if capped attempts were exhausted without passing. `readyForBase`, XP and pass status remain server-owned
- Runtime projections use `maxAttempts = 0` for uncapped attempts and omit `remainingAttempts`; authoring instead omits/nulls the cap, or supplies an integer 1–10. Authoring an explicit zero is invalid
- Creator constraints: required prompt ≤200 UTF-16 units; each side has a required label ≤20 and 2–20 entries; entry ID matches 1–32 ASCII letters/digits/underscore/hyphen and is unique across both sides; required time ≤16 and text ≤200; answer is a nonempty unique subset of IDs; XP 0–1000; nonempty effects are rejected

## Native flow

Comparison appears alongside sort/match/classify in the existing host registry and works through both navigation and inline hosts. Timelines adapt to width and accessibility text size. The user can mark either side, inspect readable immutable confirmation, cancel, submit, read overall correctness and remaining attempts, and explicitly reload the latest receipt after the version changes. Unknown submissions lock new actions and retain their original payload, session, version and idempotency key for exact replay. No local choice unlocks the base node.

Creator configuration, secret-answer review and local-only rehearsal are present. Public preview uses a field allowlist without answers, effects or XP. Leaf edits and row reorder preserve existing IDs and unknown fields. Unknown extensions remain stored but block publication. Enabling compare preserves all other configured families. The registry now contains 25 creator families and 38 total families; the existing 12 advanced-game families are unchanged. Root features remain separate.

## Source evidence

Contract verified against backend revision `2cd0d28327daf46e417d4673aca621a27a244ff7`; compare code is unchanged from its `0520cca` source baseline:

- `AdvancedGameRuntimeServiceImpl`: action dispatch, readiness guard, submitCompare, runtime compare projection and compareSideView
- `AdvancedGameConfigValidator`: validateCompare, validateCompareSide, validateXp and resolvePresent
- `AdvancedGamePublicProjection`: copyCompare and copyCompareSide
- Business reference §7.2.L identifies the prior frontend dead-end; its client absence was not used as a reason to omit the current backend family

Only independently authored native code, synthetic fixtures, contract descriptions and source hashes are included. No backend source or real user/business data is copied.

## Verification boundary

Local results: 673 Python contract tests, 42 existing optional-source skips; all 13 compare checks pass with the authorized current backend supplied. 45 tooling tests pass. Project/scaffold deterministic regeneration passes. Supplementary pinned Tree-sitter parsing passes all 19 changed Swift files, with no recovery nodes. These are not compiler results.

26 new Core XCTest cases and 6 new synthetic UI tests are authored. Swift typechecking, Apple builds, Core/UI execution, real-device behavior, real-backend acceptance and visual/accessibility acceptance remain NOT_RUN for this packet. CI owner should schedule `PlayCompareFlowTests` in the intended UI shard and rerun project generation after integration. All live backend/device/reward grants remain off.
