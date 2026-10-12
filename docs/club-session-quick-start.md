# P045/P049 club session quick start

## Source and precise missing flow

Unique MASTER-v10 extracted text P045 lines1652–1655 (`onOpenClubSession`) and P049 lines1668–1671 (topic selection and series form). Mini revision `f859cd6e2618f618a53f5cd33949259828e86313`:
- detail.js2420–2425: owner-only current club → event-ops with `recurrence=ONCE`.
- detail.wxml462–463,761: owner-only “开一场”.
- event-ops.js45–56,411–426,493–532: name/date/origin labels, ONCE seed, existing manageable-topic POST.
- event-ops.js803ff: existing createSeries payload. Native retains original form and command protections.

The ordinary detail page had calendar/workspace entry but no direct owner → fresh topic choice → ONCE-seeded form flow. This packet adds that complete entry, selection, retry, cancel and return flow, rather than another form or calendar.

## Real route and authority

Exactly one new ClubDetail line after `club.calendar.open`. The child uses the supplied ordinary `ClubReading` and `ClubGovernanceContext`; no default callback or fixture-only reader. Owner/signed-in/configured/aligned identity is required. Fresh `clubDetail(id:)` must return the same club and owner, followed by `.eventTopics` using current clubID and existing `club:activity:manage` proof. Every selection repeats both reads; the chosen topicID must still exist in that response before opening the actual `ClubGovernanceCommandForm` with the same access/coordinator.

Only seed: `recurrenceType=ONCE`. Exact scope: current clubID plus selected topicID. No guessed lead, schedule, capacity, activityID, automatic review, dispatch or new write authority. Original form11–13 owns explicit lead selection, Shanghai scheduling, dirty/discard, review, target revalidation, authorization, unknown-outcome and receipt handling. ONCE is an initial choice, not an override preventing users changing recurrence in that existing form.

## Meaning of fields

The eventTopics reader already validates an array, object rows, unique positive IDs. Projection additionally requires exact operation/scope and permission proof. Source order is retained. `row.clubId` identifies the topic's publisher, and can differ from current clubID for legitimate cooperative topics; it is never used to change target scope or filter these out. Missing origin is explicitly unknown. Trimmed nonblank names are displayed with exact topicID; missing names have a neutral label. Optional server start/end date strings remain verbatim; missing dates are omitted, never replaced with today or guessed ranges. No income, capacity, count or contact data is invented.

## Interruptions and return

Reader/access object, account/epoch, storage namespace, authorization generation, viewer revision, visibility and request generation fence accepted snapshots and ephemeral targets. Initial read has no target. Selection clears old results, double taps are suppressed synchronously, stale tasks cannot present, and malformed/failed refreshes do not retain a prior actionable list. Missing selected topics retain the fresh list for explicit reselection. Context changes/back/cancel retire the permit. The existing form handles dirty-close confirmation; no outer close bypass is added. On form dismissal the list re-reads; old targets are invalid. New sheet identity belongs to one accepted selection.

## Integration and boundaries

Base5dd3e53c1de104735b26d75811cb4ff46b2a340f plus two immutable dependency chains:11→12→13 (shared form) and17→18→20 (ClubDetail). START/registration fragment include each patch SHA and shared before/after SHA256; composite tree626c3f1501d1b47526081d361c7a8c827996f7a0. No earlier packet or shared form is modified. Central integration registers four Swift files/tests and thirteen localized keys from fragments.

This is a real entry wired to existing authorized readers and existing command form. It does not establish deployment/read capability availability, enable dormant createSeries grants, or claim production creation works. Missing ordinary governance composition or independently approved capabilities remain ordinary existing dependencies, not a new fallback gate or simulated success. P043/map6 stays canceled.

## Verification

Ten Core and fourteen App-unit tests authored, covering scope/origin/unknown values/permission, exact seed, fresh owner/topic recheck, topic removal, malformed response, retry, authority/namespace/revision/account changes, cancellation, late responses and return refresh. Exact Mini blobs and source-execution oracle, focused structural checks, existing governance contracts, Tree-sitter parsing and patch reconstruction are run separately. All24 Swift tests, native build/UI/runtime and real backend operations are NOT_RUN in this environment without Swift/Xcode. Passing static checks are not typechecking or Apple acceptance.
