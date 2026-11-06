# Purchased installation history continuation

Baseline: 13c5be211e7e03e2f447e2e061840917fab9846b.

## Normal flow

Account purchased library → frozen purchased version detail → installation/history sheet → older installation receipts or additional destination metadata → selected installed receipt's existing protected-text reader → back to existing receipt list. This patch reuses all existing entries and readers. It does not enable an installation service, perform a purchase, execute a package, or publish a draft.

The baseline continuation method fetched both history and targets on every page and replaced each collection. A history continuation could reset destination selection/list, and a target continuation could replace receipt history with its first page. This is a source-level finding, not an observed production incident.

## Changes

- Continuation reads only the requested collection and appends results atomically. Identical duplicate IDs are deduplicated; a duplicate ID with different data rejects the entire page without partial append.
- History receipts remain tied to the exact purchased item. Existing protected-text entry validation remains in place.
- Only one continuation can be offered at a time. Pagination is visibly busy without dropping previous rows. Status reads cannot interrupt active pagination; an explicit full refresh can supersede it with a new action.
- Transient/malformed page failure preserves previous rows, selection, and the exact cursor for explicit retry. A terminal empty page retains old rows and removes the continuation.
- Existing service checks reject nondecreasing history cursors. The controller additionally rejects repeated/consumed cursors as defense in depth; target cursors must decrease. Cursor history resets on full refresh or closing. The cycle regression runs through the service and does not isolate the controller’s consumed-cursor check.
- Initial destination failure offers an explicit read refresh. The continuation button is outside the nonempty-target branch; the current wire contract independently rejects empty pages with a continuation cursor.
- Unauthorized/disabled/stale-session loading invalidates protected state. Old callbacks cannot update rows or clear a replacement request's loading state.

## Acceptance evidence

15 added regression test methods cover isolated continuation, duplicate handling, failure and exact retry, initial destination recovery, status/pagination interleaving, late callbacks, cursor cycles, unauthorized reads, empty terminal pages, and mutual exclusion. These are authored tests, not executed evidence.

Source/diff review and whitespace check only. Compilation, unit/UI test execution, real App tests, CI, package execution, deployment and release: NOT RUN. Requires runtime acceptance later, including real nested-sheet return behavior, which this patch does not claim to have tested.
