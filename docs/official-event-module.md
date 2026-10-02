# Official events: isolated read-only native slice

## Delivery boundary

Initially staged in an isolated module and now additively integrated into the current native project on 2026-10-01. The integration preserves all prior modules, scoped-storage and CNAccountSessionService. The steps below document the applied wiring; do not reapply them blindly. No Flutter source, backend, live configuration, remote repository or CI was changed.

This is source-contract implementation, not live endpoint verification or completed page parity. Endpoint configuration and approval registries stay empty.

## Implemented source-backed reads

| Source | Native support |
|---|---|
| `official_events_page.dart` and `activity_status.dart` | Distinct official-event browser. Public status buckets: live = 2/3, upcoming = 1, ended >= 5. Case-insensitive local title/subtitle/city search. Positive ID/nonblank title filtering and duplicate removal. Joined events use an independent private request |
| `official_event_detail_page.dart` and `official_event.dart` | Fresh detail, source artwork through shared native image card, story, dates, city, reported participant count, V2 missions, server-reported progress/eligibility, collective progress and only configured rewards. Source CTA precedence is a read-only explanation, never a write button |
| `official_mine_page.dart` | Private publisher history, separate ordinary publisher-permission denial, event navigation, notice reach distinct from reads/clicks, owner-checked broadcast statistics preserving unknown scalar fields |
| `official_inbox_page.dart` | Private OFFICIAL/MERCHANT/CLUB invitation records, status from `status` (never `state`), role and current state; no accept/decline/withdraw buttons |

Service GET allowlist:

- `/api/official/events` with optional city query
- `/api/official/events/{id}`
- `/api/official/my-events`
- `/api/official/v2/party-inbox`
- `/api/official/can-publish`
- `/api/official/my-published`
- `/api/official/broadcast/{id}/stats`

All reads validate HTTP and business code before decoding. Raw source Authorization token convention is preserved. Guests never send a token; private guest reads return the login state without sending a request. Guest can-publish is locally false. This does not grant publisher authorization: `my-published` and stats still rely on server permission/ownership. A stats “notification not found” response means unavailable to the account; the UI does not assert deletion.

## Copy the additive source files

Copy only:

- `Core/OfficialEventContracts.swift`
- `Core/OfficialEventService.swift`
- `Core/OfficialEventReading.swift`
- `Core/OfficialEventSyntheticFixtures.swift`
- All five `App/Official*.swift` files
- `Tests/CoreTests/OfficialEventTests.swift`
- `Tests/AppUITests/OfficialEventFlowTests.swift`

The existing package automatically includes added Core and CoreTests sources. The app project generator automatically includes App/Core and AppUITests files. No Package.swift edit is needed. The native slice depends only on existing APIConfiguration/APIError, HTTPTransport, AuthRequestBuilder, AppLocalizedString, QuestifyImageEntityCard/QuestifyCardArtwork/QuestifyCardButtonStyle/questifyCardListRow, and the existing failure screenshot helper.

## Add AppSession wiring without replacing current logic

Inside the current AppSession class add:

```swift
private let officialEventService: OfficialEventService?
private var currentOfficialContext: OfficialReadContext {
    if let account, let token,
       let context = try? OfficialReadContext(accountID: account.id,
                                              epoch: gate.currentStamp, token: token) {
        return context
    }
    return OfficialReadContext(guestEpoch: gate.currentStamp)
}
lazy var officialEventReader = OfficialSessionReader(
    service: officialEventService,
    currentContext: { [weak self] in
        self?.currentOfficialContext ?? OfficialReadContext(guestEpoch: 0)
    },
    onUnauthorized: { [weak self] captured in
        guard let self, self.currentOfficialContext == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized,
                              stamp: captured.epoch, credential: self.token)
    }
)
```

In the existing approved configuration branch, using that branch's existing configuration and transport, add:

```swift
officialEventService = OfficialEventService(configuration: configuration, transport: transport)
```

In the existing unconfigured branch, add `officialEventService = nil`. Keep all other assignments, capability gates, CN protected-session handling, regional vault selection and auth behavior intact. Do not add any default base URL or approve a backend.

IMPORTANT: every account change, token rotation, logout, and guest/login/guest transition must advance the session epoch and publish a host redraw. The reader captures full context including the private token, and also uses an opaque UUID scope. The public guest context includes epoch deliberately; an old public request may contain personalized fields after a guest/account transition and must be discarded. Keep credentials out of navigation, task IDs, analytics and logs. The onUnauthorized equality check must remain exact, including token; do not simplify it to account ID only.

