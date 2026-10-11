# Merchant progressive-hint authoring

## Requirement and exact source

MASTER v10 W05 lines 399–427 requires editable merchant game drafts, human review and previews without real rewards, inventory or settlement. This increment closes one existing, persisted authoring chain. It does not implement the MASTER approval workflow or expand runtime hint/answer visibility.

Exact private source: `liboyang42-cpu/chengyin@f1fe895f34c3664783aafd6145cf93e0de15878d`.

- Mini `chengyinhub-xcx/pages/publish/temp/index.js:118`: `HINT_METHODS = [1, 3, 5]` (written answer, choice, GPS).
- JS `:1567–1586`, WXML `:1220–1238`: hint switch and three fields (`hint1`, `hint2`, `answerReveal`). Switching off empties all three. `hintEnabled` is editor state; it is not a persisted API flag.
- JS `:2519–2524`: unsupported/off hints are cleared in the outgoing Mini form. `:2755–2775` retains existing city-node submission body; `:3068–3070` hydrates these three source fields.
- `CmsMemberTemplate.java:146–155` and `CmsTemplatePublishRequest.java:141–148`: exact existing String fields, not merchant-private staff instructions.
- `TemplatePublishServiceImpl.java:398–440,564–566`: same merchant-owned template save whitelist copies all three values.
- `CmsMemberTemplateMapper.xml:40–42,294–296,361–363,445–447`: result, insert and update mapping. The update condition is `!= null`, so explicit empty strings clear existing text; missing/null is omitted and retains existing text.
- Existing `api/merchant/city-node/template/submit` and `api/template/myinfo` are unchanged. Exact-ID readback from the previous metadata batch remains the field authority.

The existing controller text-security join excludes the hint fields, just as it excludes ruleInstructions. The existing merchant endpoint is exempt from manual review and sets its own publication/review statuses. This increment neither fixes nor conceals that backend boundary and does not claim hint content is moderated. Production writes remain default-off without the existing explicit approval/session/journal setup. Backend remediation remains with root.

## Complete authoring flow

1. Open the existing merchant template form. Optional strings decode strictly; unexpected number/array/boolean values fail instead of becoming blank successes. Untouched source values, including whitespace and legacy incompatible content, remain unchanged.
2. For the same Mini-supported methods, enable hints and edit first hint, optional second hint and fallback answer/explanation. The three exact strings persist; the switch itself does not. Saving a switched-on but all-empty group reads back as disabled because no hint text exists.
3. Preview locally, one nonblank stage at a time. The fallback answer has its own explicit reveal action. Restart or any content edit resets the revealed stages. Preview does not edit the model, dispatch requests, validate completion or grant rewards. This is an author-only draft aid, not a simulation of runtime release timing.
4. Disabling empties all three fields. Clearing just one field preserves the others. Frozen review labels every previously saved field that will be cleared and shows all remaining proposed text verbatim. Cancel retains edits; explicit discard restores fetched source.
5. Changing to photo/QR with enabled hints blocks saving until the author explicitly disables hints or switches back. Unlike Mini's silent outgoing clear, native review requires a visible choice. Untouched legacy incompatible hints remain saveable during unrelated edits, so merely opening a template does not delete them. Their text is read-only in this editor until a supported method is chosen; disabling remains available.
6. Confirm uses existing endpoint approval, access/session fences, fresh baseline comparison and pending-operation journal. The exact acknowledged template ID is read again through myinfo, and returned server text wins over the submitted proposal. Empty-string readback consumes clear intent. Reusing an old review cannot send again; a changed account or server baseline prevents the save.

AI's existing allowed suggestion fields are unchanged. Raw AI output may contain hints, but none of the three fields can auto-merge. The first two batches' local planning groups still block all remote submission rather than silently dropping planning fields.

## Base and integration

Upstream is `96d727404a966cd3b3d2437c79449046beda560f`. Participation/exit batches are already present. Replay only the unsubmitted metadata, preparation and rule-step commits (`8448504`, `c988892`, `c12905f`) in this new worktree, creating dependency baseline `b23af697050489f78018ec0ebdc791917d1f8176`. The three runtime preimages match c12905f exactly. All five sealed trees/archives remain unchanged.

Only existing runtime files Contracts, SyntheticFixtures and Editor change. No new route, service or runtime file registration. Integration receives an 18-key en/zh-Hans localization fragment and new Core/UI test-file registration plus three UI method names. Central PBX, catalog and CI were not edited. Do not claim native UI acceptance until localization integration and Apple checks run.

## Verification

- 56 focused Python source checks pass (9 new plus 47 related checks).
- Five changed/new Swift files pass pinned Tree-sitter parsing. This is not Swift typecheck or Apple SDK verification.
- 19 Core XCTest methods authored: strict decode, exact optional/empty payloads, method support, untouched legacy preservation, staged preview projection, partial/full clear, absent-group equality, unchanged AI/local-only boundaries, cancel/discard/stale review, cross-account rejection, fake approved transport, server-authoritative readback and changed-server conflict.
- Three UI methods authored: progressive reveal/reset after editing with save/readback; disable/cancel/discard/confirmed clear; incompatible-method choice blocked until explicit disable.
- **NOT RUN:** Swift typecheck/Core XCTest, Xcode build, simulator UI, screenshots, VoiceOver, Dynamic Type and real-backend/provider/reward tests. The required dot environment has no swift or xcodebuild. No alternative environment was used.
- No old bug/CI repair, broad audit, real business write or full-suite acceptance claim.
