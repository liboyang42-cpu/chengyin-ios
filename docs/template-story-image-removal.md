# P036 local story-image removal

Baseline `7bf858c23374b808c6d932367f96e97d09e9d799`. Master P036/PA02, event `removeStoryBeatImg`.
Source: `chengyin` commit `f859cd6e2618f618a53f5cd33949259828e86313`, `chengyinhub-xcx/pages/publish/temp/index.js:1828-1833`; blob `76e39df5c326aaf029bda8da21562072fb352553`.

## Implemented call path

Existing authoring → story timeline → each stored image reference now has an occurrence-specific Remove image button → `TemplateStoryEditor.removeImageAction` → `TemplateStoryImageRemoval.applying` → existing `apply`/`setStory`/`model.changed` local draft path. Existing media reviews are invalidated by that path. No inert helper or unwired proposed screen.

The source filters by image index, not URL; duplicate URLs, empty strings and opaque/unknown URL strings therefore remain independent occurrences. The native action captures the entire exact UTF-8 image array. A repeated old tap, changed array, missing beat, invalid index, reload, dismissal, discard or owner/session change cannot remove a different image. Merely opening the view or preparing then abandoning an action changes no draft bytes. Returning to the view reloads and issues fresh actions. The UI never fetches a reference and never deletes a server asset.

Existing timeline storage semantics remain: explicit edits use `setStory`, preserve legacy independent storyText, derive summary through the existing marker, omit wholly empty beats at serialization, retain the final editor beat, and allow reducing oversized historical image arrays. Unknown timeline shapes stay read-only. No URL validation, trimming, newline splitting, reordering, new persistence format, network write, reward, upload or production publishing is added.

## Event and acceptance boundaries

- `removeStoryBeatImg`: native local action and occurrence guards implemented; pinned source execution covers 8 cases.
- Other story/add/upload/preview/publish events: unchanged and not claimed complete.
- Source structural checks: 4 focused Python contracts pass. Existing story-readback 3 and legacy-story 3 contracts pass. Existing story-projection suite: 6 pass, 1 fails only because new labels are intentionally not merged into the central catalog yet; this is an explicit integration gate, not a full-green claim.
- Authored tests: 5 Core cases and 6 AppUnit lifecycle cases.
- Swift typecheck/test, Xcode build, simulator, real TC01/TC02 and accessibility execution: NOT_RUN; Swift/Xcode absent. Source checks are not runtime acceptance.

## Required central integration

No PBX or central catalog was edited. Register `Core/TemplateStoryImageRemoval.swift` in the app target and `Tests/AppUnitTests/TemplateStoryImageRemovalLifecycleTests.swift` in AppUnitTests; SwiftPM auto-discovers Core/CoreTests. Merge `docs/localization/template-story-image-removal.json` into the existing xcstrings catalog, retaining unrelated keys. Existing App view/editor files are already compiled. Run focused Swift tests and AppUnit tests, then English/Chinese VoiceOver and large-text timeline checks, repeated taps, dismissal/return, owner switch and local save/restore. Publishing stays unavailable without its formal adapter.
