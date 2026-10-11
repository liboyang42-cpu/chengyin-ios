# Merchant template textual story timeline

## Requirement and source

MASTER v10 W05 lines 399–427 requires editable merchant game drafts, human review and previews that do not consume inventory, pay or reward. This increment adds the missing **template textual story timeline**, not the store-profile story page, a runtime storyline, or complete Mini image-upload parity.

Exact source snapshot: `liboyang42-cpu/chengyin@f1fe895f34c3664783aafd6145cf93e0de15878d`.

- Mini `chengyinhub-xcx/pages/publish/temp/index.js:1806–1842`: separate story moments with text/tag, add/remove and existing images. WXML `:1320–1365` contains that editor.
- JS `:2561–2572`: persists full moments in String `storyJson`, derives the existing `storyText` summary using a 500-code-unit slice, and sends empty strings when the story module is removed. Wire moments contain text/tag/images, never editor IDs.
- JS `:3161–3177`: hydrates modern `imgs` and older single `img`; plain legacy storyText becomes one moment.
- `CmsTemplatePublishRequest.java:131–139` and `TemplatePublishServiceImpl.java:561–563`: existing String DTO and whitelist copy for storyText/storyJson.
- `CmsMemberTemplateMapper.xml:37–39,291–293,358–360,442–444`: result/insert/update fields; updates use `!= null`, so absent/null retains existing columns and explicit empty strings clear them.
- Existing merchant template submit ownership/grant/security path and exact-ID `api/template/myinfo` readback are reused without route or permission changes.

At the verified f1fe source snapshot, the merchant controller's text-security join does not include storyText/storyJson. Its existing merchant save path is exempt from manual review and assigns server-side statuses. Root reports a later private feature13ef25a fix for ruleInstructions; this batch neither inspected that later fix nor assumes it covers story or hint fields. Backend work stays with root. Default-off production writes and all existing approvals remain; this is not a moderation or MASTER dual-domain approval guarantee.

## Authoring behavior

- Explicitly enable a template timeline. Add text and an optional time label, add/remove moments, and move them earlier/later. Stable IDs exist only in the editor; none are sent. The final editable row remains available.
- Read-only author preview shows the complete textual sequence and counts of retained existing image references. It does not claim to render Mini's full image timeline, publish, unlock player content or grant rewards.
- Modern image arrays and legacy single-image fields are preserved. If both exist, both are retained and counted. Image-only moments are retained. This increment cannot add, replace, upload or delete image files.
- Removing saved moments lists their original text/labels and image counts in frozen review. Removing the module explicitly clears both existing wire strings. Image warnings mean removing references from this timeline, not deleting uploaded files.
- New entirely blank moments are omitted, as Mini does. A label-only edited moment blocks review until text is supplied or the label is removed; its label is never silently discarded.
- The storyText projection is capped at 500 UTF-16 units without splitting a Swift Character. Full text remains in storyJson. Preview/review explicitly disclose when the summary is shorter. No full narrative truncation.

Untouched optional source strings remain exact. Plain legacy text and an empty JSON array can be edited safely. Recognized nodes accept optional text/tag and modern/legacy String image values. Unknown keys, malformed JSON, wrong nested types or non-array shapes make the timeline **read-only and unchanged**. Unlike Mini's fallback behavior, an unrecognized rich source is never replaced by its short storyText summary. Outer API fields of the wrong type still fail strict decoding. Opaque stories can be retained during unrelated template edits, but cannot be edited or cleared here.

Cancel keeps the edited timeline; discard restores fetched data. A new edit invalidates an older frozen review. Existing approval, merchant access, session, baseline-freshness and pending-operation gates remain unchanged. After acknowledgement, exact-ID source readback replaces proposed text and consumes removal intent; old confirmations cannot replay. The synthetic fixture performs this readback reconstruction too.

AI's current suggestion allowlist is unchanged: the timeline is not automatically filled or replaced. Existing AI storyText-to-short-description behavior is outside this increment. Local participation/exit groups still block sending rather than silently losing their fields.

## Base and integration

Upstream: `96d727404a966cd3b3d2437c79449046beda560f`. Exact incremental baseline: `ba3a202a7915cf6fb0ff3e3206e4380e9c08b31a`, which includes the unsubmitted metadata, preparation, rule-step and hint dependencies. The first two merchant batches are already in 96. All six earlier sealed worktrees/archives stay unchanged.

Only existing Contracts, SyntheticFixtures and Editor runtime files change. Registration is delivered as a fragment: 25 en/zh-Hans strings, two new test files, three UI method names. No new runtime file, central PBX/catalog/CI, creator template or merchant-profile story changes.

## Verification

- 66 focused Python source checks pass (10 new +56 related). These are source checks, not behavioral execution.
- Five Swift files pass pinned Tree-sitter parsing, not typecheck. Initial parser recovery on cast/coalescing argument syntax was resolved with explicit parentheses; final parsing has no diagnostics.
- 21 Core XCTest methods authored: strict outer decode, legacy/empty source, safe/opaque JSON, stable add/remove/reorder, modern and legacy image retention, removed-content review, whole-character summary bound/full-text preservation, exact payload/clear, AI/local-only guards, cancel/discard/stale review/account switch, fake approved save/readback and missing-approval no-send.
- Three UI methods authored: create/reorder/preview/cancel/save/readback, disable/cancel/discard/clear, and removed saved-moment review.
- **NOT RUN:** Swift compilation/Core XCTest, Xcode build, simulator UI, screenshots, VoiceOver/Dynamic Type and real-backend/provider/payment/reward acceptance. Required dot environment lacks swift and xcodebuild; no other environment used.
- No old issue/CI repair or full-suite acceptance claim.
