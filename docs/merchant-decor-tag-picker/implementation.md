# P079 store tag picker

The existing decoration tag section now offers a grouped native selection sheet: three source groups, eighteen preset values, explicit removal, custom tags, Cancel and Apply to the current local draft. The existing text editor is retained for historical values. Preset labels are localized for display; saved tag values stay the source strings. Opening does not trim, sort, deduplicate or truncate the loaded draft's tags. More than twelve historical tags stay visible and require explicit removal before this picker can apply. New custom tags use the source input's sixteen UTF-16-unit bound, ECMAScript trim and literal code-unit equality; duplicates do not append or reorder.

Apply changes only `MerchantStoreDecor.tags` on a copy of the captured whole decoration draft. Session scope, draft identity, current editable state, exact original draft and literal original tags are checked first. Unchanged Apply closes without editing, and a consumed/cancelled picker cannot write again. Reload, discard, scope change, background or departure closes the picker. Other decoration fields, current image flows, review/save and unknown-write locks remain with the existing coordinator. A failed existing save leaves the applied draft available for reopening. There is no new read, save call, entitlement or production grant.

## Source and scope

The same saved construction plan SHA-256 `eb23c8aefc22954bcd6f73ef800c32b763e7f8c4e3d4c68b0a0956756fd50133` lists P079 and tag events at paragraphs 1787–1790. The caller calls this file v9; its cover still says edition 8. No plan edit is included.

Private source `liboyang42-cpu/chengyin@ce61c0bbace743ff835cb297ef41c89b52181636` was read only to verify the interaction and existing wire contract. No private code file is copied into the candidate.

- `chengyinhub-xcx/pages/merchant/decor/index.js`, blob `36f0d912f63369d8d110b56757387c66ae81d307`: lines 28–32 preset values; 767–822 draft, toggle, custom tag, maximum twelve and existing tag save behavior.
- `chengyinhub-xcx/pages/merchant/decor/index.wxml`, blob `f37504292533118f599a3cd7a9503d79e80684cb`: lines 132–173 grouped choices and 471–481 custom input with `maxlength=16`.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantController.java`, blob `ac739a411d2de90de83bebecf482508e1d363a2a`: lines 668–721 existing PROFILE_WRITE authorization, `tags` handling, content checks and tag-discovery synchronization on actual save. The native picker does not call this mutating endpoint; it retains the pre-existing review/save pipeline and default-disabled production behavior.

This fills the ordinary tag-selection interaction within existing draft semantics. It is not complete decoration-page parity or approval to execute a production save.

## Integration and verification

Base tree: `907660925303d0fbb7d2484eabdb2937e1bdec1a`, after city-claim withdrawal. Only the `merchant.operations.tagsHint` region of existing `App/MerchantOperationsEditor.swift` changes: one inserted `MerchantDecorTagEditor(model: model)` line. A separate minimal hunk is supplied for integration because the shared candidate also has an independent NPC knowledge entry. Do not replace the whole editor from this isolated postimage. The NPC branch must be preserved.

Merge the thirty-three unique bilingual entries from `Resources/MerchantDecorTagLocalizations.fragment.json`, register the new App/Core/AppUnit files via the central project generator, and keep UI selectors, timing budgets and CI timeouts unchanged. No UI method is added or renamed.

Five focused Python checks and five affected-file Tree-sitter parses passed. Eight Core and seven AppUnit XCTest cases are authored but unrun. Swift/Apple build, runtime, accessibility, aggregate and live acceptance remain deferred. Source assertions are not runtime proof. Shared catalog/project, AppSession, Muse-reserved paths, services, contracts, coordinator and backend U2 remain unchanged.
