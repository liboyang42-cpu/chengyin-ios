# Optional Gregorian map-filter date wheels

## Source and scope

The retained mini-program `pages/searchmap/index.js` defines 81 years from 1970 through 2050, twelve months, and Gregorian month lengths. `openDatePicker` prefers the selected field, then the start date when opening an empty end field, then the phone's current day. `onDatePickerChange` clamps day when year/month changes. `cancelDatePicker` hides the nested sheet without changing either field. `confirmDatePicker` rejects an inverted range before copying one date. `pages/searchmap/index.wxml` mounts this inside `cy-date-sheet` using separate year/month/day wheels.

This native increment adds an optional SwiftUI sheet composed of three system wheel Pickers. Existing manual date fields, field identifiers, Today/Tomorrow controls, price/category/city options, Cancel, Apply, and Reset remain. Selected wheel components are Gregorian civil dates; there is no conversion to UTC or a deadline instant. Only the empty/invalid-value fallback reads the current time in the phone's time zone. A device calendar or locale cannot turn the stored value into a Buddhist/Islamic year or non-ASCII digits. Locale controls UI labels through the existing app localization mechanism.

The picker accepts years 1970–2050 inclusive. Valid manually entered years outside that range remain supported by the existing filter; opening the picker clamps the displayed year and then the day, without modifying the manual field until Confirm. Opening End prefers a valid end value, then a valid start value, then the phone day; the same clamp applies to each. A start bound above 2050 or an end bound below 1970 can make a wheel selection impossible to confirm without changing/clearing the manual bound, and the existing manual fields remain available.

Native initialization requires a real Gregorian date. The mini-program's regex-only validity check also accepts malformed days; that accidental normalization is not copied. An invalid other manual field remains available for correction and the existing Apply validation rejects it. Whitespace trimming matches existing native Apply behavior.

## State boundaries

1. Opening a picker copies values from the outer filter draft into a new picker draft.
2. Scrolling a wheel only changes that picker draft. Month/year changes clamp day safely.
3. Cancel or interactive dismissal discards the picker draft.
4. Confirm checks order against the other valid outer-draft bound. Failure keeps the picker open and changes no outer state. Success updates only that one field in the outer filter draft.
5. Cancel on the outer filter discards confirmed picker edits as it discards manual edits.
6. Apply uses the unchanged query validation and callbacks. No search, refresh, location request, provider operation, or persistent write is triggered by opening or confirming a picker.
7. Reset retains the existing keyword-preserving, draft-local behavior. Reopening an empty End picker then uses the phone day unless Start was edited first.

## Integration

- Merge the eight entries in `Resources/SearchMapDatePickerLocalizations.fragment.json` into `Resources/Localizable.xcstrings` under `strings`, checking for collisions. The fragment is a handoff artifact and is not itself a compiled string catalog.
- Run `python3 tools/generate_project.py` in the integrating checkout to add the new Core/app-unit source paths to the app and test targets. This increment deliberately excludes generated project files and central-catalog modifications.
- Run `python3 tools/check_search_map_date_picker.py`, `python3 tools/check_search_map.py`, and `python3 tools/check_scaffold.py` after integration. Supply `--baseline PATH` to the focused checker when the unchanged fifth snapshot is available; supply `--mini-program PATH` for the retained searchmap JavaScript evidence.
- Run the approved Apple toolchain's Swift package tests, app-hosted unit tests, unsigned app builds, and existing map-filter UI coverage. Preserve the current UI method inventory and CI shard/cost binding; this increment adds no XCUITest class or methods.

## Authored tests and verification status

Twelve Core test methods cover selection precedence, strict date validation, picker/manual year bounds, month-end/leap-year clamping, defensive extreme wheel values, local midnight/year boundaries, spring/fall DST, skipped civil dates, Gregorian/ASCII formatting across locale-created Buddhist-calendar instants, both order directions and equality, out-of-range other bounds, and invalid manual-field preservation.

