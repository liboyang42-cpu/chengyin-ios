# CI138 remaining editor driver candidates

## Result

Two isolated XCTest driver repairs are ready for review. No App/Core, shared UI
helper, runner, workflow, old duration profile, historical planner contract, root
integration directory or other worker directory was changed. The candidate is
not integrated and is not Apple acceptance evidence.

- UI49: call the existing strict root-Form name reveal before each of the two
  existing five-second name assertions. Both maximum-text Chinese launches stay
  intact, including unknown-upload reopen/no resend and the separate default-off
  local-audio edit/remove journey.
- UI78: move each existing reveal before its existing five-second existence wait
  in the local tap/value helpers. Lazy review/receipt rows can materialize before
  the assertion. Maximum 70 swipes, fixed-button bypass, unique/enabled/hittable/
  in-window checks, exact UTF-8 assertions and the full recovery journey remain.
- UI55: no fix submitted. Its observed failure is earlier than gap scrolling:
  the chapter tap did not establish a Chapter foreground destination. Existing
  gap-direction work cannot be used as evidence that this case is fixed.

## Evidence inspected

Exact commit: 4bf6667f8c5d9d2d59a8063d7d54eaef7a338865.
Run: https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/37792301124

Actual failure PNG pixels and logs were inspected. Evidence root:
`../ci138-new-failures-triage-20261008-1732/evidence/`.

| Case | Job | Actual PNG |
| --- | --- | --- |
| UI49 | 113373677318 | CI138-UI49-screenshot/014F7890-90FE-4A29-8AA6-5863E2F7D72D.png |
| UI78 | 113373682900 | CI138-11567242886/E33F13EC-4B97-42E1-8676-05779D4BBE43.png |
| UI55 | 113373676842 | CI138-11566308778/F72CA781-B032-4DEB-A49A-6DC01933DED8.png |

UI49's first launch has large Chinese fixture controls and a large notice above
form fields. The original method never calls the already-available strict Form
reveal before its name wait. It failed before audio editing began. The second
launch uses the same maximum-text environment and must use the same readiness
boundary; patching only launch one would leave the repeated failure mechanism.

UI78 taps Review at t=27.79s, then starts the confirmation existence wait at
29.15s. At t=35.34s it fails in tap line 17. No reveal gesture occurred for that
confirmation. Actual pixels show Review route's top content and a long summary.
The current implementation waits for a lazy offscreen row before reaching the
code intended to reveal it. The value helper has the same local ordering defect;
its existing reveal is reordered too, without adding a new call or timeout.

## UI55: known facts, uncertainty and the smallest next evidence

The AlbumFirst journey launches English/large text, saves, reads the exact
synthetic chapter ID, and reveals that chapter button. Log times:

- t=41.79s: target chapter exists after three downward reveal gestures.
- t=42.10s: original 5s existence wait begins.
- t=44.27s: original enabled/hittable expectation evaluates.
- t=44.49s: uniqueness check; t=44.59s: window-frame check.
- t=44.73s: exactly one chapter tap.
- t=45.81s: next reveal still reads the Route editor navigation bar.
- t=46.16s onward: gap target absent; topward reveal begins in root editor.
- t=78.26s: gap reveal assertion fails. Screenshot and AX still show Route editor.

The log does not print chapter frame/activation geometry at the moment of the
tap. It does not establish a Chapter screen, a later pop, an intercepted tap,
an overlay hit, or a broken product NavigationLink. None is asserted as a cause.

There is a source-backed viewport hazard worth testing, not a proven cause:
`ProjectEditView` places Save/Review in `.safeAreaInset(edge: .bottom)` rather than
Toolbar. `revealFixtureElement` excludes Toolbars but not these inset controls.
The failure AX lists Save/Review at y=823, while a 912-point app frame allows a
generic viewport bottom near y=872. A chapter row in that strip can satisfy the
current window-frame check. A strict root Form target helper would prevent this,
but evidence does not show that this particular tap was in that strip.

Smallest diagnostic proposal for the next targeted Apple run: record the chapter
frame, root Form frame, Save/Review frames, and foreground navigation action
before the existing single tap; immediately record Chapter/root foreground
state after the tap. Preserve the existing waits/gesture bound and do not retap.
Only after this evidence should a chapter-scoped inset-aware reveal or a product
navigation correction be selected. No diagnostic or speculative product change
is included in this two-file package.

## Cost and integration contract

UI49 adds two calls to the exact current275 `revealProjectEditorNameInForm`
implementation in `ProjectEditFlowTests.swift`. Per call: maximum 10 gestures,
11 viewport evaluations, 1s query-phase plus 2s gesture/settle allowance per
slot, and two 2s initial AX lookups. This follows the existing current275
source-bound model: 11*(1+2)+2*2 = 37s, rounded up to 40s. Whole-method increment
is 2*40 = 80s. These are unmeasured engineering allowances, not measured runtime
or a guaranteed wall-clock bound. The original complete-method floor is kept;
the effective prior was independently confirmed as 900s by the passing
current275 weight chain; the candidate is 980s and needs one exact source-bound
current-method exception.
The historical floor/profile must not be edited or discounted.

UI78 introduces zero reveal/wait/action calls and changes no cap. Its order-only
increment is zero; retain its existing complete-method cost. Do not treat the
failed 37.064s CI elapsed time as a successful journey duration.

`tools/remaining_editor_drivers_contract.json` binds all before/after bytes,
precise replacement hunks, the helper dependency, preserved baseline source
inventory and costs. `remaining_editor_drivers_inverse.py` rejects changed,
missing, duplicated or unowned source and restores exact current275 bytes.
The editor must admit these exact new bytes in its next layer, apply this
inverse before the old planner, and charge the two new helper calls exactly
once. This package intentionally does not relax or rewrite the old runner.

## Validation

- 8 isolated preservation/inverse/cost tests passed.
- 8 existing native audio source contracts passed in a separate copied overlay.
- 7 existing approved review-request source contracts passed in that overlay.
- Swift compiler, Xcode build and simulator execution: NOT_RUN; unavailable here.
- The copied validation source is disposable local evidence, not the deliverable.
