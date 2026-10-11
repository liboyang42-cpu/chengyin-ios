# P045 current and ended activity browsing

## Independent scope and evidence

- Real baseline: `96d727404a966cd3b3d2437c79449046beda560f`.
- No overlay dependency. The calendar implementation is already committed in this baseline. This slice extends its existing activity-list mode without changing the month calendar or depending on community/report patches.
- All seven earlier output packages remain sealed and unchanged.
- Master P045 (lines 1652–1655): `loadTopics`, `goTopic`, activity view switching.
- Exact Mini revision: `f859cd6e2618f618a53f5cd33949259828e86313`.
- Detail JS 293–319: source status, positive-only statistics, product category and card decoration. JS 344–350: current/ended grouping. JS 1959–1979: accepted read, `endDate` comparison and grouping.
- Detail WXML 190–246: cover, status, name, time, address, category, real signup/station/mileage values and separate ended section.
- Exact datetime helper: `utils/datetime.js`, blob `2163e57af3d7d8cc47b879970a2e96d3c4371ed7`. The stored evidence copy matches this Git blob.

The baseline already supported list/calendar switching but its list only showed names and start dates. This slice completes the source-backed current/ended activity browsing projection. Public member search was not invented: P045 public members have no Mini search event, and the separate native CRM search/filter is already wired.

## Implemented flow

Opening the existing club activity/calendar entry now shows complete activity cards in list mode:

- Current/upcoming and ended groups, preserving source order inside each group. The ended section is absent when empty.
- Recruiting, in-progress and ended status from the source's date comparison, not guessed audit or publication fields.
- Product category from `productType`, falling back to `mode` only when the current field is absent/null.
- Existing cover renderer, title, China-time start display, source address and positive source signup/station/mileage statistics.
- Exact accepted-topic navigation through the existing destination. A rendered old row cannot acquire a newer read's authority.

Unknown, invalid, zero and negative source statistics are omitted; no fake zero or total is added. Mileage uses the source's one-decimal rounding. A positive source distance that rounds to zero remains a measured rounded value, not an unknown value. Missing title/date uses existing truthful fallback text. Invalid date text remains visible as source text rather than being silently converted.

Month/date browsing, its start-date-only projection, event destination factory, refresh/retry, access preflight, empty identifier and topic identifiers remain in place. Cards use an adaptive stats layout for larger text. Dates are shown in China Standard Time with a visible timezone/status-refresh note.

## Time and authority

For comparisons, bare server timestamps and date-only strings are fixed UTC+8. Explicit ISO offsets keep their absolute instant; accepted ten-digit seconds/thirteen-digit milliseconds are not interpreted in the device timezone. Real Gregorian day/month/hour/minute/second and offset values are validated. The verified helper ignores fractions in bare timestamps and retains millisecond precision in offset ISO strings; the new parser mirrors this behavior, including proleptic Gregorian year 0000.

`end > 0 && end < now` marks an event ended. Otherwise a valid nonzero `start <= now` is in progress; remaining rows retain the source's recruiting label. These are informational source labels, not enrollment eligibility or grants.

One existing authorized `.topics` read now produces both the unchanged calendar projection and the rich list. The comparison clock is sampled after the accepted response. Refresh invalidates both projections; errors and late/stale replies cannot leave one projection claiming a newer read than the other. The source account/epoch, viewer revision, access-object identity, authorization generation and snapshot generation remain authoritative. No endpoint, read permission, write capability or production `AppSession` construction changes.

## Focused verification

Executed on the current computer:

- Fourteen narrow source/static assertions passed.
- Exact Mini `loadTopics` request, grouped ordering, status boundaries, category precedence, unknown/positive stats and error clearing passed with requests stubbed.
- Twelve exact datetime-helper cases passed, including timezone equivalence, date-only, fractional precision, historical Gregorian dates and invalid date rejection.
- Exact datetime blob integrity passed.
- Pinned Tree-sitter parsed five changed/new Swift files with zero recovery diagnostics.
- Whitespace and full before/after patch/hash reconstruction passed, including reverse-apply check.
- All seven prior sealed patch hashes were rechecked unchanged.

Authored but NOT RUN: twelve Core cases for parser/status/grouping/category/statistics/metadata/authorization coherence, and six AppUnit read cases for one-read dual projection, post-response clock capture, failure/retry, latest-wins responses and account/epoch/authority/suspension retirement.

Swift compilation/typechecking, all 18 Swift tests, simulator/device/UI/VoiceOver and real backend acceptance were not run. Swift and Xcode are absent on this computer. Source/static/syntax checks are not native execution.

## Integration

Register the two new sources and two new test files, then merge the twelve-key bilingual fragment through the central owner. No PBX, total catalog, CI, shared fixture, `AppSession`, service contract, governance/public-profile implementation or prior output package changed.

Native acceptance: current/ended group order, status at exact start/end boundaries, UTC/non-China device zones, optional stats and missing dates, source cover failure behavior, larger text/VoiceOver, exact topic open/back, list/month switching, refresh/error retry and stale row/account/role retirement. The existing reviewed activity read configuration remains required; this slice performs no live read or sensitive write during development.
