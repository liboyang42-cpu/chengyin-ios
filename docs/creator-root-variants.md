# Root authoring and legacy-game variants

This follow-on depends on frozen creator configuration v1. It adds two root controls (`mistakeTier`, `variants`), one separately counted backend A/B content feature (`roleViews`), the existing `diceRoll.mode=d20` variant, and scalar contract corrections. None changes the 37-section creator-family count.

## Source inventory and wire contracts

- `mistakeTier` is active: `easy`, `medium`, `hard`; omission uses the server default. The selected topic's difficulty table owns actual damage. Evidence: mini `advanced-game-config.js:116–130`; backend `AdvancedGameConfigValidator.java:383–396`; `TopicRouteRuntimeServiceImpl.java:1898–1940,2030–2046`
- `variants` is active: an ordered array of at most 16 objects containing `when` and a nonempty `relax` object. The exact 18-field easing whitelist is represented by `TemplateRelaxField`. Only enabled fields with effective changes are offered; attempts already unlimited cannot be tightened into finite attempts, and untimed ball challenges cannot receive time changes. Conditions use the backend state DSL, including tag value in `value`, positive node IDs and read-only system-variable whitelists. Evidence: mini `advanced-game-config.js:130–370`; backend `AdvancedGameConfigValidator.java:105–156,1773–1987`; `AdvancedGameRuntimeServiceImpl.java:689ff`
- Every rule's relaxed copy is validated independently. Rules never stack: the first matching condition is used and the session snapshot is frozen at start. Numeric tolerances preserve fractional values. The UI allows reordering and typed operation/amount editing, not arbitrary JSON patches
- `roleViews` is active in the backend, although absent from the 37 mini creator registry. Exactly two roles A/B and one view per role; text <=200 UTF-16 units, <=8 detail items per view. The backend projects `roleView` singular as A, B, SOLO or roleMissing based on the session/team. Evidence: validator `2081–2147`; `PlayEncounterServiceImpl.java:717–820`; `NodeJourneySnapshot.java:204–238,285–289`
- `diceRoll.mode` supports `d6` and `d20`. D20 uses integral DC 1–40, modifier −20…20, `normal`/`advantage`/`disadvantage`, and required success/failure text <=200 units. Six task faces are only required for D6. Switching mode preserves both sets of owned fields. Source: mini defaults/normalization/validation at `511,907–922,1490–1514`; `tests/unit/d20-template.test.js`; backend validator `2212–2257`
- The other six original games have no new active mode in this source registry. Their XP bounds and integral scalar requirements are enforced, and unknown extension fields fail closed. The backend reaction ceiling is 3000ms, while mini's base form remains at 2000ms; backend 3000ms is followed so valid adaptive relaxation remains representable
- Sort's existing `maxAttempts` is exposed and normalized because it is an adaptive-rule operand (0–10, zero/missing unlimited). This is a field completion, not a new family
- Retired gameTimer/stickerBook are not restored

## Authoring, reopen, review and rehearsal

Root controls retain exact wire values and unknown data in existing snapshots. Unknown root/condition/variant/role/legacy-game fields remain preserved and block submission. Root-only recognized configuration serializes instead of being discarded as empty. Existing full-payload size and live-write locks remain unchanged.

Existing creator navigation and review now include root controls and D20. Local state sliders/tags/completed-node switches demonstrate the first matching rule and changed values without altering real health, roles, rewards or sessions. A/B preview deliberately displays author-owned content, never claims the current player's role. D20 uses source-style deterministic examples (12, or 12 and 7), not random or signed server results.

Current native D20 runtime already renders server-provided pips/kept/total/success/action in `PlayKitDecisionProgressViews`; this follow-on does not duplicate it. No native `roleView` consumer was found in the integrated App/Core at this packet's audit time. The authoring preview states this limitation. A separately scoped runtime follow-on is required to render server-filtered role content; local role assignment is forbidden. Mistake damage and adaptive-session evaluation remain server-owned, not client-generated proof.

## Validation

- 12/12 current-mini synthetic source cases produced the expected accept/reject result (root tiers, adaptive shape/direction and D20)
- 553 Python contract tests: 513 passed, 40 skipped
- 36 tooling tests passed; structural/project/bilingual checks passed
- 9 changed/new Swift files passed supplementary Tree-sitter parse
- 23 new Swift tests authored for root roundtrips, ordered/first-match easing, independent bounds, whitelist/direction, conditional state, A/B pairing, unknown preservation, D20 and original-game constraints
- Swift tests/compilation, Apple build/app/UI, visual/accessibility, physical devices and live providers: NOT_RUN locally

Integrate checked narrow hunks against v1 preimages, merge the 82-key catalog fragment with exact keyed preimages, and regenerate the project. No generated project or whole catalog replacement is supplied. No stage or publication writes were performed.
