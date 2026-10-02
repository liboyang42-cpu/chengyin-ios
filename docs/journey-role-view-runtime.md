# Server-assigned role content runtime

## Scope and active source

This packet closes the active player-side `roleView` consumer gap identified during creator-root authoring. It does not add a creator family or duplicate the existing D20 runtime.

Source evidence:

- `ApiPlayEncounterController.java:27–36`: authenticated, read-only GET `/api/play/encounter`, accepting `topicId`, optional `activityId`, and `nodeId`
- `PlayEncounterServiceImpl.java:94–148`: resolves the current owner's scoped session, returns `nodeId`, `runId`, `stateVersion`, then appends role projection
- `PlayEncounterServiceImpl.java:717–820`: server determines A/B from the active team; SOLO gets both views; ambiguous membership returns `roleMissing=true` and no views. Each view has `roleId`, optional title/body and items containing label/text
- `AdvancedGameConfigValidator.java:2081–2147`: exactly A/B, one view each, text <=200 UTF-16 units and <=8 items

Fresh native types retain only the validated server projection. They do not read `advancedConfigJson`, creator `roleViews`, team order or player names to reconstruct a role. A/B must contain exactly that one view; SOLO must contain A and B exactly once; roleMissing must contain no views and no contradictory role. Mixed or opposite-role responses are rejected in full, not filtered into an inferred assignment. Unknown extra response fields are never retained or rendered.

## Flow and lifecycle

- A separate read-only role coordinator is composed with the existing journey-check coordinator; check mutation/review/journal semantics are unchanged
- Activity reads include the exact `activityId`; topic reads validate the topic identity and never fabricate an activity
- Every role projection requires matching node identity and positive run/nonnegative state version. When the parent has a run/version, stale or wrong-run content is withheld
- Role sections render in both the node-task screen and chapter-inline game path. There is no player-side role picker. Server-supplied partner labels are displayed only as labels
- Content is memory-only. Account/namespace/epoch changes, node departure and explicit hide clear it; asynchronous replies are generation-fenced. Reopening and explicit refresh perform a fresh read. Inline chapter backgrounding also clears the projection
- Main task controls remain available when role data is absent, missing or unreadable. Refresh is read-only and never assigns a role
- Existing read grants remain default-off. No payment, device permission, role write, gameplay completion, reward, check mutation or provider activation is added

The role read is deliberately independent of the older optional check probe so private role content can be cleared/refreshed without replaying check operations or changing an outstanding check review. Initial node entry can issue two bounded reads to the same encounter endpoint when both augmentations are enabled; there is no polling or hidden write retry.

## Verification

- 607 Python contracts: 566 passed, 41 skipped
- 44 tooling tests passed (their timeout-handler output is a mocked tooling test, not an Apple execution)
- Structural/project/bilingual checks passed
- 11 changed/new Swift files passed supplemental Tree-sitter parse
- 24 Core tests authored: exact roles/cardinality, mixed/opposite privacy rejection, public-template refusal, scope GET fields, run/version bounds, close/reopen, stale replies, account changes, default-off reads, explicit refresh and unauthorized-session handling
- 5 UI tests authored and included by existing automatic shard discovery: A, B, SOLO, Chinese missing-role state, contradictory payload withholding and close/reopen
- Five synthetic fixture envelopes passed JSON syntax validation
- Swift compilation/tests, Apple build/app/UI execution, visual/accessibility, physical-device and live backend acceptance: NOT_RUN locally

The isolated base copy preceded completion of creator-v2's catalog merge. Its already-approved 82-key fragment was overlaid only in the isolated work catalog for complete validation; this packet contains only the 13 new role-view keys and their exact preimages. Generated project and whole catalog files are intentionally excluded. Apply narrow shared-file hunks and regenerate the project after integration.
