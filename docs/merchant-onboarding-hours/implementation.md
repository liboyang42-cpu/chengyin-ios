# P065 onboarding business-hours recovery

Opening the business-hours editor now seeds the current draft's recognized days and exact clock minutes. Cancel and a no-op Apply preserve the original string, including a historical weekday ordering the shared parser can recognize. Unknown historical text remains visible and untouched; the proposed controls cannot replace it until the user explicitly edits and applies them. An empty new field can explicitly accept the existing all-week 10:00–22:00 default. New valid overnight hours contain the source-required next-day marker; zero-duration, invalid clock and empty-day selections cannot apply.

`MerchantOnboardingHours` now delegates parsing, weekday meaning, clock validation and output to existing `MerchantStoreHours`. The UI uses integer hour/minute selectors and never converts through Date, Calendar or a timezone. It does not infer a service timezone or change other date-display/deadline rules. The old private DatePicker sheet is replaced rather than left as a parallel path.

The sheet captures current onboarding identity, read revision and the whole original draft on opening. Apply rechecks those values, busy state, pending submission locks and confirmation absence. It writes only `businessTime` in the local draft. Reload, account change, another draft edit, Cancel or a prior Apply prevents a stale editor from applying. Sheet dismissal consumes and releases the editor. The existing form/photo/confirmation lifecycle remains intact. No license, identity gate, submission permission, upload or API route is changed.

## Evidence and exact scope

The same saved construction plan SHA-256 `eb23c8aefc22954bcd6f73ef800c32b763e7f8c4e3d4c68b0a0956756fd50133`, P065 paragraphs 1731–1734, lists open/confirm/dismiss/day/start/end hours events. The caller calls this saved file v9; its cover still says edition 8. The plan remains unchanged.

Private source `liboyang42-cpu/chengyin@ce61c0bbace743ff835cb297ef41c89b52181636`, `chengyinhub-xcx/pages/merchant/apply/index.js`, blob `daa4d23a7a17b8c171dd0734e82b4009317f7823`, lines 440–459 and 468–488: reopening uses current hours, at least one day is required, equal clocks are invalid, and an earlier end is explicitly marked as the next day. The existing application `businessTime` field and local `MerchantStoreHours` formatter provide the reused native contract. No private source is copied into the candidate and no live endpoint was called.

Only existing `App/MerchantOnboardingView.swift` and `Core/MerchantOnboardingContracts.swift` change, with new `App/MerchantOnboardingHoursEditor.swift`. The old Core overnight expectation is corrected from an unmarked earlier end to the verified next-day string. No UI test is changed, renamed or added. Three unique bilingual keys and the new App/AppUnit file registrations are left to central integration.

## Checks and storage

Five focused Python source checks and six affected-file Tree-sitter parses passed, plus exact-base replay and whitespace checks. Six new Core and seven AppUnit XCTest cases, together with the corrected old Core case, are authored but unrun. Apple compilation/runtime/UI/accessibility, full aggregate and live acceptance remain deferred. No previous feature suite was repeated.

Base tree `18b9c3d8d91f0e4aecba13993ac97e04cc70ce1e`, after featured clear. This candidate directly shares the frozen 73e Git object store, with 110 immutable incremental objects hard-linked from prior candidates to avoid the Git alternates nesting limit; source/worktree bytes were not overwritten. AppSession, Muse paths, certificates/licenses, services, coordinators, shared catalog/project, UI budgets and backend U2 remain unchanged.
