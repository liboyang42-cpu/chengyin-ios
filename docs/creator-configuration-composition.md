# Creator configuration composition

This follow-on fixes an actual authoring restriction in `be1f743`: the twelve original/PlayKit game forms were individually available, but `select` disabled their siblings and `issues` rejected more than one. The earlier 37-section structure count did not establish compound authoring. This change removes that restriction; it does not add to the 37-family count.

## Source contract

Current mini `pages/publish/utils/publish/advanced-game-config.js` defines independent sections (lines 1–37), enumerates all enabled sections (763–765), preserves disabled sections while normalizing enabled sections (768 onward), validates each family (1245 onward), and serializes their combined object (2018–2025). Current backend `AdvancedGameConfigValidator.validateAndNormalize` invokes each family validator independently (270–349). Neither validator imposes a single-game limit. The backend comment about one kit near line 292 is inconsistent with its executable validation and presentation aggregation; it is not used as a limit.

Root `present` applies across the compound object. Mini `presentError` (371–384) and backend `validatePresent` (367–385) reject inline if any enabled family requires fullscreen. A permitted first family must not hide a later restricted family. Default runtime presentation remains server-owned. Timer is an independent modifier; no source validator excludes it for coin or dice. Adaptive `variants` may address multiple enabled families in one rule; disabled or otherwise ineligible operands still reject. Rules retain first-match semantics and are not stacked.

Ten synthetic cases were executed against the current mini module: coin + dice + quiet + timer + time window; explicit fullscreen; inline rejection for coin; inline acceptance for dice + quiet; rejection for a later compass; rejection for creator steps; rejection for an invalid dice sibling; timer with coin/dice; compound adaptive relaxation; and rejection for a disabled adaptive operand. Accepted cases were serialized, parsed, and checked for surviving enabled sections. Backend source was inspected, not executed.

## Native behavior

- `enabledGames` enumerates every enabled game. `setGameEnabled` patches only the addressed section's enabled field. The destructive `select` API and single-game validation guard are removed.
- Every game has an independent editor destination and enable toggle. Opening a form has no selection mutation. Fields remain editable and retained while disabled. Existing creator forms, root controls, D20 mode and role-view authoring remain available.
- Timer stays independently editable. Shared presentation is shown once and checks every enabled game and creator family. Incompatible imported presentation is preserved with validation feedback; no silent fallback occurs.
- Preview exposes every enabled game and its existing local rehearsal or honest preview limitation. Immutable review lists every enabled family, with root rules indicated. No runtime action or provider proof is invented.
- Snapshot and request serialization preserve enabled siblings, disabled content, root controls and role views. Unknown fields retain existing lossless/fail-closed rules; this packet adds no generic JSON editor or passthrough expansion. Existing PlayKit row metadata preservation remains unchanged.
- Adaptive validation runs across the same compound draft. Turning off a referenced operand preserves the rule and blocks serialization until the author resolves it. Local first-match rehearsal can relax several families together.

## Verification

On the isolated `be1f743` copy: 620 Python contracts ran, 578 passed and 42 explicitly skipped; all 45 tooling tests passed; scaffold passed for 770 Swift sources and 6,335 bilingual keys; 12 changed/new Swift files parsed without recovery. The focused source-enabled run passed all 8 checks, including the 10 mini cases above. Fourteen new Swift core tests and three synthetic UI tests were authored. Core tests cover all twelve game families in one object, cross-family presentation, adaptive rules, unknown preservation, exact reserialization, account-local reopen, usage-location preservation, immutable review and stale-review rejection. UI tests cover independent editing, review enumeration and reopen.

Swift typechecking, Apple compilation, Core/UI execution, visual/accessibility inspection, physical devices and live backend execution are NOT_RUN locally. Existing production grants remain off. CI acceptance must be established on the publisher's integrated exact commit. No source code from the private implementation is copied into this deliverable.

## Integration

Apply the checked patch using packet exact preimages. Merge only the three keys in `Resources/CreatorCompositionLocalizations.fragment.json` using `catalog-preimages.json`; do not replace the whole catalog. Regenerate the project after merging. Generated project and whole catalog are excluded from the packet. This is a separate follow-on to the published creator/root/role work and does not modify player runtime or transport.
