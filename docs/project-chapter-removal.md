# Chapter deletion confirmation

## Source-backed gap

At backend / mini commit `ce61c0bbace743ff835cb297ef41c89b52181636`, the actual editor is
`chengyinhub-xcx/pages/publish/fabu/index.wxml` and `index.js`, not `pages/topic/fabu`.

- The active chapter settings button is `deleteChapter` (WXML line 1237).
- `deleteChapter` (JS lines 3226–3251) asks for confirmation before deleting the chapter.
  Its visible copy does not promise an undo. The unused generic undo stack is not a user-visible recovery feature.
- Source blobs: WXML `3348b97e3c694a5f8409b40ff3c7adae36dddf80`; JS `5b530a2f42df49f7e4b526a5626de4440252b85b`.
- Native `ProjectEditView.chapterStructure` previously removed the chapter directly from `onDelete`.

Sources: [mini markup](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/pages/publish/fabu/index.wxml#L1237),
[mini action](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/pages/publish/fabu/index.js#L3226).

## Native behavior

The existing swipe / edit-list delete now opens a confirmation listing the captured chapter names and node counts.
Cancel and interactive dismissal do not write. Explicit confirmation saves only removal of the selected chapters,
including their contained nodes and story blocks. Sibling chapters, pending materials, tickets, opaque local metadata,
topic settings and cross-chapter rule / graph references are not rewritten. Existing payload validation remains in force.
Deleting the last chapter leaves the existing create-chapter entry available.

The rendered offset callback owns the controller identity, owner/session epoch, coordinator draft identity,
editor incarnation, full-edit authorization, structure revision, mutation revision and exact encoded draft bytes.
The same fences are checked at confirmation. Draft edits, reorder, delete/reinsert ABA, same-byte setter,
scope/account/epoch/visit changes and retired hosts invalidate the old intent. A new render cannot redirect an old offset.
Repeated and reentrant confirmations do not duplicate saves. WHITELIST never grants chapter deletion.

## Unconfirmed local persistence

The existing local save writes an envelope and then, for a new draft, an active pointer. It is not an atomic two-item transaction.
If either step fails, the displayed draft is not changed by this controller, but the saved envelope may already contain the deletion.
The UI explicitly says the result is unconfirmed and consumes that deletion intent. A coordinator latch is bound to the original owner key and draft identity. It blocks subsequent local saving, mode copying, replacement, local deletion and review/submit for that draft;
it does not silently retry, replace the unknown action, promise unchanged disk contents or report success.

The coordinator can issue an opaque readback capability for this review. The App cannot choose a foreign account or identity.
Readback reads the original identity's envelope directly, including when a failed first pointer write left no active pointer.
It checks coordinator instance, owner/session/epoch, editor visit/generation, FULL scope and baseline before and after the read.
The displayed decoded draft is classified as original content, the proposed removed content, other/incompatible content,
missing, unavailable or stale. This is an informational comparison of the supported local envelope projection, not a new durable receipt.
It never repairs or follows the active pointer, mutates the displayed draft, acknowledges the save, retries removal or unlocks the consumed intent.
The lock remains after closing or leaving the editor, so automatic leave-time saving cannot overwrite the unknown envelope. Other accounts, draft identities and independent coordinators are not frozen. The captured readback remains available while that exact editor context is current.
Leaving or changing the owner retires access. A pointer-repair / durable recovery workflow is outside this increment.

## Scope and verification

No new HTTP endpoint, live write capability, payment rule, publishing/retirement contract or LocalStore behavior is introduced.
The existing topic create/update/V2 paths remain gated. This is local draft authoring, not deletion of a published release or run.
Node removal is intentionally separate: the mini uses different behavior for free-exploration nodes and city story nodes.

Focused regressions: six Core XCTest methods and eighteen App-hosted XCTest methods cover confirmation/cancellation,
storage restore, last-chapter creation, stale/ABA offsets, owner/scope changes, repeated taps, envelope/pointer failures,
original-identity readback, foreign-coordinator rejection, post-read account changes, failure followed by all local write entrypoints and leave, owner/draft-isolated suspension, and existing unknown submissions.
Python contracts inspect mounted behavior, permission fences, local-only data flow and the English / Simplified Chinese fragment.

Swift compilation, XCTest, simulator UI, device behavior and production acceptance were **not run** in this Linux workspace.
Tree-sitter parsing is supplementary syntax evidence only. The localization fragment and new App / AppUnitTests files
must be merged into the main catalog and generated Xcode project by the integration owner; this increment does not modify
the main localization catalog, project file, CI, AppSession or composition root.
