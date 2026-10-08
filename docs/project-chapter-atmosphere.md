# Chapter color authoring (P034 / W02)

## User-visible increment

City-orientation chapter settings now expose the mini program's five solid color
choices, a selected checkmark and a chapter-scoped preview. Choosing a color saves
only `chapters[target].preserved["atmospherePreset"]` through the existing local
editor store. This is a chapter-content preview, not an app theme or a claim that
the player renderer has been tested.

The palette is restricted to `productType == 1`, matching the current mini WXML.
Ordinary chapters and already-materialized starter chapters use their actual
model/chapter identity. A pending new chapter's temporary override binding keeps
its existing placement flow and does not receive this palette. Free-exploration
chapters gain no palette. Unsupported existing data gets a named, read-only
warning there instead of being replaced.

## Verified source and baseline

- iOS published commit: `1161bf975172091f49ba6b33fe49ce515ff9eca4`.
- Frozen baseline tree: `0ed2ed6d6ac55a13e54fa2e7b6c1e6286776acfc`.
- Master document: W02 model/publishing boundaries and P034's
  `onChapterAtmosphereSelect` event. W18 was checked; this slice does not introduce
  marketplace, license, fee or installation rules.
- [Mini editor action](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/pages/publish/fabu/index.js):
  `onChapterAtmosphereSelect` changes the chapter form, and `confrimChapter`
  normalizes the selected enum on completion.
- [Mini chapter UI](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/pages/publish/fabu/index.wxml):
  the chapter color block is city-only and contains five horizontally arranged
  choices. Native implementation uses SwiftUI buttons, scroll view and form.
- [Mini enum/aliases](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/utils/chapter-atmosphere.js)
  and [solid swatches](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/pages/publish/fabu/index.wxss):
  DEFAULT `#0A0A0A`, BLUE `#14294F`, RED `#4E1C24`, YELLOW `#4E4114`, WHITE
  `#F5F6F8`. Text is white except WHITE, whose foreground is `#111318`.
- [Backend validation](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-system/src/main/java/com/chengyinhub/business/util/ChapterAtmospherePreset.java):
  the five enum values and NIGHT→BLUE, ARCHIVE→YELLOW, NEON→RED, MOSS→DEFAULT
  aliases. The native payload guard matches Java's trim boundary and accepted set.

These references identify audited source contracts, not live-service readiness.

## Data and failure behavior

The existing `/api/topic/edit-detail` read and `/api/topic/create` / `/api/topic/update`
payload remain the only contracts. This slice adds no request, transport, endpoint,
production permission or network call.

- Merely rendering or leaving a chapter never rewrites a stored color.
- A known legacy local value is displayed via its alias, retaining its original
  bytes until an explicit choice. Existing authoritative readback still maps
  known aliases to canonical values.
- The previous readback decoder turned every unknown value into DEFAULT. It now
  preserves unknown strings and JSON structures. The palette shows no selected
  swatch for these values, and identifies the affected chapter by name.
- Unsupported values survive local save and cold restoration unchanged. FULL
  submission payload preparation is rejected until the user explicitly chooses a
  supported color. WHITELIST payloads still omit chapters and remain unaffected.
- A deliberate choice of a known color can replace the unsupported color field.
  Other chapter metadata, narrative bytes, media, nodes and chapters stay intact.
- Taps carry model reference, chapter ID, editor/session lease, host generation,
  mutation revision and exact draft bytes. Account changes, restored/discarded
  drafts, reordered/deleted/recreated chapters and retired views reject old taps.
- A repeated canonical selection does not write. A failed local save leaves the
  displayed value unchanged and reports that saving was not confirmed. The
  existing two-write new-draft store can have saved its envelope before failing
  its pointer write; this is explicitly tested and is not described as rollback.
  Choosing the color again retries the same local change.
- Existing production switches remain off. No real publication, payment or
  production data write was performed.

## Integration

Only two pre-existing implementation files change: the chapter form gets a small
mount/unsupported-data notice, and the existing project contract gets the focused
readback preservation plus chapter-payload guard. The previously published node
narrative and image/audio/template state owners are retained.

Merge the 19 EN/zh-Hans keys from
`Resources/ProjectChapterAtmosphereLocalizations.fragment.json` into the main
catalog during integration. This candidate does not modify that catalog, PBX,
AppSession, CompositionRoot or CI. The normal project generator must include the
new App/Core/AppUnit sources in the integrating tree; no project was regenerated
in this candidate.

