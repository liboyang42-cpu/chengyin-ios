# P036 D6 configuration → local sample rehearsal

## User flow
Continue editing the existing D6 count (one or two dice) and six face-action strings in the dice configuration page. Open the new local sample view when the current D6 configuration passes its existing validation. Choose one example pip per die, explicitly show the sample, inspect the pips and total, then reset or choose other example values. Return to the existing configuration editor to change the content and use the existing local save/restore flow.

For one die, the sample shows the corresponding normalized face action. For two dice, it shows both pips and their sum only. It never indexes the six face actions with a sum of two dice. Samples are explicitly author-selected examples, not random rolls or authoritative player results. No sample pips/results are stored in the draft, submitted, scored or granted as rewards.

## Source and true missing capability
The master P036 index lists `onDiceCount`, `onDiceFace`, `tryCurrentGame` and `onPvKitAction`. The real Mini `temp-index.js` 549–563 configures one/two dice and six actions; its comment explicitly says two dice only report a sum, not an indexed task. Lines 2309–2323 launch a preview using the current configuration; 2362–2380 isolate local preview feedback and close state. WXML 540–549 confirms the count/faces editor.

Before this change, `TemplateAdvancedGameConfigurationView` delegated D20 to its existing rehearsal and newer mini games to their previews, but the D6 branch only contained editing fields. Those fields are byte-preserved; a local preview entry completes this path. The production player dice view invokes server actions and therefore is deliberately not used to manufacture a player roll. Master K31's authoritative server/receipt/payment boundary remains unchanged. Mini's delegated preview helper was not available here; this candidate does not claim to reproduce its randomization or all gameplay visuals.

## Contract and ownership
`TemplateD6Rehearsal` reads an isolated copy of the existing dice section and applies existing native validation. The new local view does not rewrite or normalize the stored draft. Display strings follow existing serializer trimming. Other invalid configured families do not block inspecting this D6 configuration, but existing whole-draft save/publish validation is unchanged.

The preview owns a captured owner/draft/metadata/media lease. Any model publication immediately retires the sample and local controls, including draft A→B→A changes before the parent onChange callback. An explicit reload acquires the current valid configuration. Reset rotates local controls; changing a pip clears the last sample. Leaving, account changes and pending-write locks deny retained actions. No clock, RNG, sensor, network, media renderer, service factory or production permission is introduced.

## Verification / integration
Native Core tests cover all six single-die examples, all 36 two-dice combinations, validation, display normalization, invalid samples and local draft round trips. App tests cover choose/show/reset, edits/reload, lifecycle/owner fences, locks and fresh local restore without sample state.

Swift/Xcode are unavailable on this computer: authored native tests, Apple build/UI and production acceptance are NOT RUN. Python checks verify bounded source contracts only. Apply the patch independently on base 96d7274; it does not depend on or touch the seven earlier packages. Register the new sources/App tests and merge the supplied localization fragment additively.

Apple manual check: edit all six actions, set count 1, test pips 1 through 6; set count 2 and test 6+6, ensuring no face action appears; reset; return and edit a face; reload current configuration; save/leave/restore and verify configuration persists while sample state does not.