Six app-hosted unit test methods cover the value-state lifecycle for wheel Cancel/reopen, Confirm then outer Cancel, Apply/reopen and unchanged non-date filters, Reset, preset/manual/picker interoperability, and failed Confirm correction. They exercise the shipping state model; actual SwiftUI dismissal, callbacks, hit targets and accessibility still require the UI acceptance below.

Local structural/localization checks and the independent Gregorian oracle are supplementary only. Tree-sitter can check parsing only. Swift execution, Apple type checking/builds, XCUITest, VoiceOver, visual review, and physical-device acceptance are **NOT_RUN** in the cloud Linux workspace. No live provider/GPS/private production acceptance is claimed.

## Pending Apple UI acceptance

Use the existing offline search-map fixture, first global search and then city/nearby. Confirm the map remains opt-in and no provider/location permission appears.

1. Open Filters and verify the existing Start/End manual fields and `searchMap.filter.start` / `searchMap.filter.end` identifiers remain. Tap each optional picker button. Verify the proper localized title, current YYYY-MM-DD value, and independently adjustable year/month/day wheels.
2. With empty dates, compare the initial picker day with the phone in UTC, America/Los_Angeles, Asia/Shanghai, and Pacific/Kiritimati near midnight. End must instead initialize from a valid Start, and a valid End must take precedence. Opening/cancelling must not fill empty fields.
3. Start at January 31; change to February in 2028 and 2027, then April. Expect 29, 28, and at most 30 days. Select February 29, 2028 and change the year to 2027. Verify February 28 stays selected, with no unavailable row or crash. Check year 2000's leap day.
4. Try first/last wheel years 1970 and 2050. Manually enter 1968-02-29 and 2052-02-29, open the picker, and verify 1970-02-28 / 2050-02-28 without a manual-field change until Confirm. Manual Apply outside the picker range must retain the previous behavior.
5. Edit wheel values, Cancel, and reopen; then repeat with interactive dismissal. Both must restore the outer draft's prior field. Cancel on the outer filter after a successful picker Confirm must restore the last applied query when reopened.
6. Confirm a selected start after the valid end, then an end before the valid start. Verify a localized error and an open picker with both outer fields unchanged. Correct the selected value and confirm. Equal bounds must work. Repeat with whitespace around manual bounds and with invalid manual text, verifying existing Apply validation remains reachable.
7. Confirm valid selections, Apply, reopen, and repeat reads/refresh. The concrete dates must not drift at midnight, across phone time-zone changes, or across spring/fall DST. Select 2011-12-30 while using Pacific/Apia; the civil date must remain selectable.
8. In city filters, use Today/Tomorrow, then open both pickers; their initial dates must match the preset. Change one through a wheel, then edit manually, then choose a preset again. Check each path and Reset followed by Cancel versus Reset followed by Apply. Non-date filters and keyword semantics must remain unchanged.
9. In English and Simplified Chinese, verify translated titles, labels, explanation, error, Cancel and Confirm with no localization keys visible. Repeat under Thai Buddhist and Arabic-calendar device preferences: storage and displayed ISO summary stay Gregorian/ASCII while normal app localization still works.
10. Check small and large iPhones, light/dark appearance, Reduce Motion, largest accessibility text, and VoiceOver. At accessibility sizes wheels must stack vertically and be reachable by scrolling. Verify year/month/day labels, selected values, error announcement/readability, accessible Confirm/Cancel, non-overlapping wheel hit areas, and existing form controls after dismissal.
11. Open/close both pickers repeatedly, dismiss/reopen the filter, navigate away/back, and switch fixture account while the surrounding screen is available. Verify no stale picker selection leaks into a new filter instance and the original map/query scope safeguards remain intact.

Record exact Apple build/test revision and results. Do not label authored tests, static passes, or this checklist as completed runtime acceptance.
