# Creator configuration families

## Delivered scope

This packet adds structured authoring for the 24 remaining sections in the current mini-program creator registry: random, branch, leaderboard, multiplayer, timeWindow, blindTaste, silentOrder, diyName, musicCorner, steps, dailySign, slowTask, estimate, pricePair, hiddenObject, predict, qa, scan, album, profile, photoCheck, check, note and typeIn. It builds on the seven previous games, timer, and the five PlayKit v3 additions. The combined registry has 37 authorable section families; this is not a screen, endpoint, complete-runtime or business-module completion count.

The family enum and per-family typed schemas supply numeric ranges, boolean switches, wire-enum pickers, repeated rows, nested structures, state effects and condition editors. This is not a raw-JSON editor. Configuration remains in the existing lossless draft representation and snapshot lifecycle. Leaf edits retain siblings. Unknown root/section/row fields survive local encoding and reopen, and block network serialization. Retired `gameTimer`, `stickerBook` and pre-vision `photoCheck.rule` are recognizable preserved data, not newly enabled gameplay.

Creator families have independent enable switches. Source sections can coexist, including opening hours plus blind tasting. Switching the older game selector no longer erases these independent sections. The existing 12-game picker still allows one selection; its prior behavior is otherwise retained.

## Current source intent and stricter backend boundaries

Contract evidence was read from the current mini-program `pages/publish/utils/publish/advanced-game-config.js` (registry, defaults, parser, normalizer and validator), and backend `AdvancedGameConfigValidator.java`. No private source implementation, secrets, user records or service configuration is copied into this packet. Fresh synthetic fixtures and derived Swift contracts are the deliverables.

- `pricePair` is now guess-the-picture. It is not the retired price-comparison game
- `musicCorner` supplies ambient content and never proves completion
- `steps` requires server-decrypted WeChat exercise data; local pedometer data is not equivalent
- Opening hours, daily signs, predictions and cross-day tasks depend on server date/time
- Photo review uses a server vision requirement/confidence contract, with optional CARD output; the old local image-scoring rule is blocked
- Backend requirements omitted by some mini UI checks are enforced: random <=50 cards, branch <=50 steps / <=12 options with a reachable terminal and terminal/no-options rule, multiplayer role coverage, profile option-key uniqueness across questions and mandatory questions, photo/type-in titles, type-in <=10 attempts, photo frame URLs <=512 characters
- `ADD_TAG` and `HAS_TAG` use the wire `value` field. Effects cannot mutate system variables except `sys.luck` via INC 1–3. Read conditions accept the backend whitelist, including `sys.passed.{nodeId}`
- Typed numeric input preserves incomplete text until valid; wire serialization restores numbers. Payloads exceeding the backend 64 KiB limit fail closed
- Source-stripped estimate/blind-taste/daily-sign/QA secrets are not filled with invented answers. Authors must provide valid owned values before this native serializer can submit; adopted-secret backfill is not claimed

## Review and local rehearsal

Each enabled family is reachable from the existing template review. Local answer rehearsal covers estimate, blind tasting, picture selection, QA, timed typing, branch traversal and image-coordinate targets. Card/verse samples and cross-day/check stages are deliberately selected examples. Profile inputs, note/name suggestions and album content can be inspected locally. State effects, rewards, team records, ranking, predictions and real completions are never applied.

No runtime provider is fabricated. Camera/vision, QR binding, AR, WeChat steps, server clocks and multiplayer state show explicit limits while allowing configuration. Site-relative media can be authored but needs a configured media host for interactive image rehearsal. Music rehearsal reviews its linked track; it does not claim listening evidence. Full form visual quality, accessibility, Apple runtime, and original-image tap geometry still need Apple/device acceptance.

Root-level capabilities beyond the 37-section registry (for example `mistakeTier`, adaptive `variants`, role-view or other future root structures) remain preserved and fail closed if not understood. This packet does not claim to implement those separate capabilities or expand the original seven games' newer field variants.

## Integration and verification

Apply exact shared-file hunks to the post-PlayKit-v3/v4 base, copy new files, and merge the keyed localization fragment against its per-key preimages. Regenerate the Xcode project with `tools/generate_project.py`; do not overwrite another worker's generated project or catalog. All live grants and transports remain unchanged/off.

Validation at packet creation:

- Current mini source validator: 24/24 synthetic valid fixtures accepted and 12/13 source-boundary mutations rejected; incompatible scan/AR model data is silently removed by mini normalization, while native rejects it before serialization to avoid silent loss
- Python contracts: 538 run, 498 passed, 40 skipped
- Tooling tests: 36 passed
- Structural/project/bilingual checks: passed
- Swift syntax preflight: 10 changed/new Swift files, no Tree-sitter recovery nodes (supplementary syntax only)
- Authored Swift tests: 21 cases, including all 24 family roundtrips, every top-level numeric boundary, unknown-field snapshots, graph reachability, source enum identity, provider separation and local rehearsal
- Swift compilation/tests, Xcode build/app tests, simulator/visual/accessibility, physical devices and live backend: NOT_RUN locally
