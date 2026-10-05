# Native activity registration form

## Scope

This local slice adds an interactive SwiftUI activity-registration sheet using the existing `RegistrationContracts`, `RegistrationService` protocol boundary and `RegistrationCoordinator`. None of those existing files is modified. The form supports native ticket selection, optional saved-participant autofill, editable name/mobile, points selection and quote refresh, nullable quote details, a separate immutable review step, retained-intent recovery UI, and an explicit status read for a known registration ID.

There is no endpoint/configuration creation, network invocation during development, live consent/create/payment operation, SDK integration, credential acquisition, log or persistent storage. Production order creation has no enabled policy case. DEBUG fixtures are entirely synthetic.

## Verified source contract

Paths below are relative to the retained Flutter repository, reviewed 2026-10-01:

- `lib/feature/activity/activity_detail_page.dart`, `_SignupSheetState` (around lines 1123–1870): first ticket default; default participant or first participant; saved original name/mobile as autofill; current editable fields, trimmed at submit; name required and mobile `^1\d{10}$`; quote on ticket/points change; consent before create
- This activity sheet does **not** offer email or a participate-date input. `ActivityApi.createRegistration` supports them for other callers, but native activity UI does not invent them. `RegistrationUIFormDraft.participantDetails` leaves both nil. Activity `startDate`/`endDate` are displayed as source strings, with no timezone/date inference
- `_requiresWaitlistOffer` gates a sold-out ticket on a verified active offer. This slice does not implement the waitlist reader/redemption flow and therefore blocks sold-out confirmation. It never fabricates an offer ID/token or infers one from inventory
- `FeeBreakdown` (around lines 2482–2636): quote amount, points, member and coupon deductions, nullable totals, points eligibility, and source `_formatMoney` helper. The native UI preserves unknown deduction amounts instead of replacing missing values with zero
- `lib/data/api/activity_api.dart`, `quote` / `createRegistration`: activity owner type 2, optional ticket, 0/1 points, signed quote, retained request ID, separate optional email/date and waitlist offer pair
- `lib/feature/legal/legal_docs.dart`: user agreement is versioned, but app privacy-policy body remains explicitly pending. A local checkbox cannot resolve that release gate
- `_attemptCheckout` calls `agreeSignupDataSharing(requestId)` before creating. Native form does not send that agreement or claim any server consent receipt exists
- `lib/data/models/activity.dart`, `MyRegistration`, `TicketState`, `RegistrationDetail`: registration 1 awaiting payment, 2 ready to use, 3 cancelled, 4 expired. Other/missing values remain unknown. Raw payment and verification codes remain separate; no settlement/refund facts are inferred
- `lib/feature/orders/payment_verifier.dart`, `classifyRegistrationStatus`: the source checks payment/registration 2 before failure-looking 3/4. The client evidence does not settle conflicting-field precedence against the authoritative server. This slice does **not** port that combined success classifier or polling loop

### Currency and regional gap

The activity source `_formatMoney` prefixes ticket price and `payAmount` with `¥`; quote/create wire data has no ISO currency field. That helper alone does not establish a reliable server currency contract for a US launch. Native listed price, quote total and create payable amount therefore display exact decimal values with **Currency unconfirmed**, without an inferred CNY/USD value. The explicitly named and documented `pointsDeductYuan`, `memberDiscountYuan` and `couponDeductYuan` fields display **CNY**. Number formatting follows the UI locale, but currency is never selected by locale, and amounts are never converted to USD.

The existing 11-digit mainland-mobile source validation remains intact. The form explicitly explains the current international-number limitation. A US launch requires an approved international-contact contract, currency/price contract, regional legal/consent copy and payment path; changing English strings alone does not satisfy these gates.

## Host integration API

`RegistrationSheetView` (main actor):

```swift
RegistrationSheetView(
    activity: detail,
    coordinator: stableCoordinator,
    participantReader: profileReader, // optional ProfileReading
    currentIdentity: { currentProfileIdentity }, // ProfileReadIdentity? with epoch
    quoteEnabled: false, // default; explicit true only with an approved injected service
    creationPolicy: .disabled, // default; no production-enabled case exists
    onReadback: { snapshot in /* refresh known-ID display if needed */ }
)
```

The sheet supplies its own `NavigationStack`; present it using `.sheet`. Root integration owns the activity-detail entry and authenticated-session wiring. Add the App/Core files via project regeneration and merge `registration-ui-localizations.json` into the existing bilingual string catalog. This module does not edit shared navigation, AppSession, catalog or project files.

Host requirements:

