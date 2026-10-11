# Merchant player-instruction steps

## Source and scope

MASTER v10 W05 lines 399–427 requires an editable merchant game draft and human review. This increment adds a missing **existing persisted content field**, not completion of all W05 constraints or a new publish/reward capability.

Exact private backend/Mini source: `liboyang42-cpu/chengyin@f1fe895f34c3664783aafd6145cf93e0de15878d`.

- Mini `chengyinhub-xcx/pages/publish/temp/index.js:1375–1410`: `ruleSteps` is display state only; trims nonempty rows and joins with a newline into existing `formData.ruleInstructions`; add up to 12, remove except last. WXML `:166–187` shows numbered editable steps, `maxlength=60`, add/remove actions.
- `CmsMemberTemplate.java:78–88` and `CmsTemplatePublishRequest.java:57–61`: `ruleInstructions` is a String visible to players. **It is not the staff-private `merchantGuide`.** The editor and review explicitly warn against putting answers or staff secret words here.
- `ApiMerchantNodeController.java:172–231`: existing `api/merchant/city-node/template/submit` checks project-management grant, merchant-node permission, reward ownership and text security. No grants or endpoint changes. The existing controller text-security join does **not** include `ruleInstructions`; this source limitation is recorded, not repaired or described as a moderation guarantee. Production activation still needs separate authorization and review of this gap.
- `TemplatePublishServiceImpl.java:398–440,523–535`: existing ownership check, DTO whitelist and ruleInstructions copy. Merchant template save returns its ID. The existing server path assigns draft/status/check/publish states itself and is documented as exempt from manual review; this increment does not implement the MASTER dual-domain approval workflow.
- `CmsMemberTemplateMapper.xml`: existing result/insert mapping and `:419` update condition `ruleInstructions != null`. Omitted/null leaves an existing column untouched; an explicitly supplied empty String clears it. This is an evidenced existing clear contract, not a new `clearRules` command.
- Existing `api/template/myinfo` read is reused through the previous metadata increment. Server-returned exact-ID data replaces the submitted draft. Acknowledgment alone is not considered field readback.

## Native behavior

The existing merchant template form now offers ordered step input, add and remove. One empty row always remains. This is a native editor over one persisted String; no `ruleSteps` array is sent.

Decode is strict optional String. Unedited legacy raw text (including whitespace, long lines or more than 12 rows) is preserved byte-for-byte. Missing/null stays omitted. Display splits on newlines and trims empty rows, as Mini does; no source text is truncated just by opening the editor.

An explicit rule edit enables the editor constraints: at most 12 rows, at most 60 UTF-16 units per row, and one line per row. Invalid pasted text stays visible and blocks review rather than being truncated or silently creating extra rows. Limits are client editing constraints from the Mini affordance, not invented backend schema validation. Longer legacy text remains saveable during unrelated edits until the user edits the rules themselves.

Edited nonempty rows are edge-trimmed and joined with newlines. Blank rows are omitted. Clearing every row produces `ruleInstructions: ""`; the form explains this and frozen review explicitly says existing rules will be cleared. Merely adding an empty step does not add an empty instruction to the wire value.

All edits flow through the existing coordinator. Cancel retains the draft; discard restores the fetched source; changes invalidate an old review. The existing endpoint approval, owner/session fence, refreshed baseline, pending-operation journal, default-off production gate and no-replay logic are unchanged. Only synthetic transport/fixture tests exercise the adapter here; no real business data was sent.

AI's current suggestion allowlist remains unchanged and cannot apply this field. Source `ruleInstructions` may appear in raw AI output, but it is not auto-merged. The first two batches' local planning groups still block remote submission instead of silently dropping their fields.

## Base and integration

Upstream: `51d3e24de92427a777f8690f847cec39971b041a`. New detached worktree replays the four sealed dependency commits (originals `c80fcab`, `c626436`, `8448504`, `c988892`) into baseline `16e1ccc6b9752c892a33b273f4a7affb26639bd0`. The three edited runtime preimages exactly equal `c988892`; the original four trees and sealed archives were not modified.

Only existing runtime files changed: Contracts, SyntheticFixtures, Editor. No central PBX, catalog, CI, routes or service registration edits. Integrator receives the 14-key en/zh-Hans localization fragment, including two integer-interpolated accessibility labels, plus the new test-file/method registration fragment. Do not claim the UI is accepted until those resources are merged and Apple checks run.

## Verification

- 47 focused Python source-contract checks pass (8 new + 39 prior); these inspect code, not runtime behavior.
- Five changed/new Swift files pass pinned Tree-sitter parsing, not typecheck.
- 15 Core XCTest methods and two simulator UI tests authored: decode, legacy preservation, add/remove limits, UTF-16, pasted newlines, explicit clear, exact wire keys, AI exclusion, local-plan blocking, stale review/cancel/discard, approved fake-transport save/readback, no approval/no send, no replay.
- Apple build/Core XCTest/UI execution, screenshots, VoiceOver and Dynamic Type are **NOT RUN**: neither swift nor xcodebuild is installed in the required dot environment. No environment switch or dependency installation attempted.
- Initial Python invocation accidentally named a nonexistent AI-review module; corrected to the existing field-review module and rerun cleanly. This was a test-command error, not a product or CI repair. The initial log is retained in evidence.
- Known historical static failures were not changed or reclassified by this batch. No all-suite/CI claim, no live backend, payment, provider or reward acceptance claim.
