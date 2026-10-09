# Merchant service date and time selection

## Requirement and gap

P086 / PA10 in the supplied consolidated construction document explicitly lists `onServiceDateChange`, `openServiceTime` and `onServiceTimeConfirm`. The real merchant game-node page offers a service-date control and a combined, validated time-range editor. The native ready-station form only exposed two full civil-time text fields.

A native calendar and hour/minute selector now supplements those existing fields. It reuses `MerchantStationCommand.validTime`, `MerchantStoreHours.clock`, the existing ready command, and ordinary SwiftUI controls. No service, framework, API, permission, schedule rule or production grant is added.

## Interaction and compatibility

- Open creates an independent local editor. Cancel or dismissal does not write either existing source string.
- A recognized same-day source pair initializes the date and both times exactly. Existing off-five-minute values remain selectable and are never rounded on open. New minute choices follow the source's five-minute step.
- Blank/unrepresentable times begin at the source component's zero/zero proposal, which is invalid until the user explicitly chooses a later end. An unrepresentable existing pair remains untouched and is clearly described as being replaced only on Apply.
- The calendar's Date is only a fixed-Gregorian, fixed-zone carrier for year/month/day. Service hours never pass through Date conversion. The phone's zone is used solely for a new calendar proposal when no representable source pair exists, not to reinterpret an existing value or establish a service timezone.
- Apply requires a valid day and strictly later end on that same day. It rechecks account/read scope, activity/node/revision, current snapshot including observation identity, original text pair, busy/lock/review state, and validity before assigning both fields synchronously. Identical values do not mark the form dirty.
- Parent raw-text controls remain available and unchanged. Historical cross-day or otherwise unrepresentable values are not silently migrated, and this selector does not narrow the existing ready-request contract.
- The resulting values are local draft fields only. Existing frozen review, fresh preflight, unknown-result journal and production gates still control submission. Applying the picker does not make a station ready or save it remotely.

## Source

Private source ref `liboyang42-cpu/chengyin@ce61c0bbace743ff835cb297ef41c89b52181636`:

- `chengyinhub-xcx/pages/merchant/game-node/index.js`: `splitServiceDateTime`, `openServiceTime`, `onServiceTimeConfirm`, and `submitReady` retain a date with two clock values and submit the same existing fields.
- `chengyinhub-xcx/pages/merchant/game-node/index.wxml`: service date and time controls; `cy-time-range` uses `minute-step=5` without cross-day allowance.
- `chengyinhub-xcx/pages/merchant/components/cy/time-range/index.js`, blob `d1c417bc4bacb406aa5b56df9c5302db06501487`: minute step, zero/zero initialization, ordered-window validation and cancellation without emitting a value. Unlike its internal snapping, this native increment preserves preexisting off-step values as explicitly required in the task.

No private-source files are copied into the native increment. The supplied document file is pinned in the artifact manifest; its cover says edition 8 although the task handoff calls it v9.

## Integration and limits

This delta starts from the preceding optional-pause result tree `cd528e0aaff903291502eea2c6165af146e32452`, not directly from 73e. Apply the pause increment first, then this one. The only existing product edit is `App/MerchantContentEditor.swift`; all pause code, request validators, services, coordinators and protected integration paths are retained.

Root should add the ten unique entries in `Resources/MerchantStationServiceTimeLocalizations.fragment.json` and regenerate the project. No shared catalog/project/CI files or UI methods/timing estimates are changed here.

Twelve Core tests are authored for exact civil-string roundtrip, off-step preservation, source-zero proposals, ordering, leap days, cancellation, Gregorian date carriers, timezone-independent existing values and unchanged legacy request support. Seven focused source checks and supplementary parsing of four Swift files are run locally. Swift/Core/AppUnit/UI, Apple calendar behavior/accessibility, aggregate and live-backend acceptance remain unrun for the consolidated stage.