1. Retain the `RegistrationCoordinator` outside the sheet builder, for the lifetime of its unresolved flow. Reopening must receive that exact instance, not a newly constructed coordinator
2. Synchronize `setAccount(id:token:)` / `clearAccount()` on every authenticated session replacement, including same-account reauthentication; the UI never receives a token
3. Return a live `ProfileReadIdentity` whose epoch changes with session replacement, using the same identity as the participant reader. Ensure parent session changes cause the sheet body to reevaluate, so `.task(id: flow.identity)` resets the view-local form. An identity mismatch hides coordinator state and blocks all confirmation immediately
4. Do not reuse a coordinator for simultaneous unrelated sheets. A retained intent from another activity is shown as locked and is never silently selected/replaced
5. `onReadback` is invoked only after one successful, account-current, matching-ID status response. It is **not** a registration/payment completion callback
6. Root may inject `RegistrationService` into the existing coordinator. This slice does not configure it and `quoteEnabled` defaults false. The production sheet can be explored without activating create

The view-local form uses `RegistrationUIFlow` (Foundation-only) and publishes changes through a small ObservableObject adapter. `open()` performs no requests; the sheet then starts participant read and quote independently. A missing/slow/failed participant reader does not block manual entry or quote. A late default participant never overwrites manual edits. Selection changes clear the previous quote/review before another quote is requested. Every async result is checked against the captured identity and view generation.

## Creation and uncertainty rules

- `.disabled` is the only release policy. `.offlineFixture` exists only under `#if DEBUG` and is used by the explicit in-memory fixture host; never pass it to a network-backed coordinator
- The demo consent toggle only rehearses UI interaction. It sends no server consent and is not represented as legally effective agreement
- Review captures identity, exact ticket/points selection, signed quote and current contact values. Edits, selection changes, refresh, dismissal and session changes invalidate that review
- Confirmation rechecks the snapshot and policy immediately before delegating to the existing coordinator. The coordinator retains one immutable intent before first suspension and blocks repeated taps
- Timeout, cancellation, business/HTTP failure after dispatch or dismissal during create leaves the intent locked as unknown. There is no auto retry, new request ID, recreate, payment retry, cancel/refund request or background polling
- Missing `payParams`, a known zero amount, or receiving a create ID never renders success. A known ID exposes an explicit read; missing ID exposes the uncertainty warning and no guessed lookup
- Raw registration, payment and verification facts stay separate, including conflicting/future/null values. A known terminal-looking status does not unlock a new create
- Leaving the sheet clears local contact fields/participant rows and invalidates callbacks. It does not discard the session owner's submitted intent or claim server cancellation. The existing coordinator retains its original PII-containing intent in memory only, with no additional persistence or logs here
- Protected durable intent retention/restoration, server consent integration and unknown-ID reconciliation remain prerequisites for live creation. App restart is not recovery and must not be treated as permission to submit again

## Offline fixtures

`RegistrationFixtureScenario.selected(arguments:)` recognizes:

```
--uitesting-registration-fixture standard
```

Root can use the returned enum to present `RegistrationFixtureHostView(scenario:)` inside a DEBUG branch. Scenarios: `standard`, `noPaymentParameters`, `unknownAmounts`, `quoteError` (first quote fails, explicit refresh succeeds), `participantsError`, `createTimeout`, `readbackError`, `conflictingStatus`, `soldOut`, `disabled`.

The host preserves its coordinator when the sheet is closed/reopened. Fixture contact records, activity, account identity/token and opaque payment parameters are synthetic; there is no URL or transport path. `disabled` uses the production creation gate with otherwise interactive offline quoting. Three SwiftUI previews exercise standard, timeout and disabled scenarios.

Useful accessibility IDs: `registration.form.sheet`, `.name`, `.phone`, `.participantPicker`, `.ticketPicker`, `.usePoints`, `.refreshQuote`, `.total`, `.consent`, `.review`, `.creationDisabled`, `.readStatus`, `.statusSnapshot`, `.outcomeUnknown`, `.close`; host reopening uses `registration.fixture.open`.

## Verification

- Added 18 pure XCTest cases across `RegistrationUIFormTests` and `RegistrationUIFlowTests`: source validation and trimming, missing/zero money and currency, status labels, fail-closed creation, quote opt-in, nil tickets, ticket/points invalidation, preferred participant plus edited values, late participant races, participant failure, dismissal/PII clearing, same-account epoch replacement, consent and sold-out/incomplete quote gates, explicit review invalidation, timeout/reopen/no recreate, known-ID raw readback, dismissal during create and cross-activity locks
- Tests use synthetic local services and manually released continuations; no sockets, sleeps, live accounts, payment SDK or external actions
- Swift compiler/XCTest, Xcode compile, simulator UI, accessibility/Dynamic Type, physical device and live backend are **not run** in this worker because no Swift/Xcode toolchain is installed
- Offline structural validation passed in a temporary integration copy after merging the 73 bilingual keys and regenerating the project: 109 Swift source files, 725 keys, valid references/scheme and deterministic regeneration. This is not a Swift compile/runtime result; shared project/catalog files were not changed in the worktree
- All eight new files passed whitespace checks, localization JSON parses, and all registration UI/core localization keys have English/Simplified-Chinese entries. Project/catalog changes remain a root integration responsibility
