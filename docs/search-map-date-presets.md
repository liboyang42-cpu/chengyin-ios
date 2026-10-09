# P101 map date shortcuts

## Verified gap and source meaning

Mini-program map search exposes Today and Tomorrow; the native map filter sheet previously required typing both dates. This narrow slice adds the two shortcuts only to the city/map filter sheet. Manual dates, the existing range validation and Apply/Cancel/Reset remain available. Global-search shortcuts are not added.

Read-only source baseline: `liboyang42-cpu/chengyin` at `ce61c0bbace743ff835cb297ef41c89b52181636`:

- `chengyinhub-xcx/pages/searchmap/index.js`, blob `eb6b2c97de1023b4b5407c51c5d49512639b4c36`: `selectDate` resolves local Gregorian Today/Tomorrow and writes equal concrete bounds; `searchFilter` consumes the bounds. `getList` applies `discoverSearch.filterRows` locally and explicitly omits unsupported server date parameters.
- `chengyinhub-xcx/pages/searchmap/index.wxml`, blob `731e900ef0b7d3970d723ff95576c5bccd7377f5`: date choices and custom-range controls.
- `chengyinhub-xcx/utils/discover-search.js`, blob `29f262eedc7f4332b0564b243bf5d314e175fc22`: `matchesFilters` compares the supplied activity start-date YYYY-MM-DD prefix inclusively. Missing dates remain visible. This is a source-calendar-day filter, not an instant/time-zone conversion or date-range overlap test.

Local evidence files were checked against the ce61 manifest's Git blob hashes. Native `GlobalSearchQuery.matches` and `SearchMapService.cityActivityPage` already implement the same start-day semantics. Neither is changed. The master migration list identifies this screen as P101 with PA04 map/session acceptance; this increment does not establish complete P101 or W13–W15 parity.

## Shipping behavior

`SearchMapDateFilterDraft` is a value held only in the sheet. On an explicit shortcut tap it resolves the phone's current time zone using a Gregorian calendar and calendar-day addition, including DST. It does not use a project-deadline time zone or add 86,400 seconds. Both text fields display the concrete result.

Apply validates and returns a copy of the existing query with those concrete bounds. Cancel discards the sheet draft. Reset clears the draft through the existing reset action. Reopening, pagination and same-query refresh do not evaluate Today/Tomorrow again. The bilingual explanation identifies phone-date selection, fixed bounds and the source start-day/missing-date behavior.

The existing explorer observes the applied query and invalidates old requests. Query, session, manual-area revision and cancellation fences, retained-results warnings, categories, tag/role/sort, price semantics and routing are unchanged. There are no new request fields, endpoints, location prompts, map activation, coordinate conversions, storage or automatic reloads.

## Candidate integration and verification

The candidate adds `Resources/SearchMapDatePresetLocalizations.fragment.json`; the parent integration should merge its three entries into the main catalog and regenerate the Xcode project. No UI test methods or classes are added or modified, so UI shard budgets are unchanged. The hosted AppUnit tests exercise the actual shipping helper and existing refresh/pagination query fence.

Authored: eight Core XCTest cases and four app-hosted XCTest cases. Month/year/leap, spring/fall DST, cross-phone-zone selection, source day-prefix semantics, validation, draft cancellation, fixed applied bounds and query/session/area retirement are covered.

Python source assertions and supplementary Tree-sitter parsing are static evidence only. Swift compilation, Apple SDK typechecking, Core/AppUnit XCTest execution, simulator/device UI, VoiceOver and Dynamic Type are NOT_RUN in this Linux workspace. No backend deployment, production grant, source publication or user-computer action is part of this candidate.

Local candidate results: 47 focused search-map Python contracts ran, 46 passed and one optional external-source comparison skipped. The map module structural checker passed 17 assertions. All four changed/new Swift files passed the pinned supplementary Tree-sitter parser without recovery nodes. Whitespace checks passed. Full repository aggregate and generated catalog/project verification are deferred to parent integration.