## Mount a distinct official destination

Add an explicit `Official events` route/entry in the existing app navigation, e.g. an additional sheet from SessionHomeFeedView or a separate account navigation entry. Keep ActivityBrowser and topic routes unchanged: `/api/activity/list` lacks official status and is a different product.

```swift
.sheet(isPresented: $showsOfficialEvents) {
    OfficialEventsBrowserView(
        reader: session.officialEventReader,
        onClose: { showsOfficialEvents = false }
    )
    .id(session.officialEventReader.scope)
}
```

The owning view must observe AppSession. Reading `.scope` without observing session changes is insufficient. Reset the sheet and private navigation on the same session scope changes as the existing home-feed pattern. An optional `onLogin` callback can present the existing authorized login flow; omit it if the current host has no supported login presentation. The screen still gives honest login-required copy and never silently starts authentication.

OfficialEventsBrowserView owns its NavigationStack; do not nest it inside another stack. Detail, published, inbox and stats views do not own a stack and may be mounted in an existing one. Publisher history is shown from the browser only after can-publish returns true. The fixture can enter denied states directly for tests.

## Localization merge

`localization.json` is an xcstrings-shaped object containing 101 new `official.*` keys, each with English and Simplified Chinese. Merge its `strings` dictionary into the existing `Resources/Localizable.xcstrings`; preserve all other catalog values and reject any unexpected conflicting key. Do not replace the catalog. Existing `action.close` is reused.

Example additive merge, run only by the integration owner:

```python
import json
from pathlib import Path
p = Path('Resources/Localizable.xcstrings')
dest = json.loads(p.read_text())
src = json.loads(Path('../native-official-events-new/localization.json').read_text())['strings']
for key, value in src.items():
    if key in dest['strings'] and dest['strings'][key] != value:
        raise ValueError(f'Conflicting localization: {key}')
dest['strings'].update(src)
p.write_text(json.dumps(dest, ensure_ascii=False, indent=2) + '\n')
```

## Fixture integration

In DEBUG `ModuleFixture` add `case officialEvents`, and in its root switch add:

```swift
case .officialEvents: OfficialFixtureHostView()
```

The fixture uses `--uitesting-module officialEvents`. Optional arguments:

- `--uitesting-official-scenario content|empty|failure|retry|guest|unauthorized|noPermission|unconfigured|unavailable|paused|ended|unknown`
- `--uitesting-official-destination browser|detail|inbox|published|stats`

All fixture rows are synthetic and contain no remote artwork, coordinates, account credentials or network service. Guest/account transition controls are DEBUG fixture-only. Existing `AccessibilityFixtureOptions` and `QuestifyReduceMotion` supply large-text/dark/Reduce Motion flags.

## Deliberately deferred or different

- No signup, complete, arrival verification, roam navigation/start, publishing, invitations, responses, withdrawals, broadcasts, click tracking, contact sharing, financial or backend writes
- `/api/official/invites` tracking read is API-only in the audited files and is not implemented here; it needs a separately scoped native destination and contract validation
- Official publish and broadcast composition sheets remain deferred
- No optimistic `signed`, eligibility or progress updates; no claim a reward/notification has been delivered
- No timer/countdown or inferred event timezone. Source text dates remain verbatim; numeric timestamps use local display formatting. Operational timezone must be independently verified before adding countdown/date arithmetic
- Participant avatars are decoded only; the preview does not fabricate an avatar stack
- Missing/invalid status stays unknown. Missing price stays “not provided”, never free. Empty/malformed reward JSON produces no promised reward
- The source hides search on Joined but retains a hidden keyword filter. Native Joined intentionally ignores the hidden keyword so records are not silently filtered
- Invalid envelope shapes fail closed rather than becoming a misleading empty success. Invalid/duplicate list identities are filtered; malformed element types fail the response rather than being silently treated as valid
- Read-only UI uses List's lazy rows, reusable full-bleed image cards, native navigation and menu picker, minimum 44-point controls, semantic labels, scalable text, and no independent continuous animations. Existing card motion obeys Reduce Motion. Device/VoiceOver/layout acceptance remains NOT_RUN

## Verification

See `verification.md`. After integration regenerate the project and run existing aggregate checks. Swift compilation and the 21 new XCTest + 10 UI test methods are authored, not executed in this Linux environment. No remote CI or network has been triggered.
