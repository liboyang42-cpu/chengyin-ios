# CI138 story reveal and editor-arrival repair candidate

This isolated package changes two helpers relative to the frozen current275
candidate. It is not integrated into the active UI planning layer and has not
been built or run on Apple. The current275 directory remains untouched.

## Verified failure causes

- UI46 AudioFirstGap and UI53 ImageMiddleGap entered Chapter, then exhausted 45
  topward reveal gestures while the lazy gap row was below the viewport. Both
  AX snapshots and actual failure PNGs show the top Chapter sections.
- UI57 GameEnd successfully returned to Route editor at its retained scroll
  position. The lazy name field was absent, making the former arrival oracle
  invalid. The root title, Chapters and Tickets are visible in actual pixels.
- UI58 GameFirst failed at initial fixed snapshot-probe readiness before any
  story interaction. Its later screenshot does not identify the failing
  predicate state. This candidate does not alter that path or increase waits.

## Exact changes and foreground semantics

1. Remove only `top: true` from MediaGapFlowSupport's existing gap tap. Its
   bounds, calls, timeout caps and assertions are otherwise identical.
2. Replace only the five-second editor-name wait in TemplateFlowSupport with
   one five-second predicate for the native Edit button scoped to the
   `Route editor` navigation bar: `exists == true AND hittable == true`.

The action's ancestry confirms the requested editor navigation bar; its native
hittability rejects a hidden old bar. The structural bar is not itself used as
the hit target, consistent with the existing FailureScreenshot helper's
documented distinction between navigation containers and native action leaves.
The fixture explicitly launches in English. Original arrived assertion,
timeout-only diagnostic, all snapshot/byte assertions, cancellation behavior,
back taps and the already-applied Template gap-direction repair are preserved.

## Complete added-operation accounting

| Operation | Before | After | Delta |
|---|---:|---:|---:|
| Launches per template journey | 1 | 1 | 0 |
| Back taps per journey | 3 | 3 | 0 |
| Arrival waiting stages per journey | 3 | 3 | 0 |
| Cap per arrival waiting stage | 5 s | 5 s | 0 |
| Total arrival explicit caps | 15 s | 15 s | 0 |
| Template reveal calls | 14 | 14 | 0 |
| Maximum swipes per template reveal | 10 | 10 | 0 |
| Media maximum swipes per reveal | 45 | 45 | 0 |
| Arrival predicate properties | exists | exists, hittable | +1 per evaluation |
| Explicit sleep/retry/new action stage | 0 | 0 | 0 |

The success path retains exactly one waiting boundary at each existing return.
The new predicate is inside that same five-second boundary; it is not appended
after an existence wait. There is one additional native hittability property
read per predicate evaluation. The existing unmeasured 117-second whole-method
overhead allowance explicitly includes AX queries outside reveal iterations.
Retaining it is an engineering assumption, not evidence that actual wall time
is unchanged. AX calls can overrun nominal timeout observations; this package
does not claim a measured or guaranteed upper bound.

Original full-method formulas remain:

- End: 90 launch + 355 explicit waits + 14 x 11 x 2 reveal allowance + 117
  whole-method overhead + 30 rounding reserve = 900 seconds.
- First/middle: 90 + 385 + 308 + 117 = 900 seconds.
- Media direction repair adds no operation or cap; existing 900-second floors
  stay intact.

No current or historical duration is reduced, and no failed elapsed duration is
treated as a successful observation. The editor must bind these exact new bytes
in its next current-source layer, using the supplied inverse to restore exact
current275 bytes before applying existing historical projections. Do not update
old historical hashes in place.

## Review package and validation

- `story-current275.patch`: two independent hunks, preserving existing template
  direction fix.
- `tools/story_reveal_arrival_contract.json`: exact before/after bytes, baseline
  UI source inventory, unchanged planning-file hashes and operation accounting.
- `tools/story_reveal_arrival_inverse.py`: fail-closed forward/inverse functions.
- `tools/test_story_reveal_arrival.py`: exact round trip, unknown-source rejection,
  assertion/journey/probe preservation, wait-stage/cap checks and frozen-base
  integrity checks.

These are source-level validations. Swift compilation, real foreground AX
behavior, media completion and exact-SHA Apple UI gates remain unverified.
