# P036 profile “咔哒” guided override editor

Published base: `f329ff5180551ef3956b2718cb9ef071e2635409`, tree `e5a30ae239ec9f4cdf0576cab3d685b2189d2cdd`. Sealed feature origin: `adfbde7c2030070f25a1fa7ff89f89ed93307d11`, tree `56c0a043f169f727435557d8c3c6ae8e28b01027`.

## Verified gap and source

The sole restored master P036 names `toggleProfileKaccha`, `updateProfileKaccha`, and `pickProfileKaccha`. At pinned Mini commit `95e499471eaa39c28f77d16125f0cc17b8c37123`, `pages/publish/temp/index.wxml` lines 746–759 exposes a grouped switch, state variable, integer threshold, existing option picker and optional override line. Its JS handlers at 826–849 preserve inactive in-form values and use the first option's key as fallback. `advanced-game-config.js` lines 733–739 and 1017–1020 bridge editor-only kaccha and existing backend override; lines 1843–1849 validate namespace, integer, option membership and 120 UTF-16 code units. No private module is copied here.

Native adfb already has generic profile override objects and the question/option list and kind editor. This addition fills only the missing coherent shortcut. The original generic editor remains available for manual rules. No features 1–33 are replaced. No preview-only display, new game, or synthetic example is introduced.

## Full editing flow

Open the new link on a current pick question with an enabled profile and 2–6 existing options. Read current override without normalization. Toggle on, edit state/threshold/target option/line, inspect inline issues, then Apply to the shared local draft or Apply and save locally through the existing owner-scoped store. Save reports the actual store result and supports explicit retry. Title is still required by the existing local store path. Neither opening nor editing staged fields writes the draft or store. Closing, reloading or leaving the foreground discards only unapplied form changes; explicitly applied draft changes remain.

Only the selected question's override key changes. On activation the exact existing backend shape is `override = {requires: [{op: GTE, var, value}], option, voice?}`. Text is source-trimmed on explicit Apply; blank voice is omitted. There is never a persisted kaccha key. An explicit off Apply removes only the recognized override; its inactive values remain in the current editor so re-enabling restores them. Reload or reentry after off starts from source defaults because backend storage has no inactive kaccha cache.

This native staging boundary is explicit in UI. Mini updates its in-memory author form on every control event; native defers that mutation to Apply. Both use the same final override representation. Unrelated question fields, options/effects, other questions, profile metadata and all other draft fields remain intact, unlike normalizing the whole private Mini model.

## Safe subset and lifecycle

Only a single GTE condition with known fields is shortcut-editable. Multiple conditions, other operators, unknown override/condition keys or malformed structural types are read-only, including disable and save. The existing generic editor is the escape route; this shortcut never flattens or deletes manual rules. Recognized shapes with invalid variable/threshold/option/text can be explicitly corrected. False or malformed profile enabled flags are not silently repaired or enabled.

State names follow the source clue/relation/counter namespace. Values must be finite integers. Mini itself has no additional threshold bound; the existing native condition validator restricts -99...99. This shortcut uses that intersection and explains it inline, leaving old validation code unchanged. Numeric text uses finite decimal Double parsing (including source blank-to-zero); unsupported JavaScript-only numeric spellings are rejected rather than silently reinterpreted. The 120-character voice boundary uses source UTF-16 length after trimming, including literal {picked}/{assigned} placeholders.

Stable question key plus an exact sorted-JSON full-draft snapshot rejects stale work after reorder, delete, kind change, option edits or canonically equivalent but byte-different Unicode changes. Controller owner/session/identity, media/metadata generations, busy/review and per-action generation fences retire old bindings, Apply, Save and Close callbacks. External model publication, background, disappearance and reentry discard pending stages. The editor never evaluates a player's condition or assigns an actual answer; it cannot award, complete tasks, publish or request new permissions.

## Integration and verification

This complete batch registers two source leaves and the App test leaf in project.pbxproj. The Core test is discovered by the unchanged Package.swift directory target. All 25 bilingual keys are compiled from a dedicated Resources/TemplateProfileOverride.xcstrings resource. No existing catalog, Package.swift, CI or another feature line is changed. The only existing host change is one three-line NavigationLink addition immediately after TemplateProfileKindFields, conditional on pick kind. It also applies to the root's combined 31–33 host while retaining that separate top entry byte-for-byte.

Read `docs/registration/template-profile-override.json`. Baseline dependencies are TemplateProfileQuestionComposition, TemplateCreatorSchema, TemplateAuthoringStory, TemplateAuthoringDraft/JSON, TemplateAdvancedDraft, TemplateAuthoringModel and its existing owner/store contracts. There is no dependency on the recent preview sample leaf or 31–33 implementation.

Run the focused Python source contracts with a payload/repository root argument. Native XCTest files contain Core boundaries and the full staged editor/save/lifecycle flows. The packet records execution of real pinned Mini reference functions, supplementary Tree-sitter diagnostics, and actual isolated Git index forward/reverse/reapply witnesses. Source/parse checks are not Swift typechecking, an Apple SDK build or an App test. Native build, Core XCTest, App XCTest and device/UI tests remain NOT_RUN in this environment.


## Complete actual-published-base registration

This independent candidate is transplanted onto published commit `f329ff5180551ef3956b2718cb9ef071e2635409`, verified tree `e5a30ae239ec9f4cdf0576cab3d685b2189d2cdd`. The local same-tree witness commit is `ae7cbccf7c3401d76fc15dc63e11b5f55c105b30`; it is not presented as the published parent. All nine baseline dependency blobs are identical to the sealed adfb version, so no unpublished 25/26/sample/timer leaf is required.

This candidate now includes the actual Xcode file references, source/app-unit build membership and a compiled `Resources/TemplateProfileOverride.xcstrings` with all 25 exact sealed EN/ZH keys. SwiftPM already discovers Core and CoreTests by directory; Package.swift is unchanged. The earlier sealed package remains untouched; this complete batch records actual applied registration rather than stopping at a proposal. No other Xcode target settings or catalog keys are modified. Real native build and tests remain NOT_RUN.