## Verification and limits

- Focused Python source-contract suite: 52 discovered, 48 passed, four skipped
  because the optional external Flutter checkout is absent. These are source
  assertions, not Swift execution.
- Supplementary Tree-sitter parse: all six changed/new Swift files parsed with
  zero recovery diagnostics (`tree-sitter` 0.26.0 / `tree-sitter-swift` 0.7.3).
- Eleven Core XCTest methods and ten AppUnit XCTest methods are authored. They
  cover the actual decoder, draft/store restore, existing payload, controller,
  failed local persistence, permissions and lifecycle fences.
- Swift compiler, Xcode/Apple SDK, simulator and device execution: NOT_RUN in this
  workspace. No screenshot or visual acceptance claim is made.
- No existing XCTest expectation was changed. Inspection found no existing test
  that specifically asserted unknown chapter colors should become DEFAULT.
- No AppUITest file or CI UI budget was added.

Focused commands:

```sh
python3 -m unittest \
  Tests.ContractChecks.test_project_chapter_atmosphere \
  Tests.ContractChecks.test_project_node_narrative \
  Tests.ContractChecks.test_project_edit_contracts \
  Tests.ContractChecks.test_project_edit_rich_story \
  Tests.ContractChecks.test_project_edit_composition_fence \
  Tests.ContractChecks.test_project_story_media_gaps -v
python3 tools/check_swift_syntax.py \
  Core/ProjectChapterAtmosphere.swift Core/ProjectEditContract.swift \
  App/ProjectChapterAtmosphereFields.swift App/ProjectEditDetailForms.swift \
  Tests/CoreTests/ProjectChapterAtmosphereTests.swift \
  Tests/AppUnitTests/ProjectChapterAtmosphereLifecycleTests.swift
```

## Pending unified E2E acceptance

These scenarios are proposed for the shared acceptance pass, not executed here:

1. Open a FULL city chapter in the existing project-editor fixture. Confirm five
   choices, source order, correct swatches, checkmark and VoiceOver selected value.
2. Choose each color. Return to the chapter list and reopen the same chapter;
   preview should retain the selected color, while another chapter stays intact.
3. Restore the saved draft via the existing restore flow. Verify the selected
   enum remains in the prepared create/update payload; cancel review without
   submitting. Cold-model reconstruction is separately covered by AppUnit tests.
4. Restore an unknown string and an unknown structured color. No swatch should
   appear selected. The warning identifies its chapter. Review cannot prepare a
   FULL submission until a deliberate supported selection is made.
5. Verify free-exploration and WHITELIST flows show no enabled palette; unknown
   free-exploration data has an honest read-only warning.
6. Repeated tap, Back/reopen, logout/account replacement, restore/discard and
   chapter delete/recreate must not apply a queued choice to a new target.
7. Simulate local persistence failure. The displayed color stays unchanged, the
   warning appears, and retry succeeds without duplicating a chapter.
8. Check EN/Chinese, small screens, largest supported Dynamic Type, dark mode,
   VoiceOver and Reduce Motion. Swatches must remain solid and horizontally
   reachable, names/notes must wrap, and selection must not rely on color alone.

This slice does not claim complete W02/W18 or P034 parity, production publication
readiness, player-renderer parity or end-to-end acceptance.

## R1 readback normalization correction

R0 is retained separately. R1 prevents a more permissive display-normalization
rule from legalizing a value that the backend rejects before the payload guard
sees it. Readback now first checks the original value with `canSubmit`, and only
then normalizes a recognized value. Empty strings, whitespace-only strings, BOM
prefixes and NBSP-wrapped values survive readback and cold restore byte-for-byte;
FULL payload preparation fails until an explicit known-color choice replaces the
field. Those unsupported values also show no selected swatch in the native host.

Legal ordinary ASCII whitespace around known values/aliases still normalizes to
the canonical enum. Missing/null still uses the existing DEFAULT behavior.
Java-trimmable control characters outside JavaScript's trim set retain their
accepted original bytes instead of being relabeled; the backend-supported payload
is unchanged. Focused Core regressions exercise the decode→draft→restore→payload
chain, and existing AppUnit cold-model cases additionally cover empty/BOM/NBSP
values. No old test was generalized or removed.
