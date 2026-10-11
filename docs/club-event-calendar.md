# P045 club activity calendar

## Scope and source

This additive slice implements the existing `onEventViewChange` list/calendar action and its month controls and topic-detail navigation. It does not represent completion of the club detail page or the club domain.

- Native base: `53bbc93ea77bcb66a2ed1701e3e0ef8896d30e13`.
- Overall product document: P045, club detail, event index `onEventViewChange`, `onShiftEventMonth`, `goTopic`, `loadTopics`.
- Exact Mini revision: `f859cd6e2618f618a53f5cd33949259828e86313`.
- `chengyinhub-xcx/pages/club/detail/index.js`: 1922–2034; `/api/club/topics`, body `{ id: clubId }`; list/calendar switching, month shifting and calendar refresh.
- `chengyinhub-xcx/pages/club/detail/index.wxml`: 249–273; previous/next month, Monday-first cells and event `id` to `goTopic`.
- `chengyinhub-xcx/pages/club/utils/club-event-calendar.js`: exact Git blob `de54048b5285a492a3ca9411e899d75d4671c0ff`.
- Source unit test: exact blob `70898063549ea99261d3d8a105f29a558928fb27`.

The helper was read through the authorized connector at the exact blob. Private source copies and their test execution evidence remain outside this public repository.

## Delivered behavior

The ordinary club detail contains an activities link when its existing governance composition is present. The new screen reads the existing `.topics` adapter, which retains its current access/me preflight and signed-in boundary. It does not introduce a public/guest endpoint or broaden authority.

The same accepted response supplies both the list and calendar. The calendar starts on Monday and has exactly 42 cells. Multiple activities on a date remain distinct. Leading and trailing dates retain any matching activities. Month paging handles year and leap transitions; unsupported bounds are disabled. The initial month follows the device calendar date; each activity uses its source-written `startDate` prefix, without timezone conversion or inferred multi-day expansion.

The compact native calendar lets a user select a day and then open any activity on that day. Accessibility text sizes use a readable date-and-activity list for the same six-week window instead of squeezing long names into seven narrow columns. Missing or invalid dates stay in the activity list and a separate undated section. Missing names use localized fallback copy; no dates, counts, availability or registrations are invented.

Each navigation carries the source topic `id` into the existing `topicDestination`. A missing destination produces readable rows rather than dead buttons. The destination reader retains its own authorization.

## Response and navigation boundaries

- Snapshot requires the exact `.topics` operation, club scope and active permissions for that club.
- Invalid/duplicate IDs and contradictory optional club IDs fail closed.
- Each reload clears prior rows before dispatch; errors remain errors and have a retry path.
- Account, epoch, viewer revision, authority generation and access instance changes invalidate rows and routes.
- Request generations reject earlier overlapping responses. Cancellation/disappearance fences late success and failure.
- Covering the list for a detail disables queued selection; its immutable accepted snapshot keeps the valid detail alive. Stale destinations clear themselves rather than displaying a permanent blank page.
- No writes, new transports, dispatch capabilities or mutations are introduced.

## Focused checks

Executed in the current dot workspace:

- 79 focused static contracts: passed, including exact helper hash and exact Mini action/route evidence.
- Exact Mini helper unit tests: 3 passed. These validate the source oracle, not the Swift implementation.
- Supplementary Tree-sitter parse: 5 Swift files, 0 recovery diagnostics, pinned `tree-sitter==0.26.0` and `tree-sitter-swift==0.7.3`.
- Patch whitespace check: passed.

Authored: 10 pure Core tests and 9 app-hosted read-lifecycle tests. These cover leap days, year boundaries, unavailable dates, scope/ID errors, exact routes, account/epoch/authority changes, replacement readers, overlapping refreshes, cancellation, retry and covered-source behavior.

NOT RUN: Swift compilation/typechecking, the authored Swift tests, iOS simulator/UI/VoiceOver/large-text checks, real backend acceptance. This environment has no Swift or Apple SDK/Xcode toolchain. Static/source checks must not be reported as native runtime acceptance.

## Integration

See `club-event-calendar-registration.fragment.json` for the new sources and catalog fragment. No PBX project, aggregate localization catalog, workflow or existing fixture host was modified by this slice. The integrating owner should register the additions using the existing generator/catalog merge process and run the focused Apple tests before claiming native acceptance.
