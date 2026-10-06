# P034 anchored story-media insertion gaps

This bounded increment completes first/middle/end placement for the already supported image and audio story blocks. It does not add a media kind, upload route, source-reader permission, publishing action, recorder, Photos grant or document grant. Independent upload approvals stay default-off.

## Source witness

Repository `liboyang42-cpu/chengyin`, commit `7aa31fbda505e079f3cda0e6e6aa19068e7efe58`:

- `chengyinhub-xcx/pages/publish/fabu/index.wxml`, blob `50c1daeebb57e7eb3970bc8576dcecd28f52d205`: lines 428–436 render a selected gap before each block; 615–628 render the explicit tail gap.
- `chengyinhub-xcx/pages/publish/fabu/index.js`, blob `5bae9013997f817f6b89e09d81ce91c796e265f3`: 1040–1048 uploads an image then inserts at the selected gap; 1056–1065 inserts blank audio first; 1069–1086 subsequently selects a document for that exact audio block; 1121–1135 forwards the position to `insertMediaAt`.
- `chengyinhub-xcx/pages/publish/utils/publish/pro-editor-story.js`, blob `c0a6005ba0598389333f70db9a88e23f7700131b`: 434 onwards checks the 200-block bound and uses the selected insertion position.

The native predecessor already implemented uploads, local receipt journals, local editor save and the typed pending-material host. Only append/replace image actions and append-only blank audio were available. Native captures an anchor identity and exact draft rather than retaining Mini's numeric index through asynchronous work.

## Behavior and ownership

`ProjectStoryMediaGap` holds owner key, draft bucket, chapter identity, optional before-block identity, exact draft hash and ordered block identities. A nil anchor is explicit end. Missing, duplicate, moved or replaced anchors fail closed; they cannot become append. Duplicate chapter or block identities and the existing 200-block cap are rejected.

Each real story block has a collapsed insertion menu. Image selection uses the existing picker/crop/upload/journal path, adding a block only after the exact uploaded reference is applied and the ordinary editor save succeeds. Audio first persists a blank block at the selected gap; choose/cancel/reopen/fill operates on that same block. Picker cancellation keeps the blank audio block, which the existing serializer omits until filled.

The existing ordinary and controller-minted pending hosts remain the only media hosts. Pending materials are not implicitly placed. Arbitrary chapter bindings do not gain media capability. End controls retain their established identifiers. Existing append/replace journals keep their version-1 Codable shapes; new insertion journals use the distinct `insertBefore` enum case.

A live presentation captures both topology and a monotonic exact chapter-content revision, plus its existing editor lease, incarnation, session, draft identity, source and journal. Delete/reorder/replace-and-restore ABA cannot revive its callbacks. Only the exact successful synchronous local save performed by that presentation may advance its own stamp for applied-marker retry. Fresh presentations may recover a matching durable receipt against an unchanged saved draft. Fresh recovery does not inherit the old runtime lease or silently retarget a receipt to a different gap. Inserted-image recovery checks exact block bytes, location and the full original draft with the inserted block removed. End append recovery similarly requires the original end postimage. Replacement recovery keeps its prior behavior.

## Verification boundary

Authored coverage: 7 independent Core methods, 14 DEBUG-only real-model AppUnit methods, and 6 complete image/audio first/middle/end UI methods. UI helpers cover cancellation, exact saved order, cold restore and prepared-reference order. Every existing XCTest source file is byte-identical to the predecessor. Synthetic-dependent AppUnit methods remain DEBUG-only; the prior independent reader tests remain Release-visible. The inherited central Debug-only target configuration is retained verbatim.

No Swift or Xcode exists in this executor. Python source-contract tests, project/scaffold checks and Tree-sitter parsing are structural checks, not Swift typechecking, XCTest, simulator, accessibility, device or live-service execution. Integration must retain larger central timing costs/history and run Apple validation before claiming UI behavior. Six new complete UI methods each have an unmeasured 900-second estimate, independently schedulable at 1,200 seconds including the unchanged 300-second startup reserve; no 1,800-second process limit is relaxed.
