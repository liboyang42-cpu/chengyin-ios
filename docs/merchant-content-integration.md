# Merchant content integration

## Copy only the module files

Copy all `Core/MerchantContent*.swift` and `Core/MerchantStationContracts.swift` files (six Core files total), three App files, `Tests/CoreTests/MerchantContentContractTests.swift`, and `Tests/AppUITests/MerchantContentFlowTests.swift` into the corresponding target directories. Merge `Resources/MerchantContentLocalizations.fragment.json` into `Resources/Localizable.xcstrings`'s `strings` object, checking for conflicting keys. Keep the default live executor disabled.

Also copy the two tools and these docs if desired. `check_merchant_content.py` expects the sibling retained Flutter source at `../app-audit`; its location can be supplied by an integrator-specific wrapper if needed. Do not copy the disposable QA overlay path marker into the app or release bundle.

## Normal host wiring

Inside AppSession, a lazy service can read the existing approved regional configuration and create its own read-only URLSessionTransport. It must use the real account/epoch/credential and `storageScope.service`, not a locale or guessed merchant identity:

```swift
private var currentMerchantContentSession: MerchantContentSession? {
    guard let account, let token, let storageScope else { return nil }
    return try? MerchantContentSession(
        accountID: account.id,
        epoch: gate.currentStamp,
        storageScope: storageScope.service,
        token: token
    )
}
lazy var merchantContentService = MerchantContentService(
    configuration: regionalConfiguration?.apiConfiguration,
    transport: URLSessionTransport(),
    currentSession: { [weak self] in self?.currentMerchantContentSession },
    onUnauthorized: { [weak self] captured in
        guard let self, self.currentMerchantContentSession == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized,
                              stamp: captured.epoch, credential: self.token)
    }
)
```

No journal or test execution switch is passed to this factory. That keeps live mutations disabled before transport while allowing source reads when the existing regional/session gate is genuinely configured.

Add optional `contentService: (any MerchantContentServing)? = nil` to MerchantHomeView and forward it to its private workbench. Present `MerchantContentHomeView(service: contentService).id(contentService.scope)` from a “Projects & local content” link. Pass `session.merchantContentService` from AccountView. Existing merchant fixtures may omit the optional parameter.

For recruitment from a known recruiting route, pass the exact source topic ID to `MerchantContentHomeView(service:..., topicID:...)`, or push `MerchantContentDocumentView(service:..., query: .chapters(topicID:...))`. Do not use a project ID whose `bizType` is activity/template as a topic ID. The new hosted-project list already filters navigation to `bizType == "topic"` and sends `scope=MERCHANT` only on the source endpoint that accepts it.

## Cooperation supply bridge

An optional environment closure supplies the Cooperation module's view:

```swift
.environment(\.merchantContentSupplyDestination) { sourceContext in
    // sourceContext contains exact applicationID/chapterID/offerID,
    // known termsMode, canEnroll and canReconfirmOrPause.
    // Return an AnyView wrapping the existing Cooperation flow.
}
```

`CoopFlowOfferContext` in `CooperationFlowContracts.swift` expects `chapterID`, `TermsMode(rawValue:)` and optional `offerID`. The constructor throws on invalid IDs. Only use enrollment when `sourceContext.canEnroll` is true; do not infer terms from application JSON. Fetch Cooperation's own eligible perk templates for PERK mode before opening `CoopFlowOfferEditor(context:eligibleTemplates:)`. Its source filter is positive retail value and positive quota. REVSHARE and TRAFFIC use their source-specific forms.

For an active circle offer, pass the exact offer ID into `CoopFlowSupplyManagementView(context:canManageCircleSupply:)` and use `sourceContext.canReconfirmOrPause`. Its true condition is active offer + positive offerId + nonempty circleThemeCode. If a current active offer lacks the recruitment chapter's terms, do not invent TRAFFIC/PERK/REVSHARE just to satisfy the other module's context constructor. Keep the bridge blocked until that module accepts a management-only context or a source-backed terms read is available.

The closure is a navigation hook only. It never grants the cooperation executor permission or enables financial/terms commitments.

## DEBUG fixture and UI tests

Add a DEBUG branch in QuestifyApp's fixture selection:

```swift
if ProcessInfo.processInfo.arguments.contains("--uitesting-merchant-content-fixture") {
    MerchantContentFixtureScenarioView()
}
```

Include that exact launch argument in the existing synthetic-fixture startup/restore-bypass condition. The fixture root uses only `MerchantContentFixtureTransport` and a memory journal. It supports `--merchant-content-denied`, `--merchant-content-unknown`, and `--merchant-content-failure`. It also provides deterministic sign-out/recover controls and an explicit synthetic-data banner.

`MerchantContentFlowTests` contains seven authored flows: review cancellation, rejected registration editing, ambiguous claim ID, denied access, unknown-write lock, account-switch navigation clearing and station checklist scope. Run them under both locales, light/dark appearance, Reduce Motion and accessibility text sizes as part of Apple validation. They have not been run in this environment.

## Integration checks

```sh
python3 tools/generate_project.py
python3 tools/check_scaffold.py
python3 tools/check_merchant_content.py
swift test
xcodebuild -project Questify.xcodeproj -scheme Questify \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Also run the seven new UI tests after mounting the fixture and rerun affected merchant, account, cooperation and session tests. Source and parser checks passed in isolation and in a disposable structural overlay, but cannot establish Swift typechecking, actor conformance, SwiftUI layout or runtime safety. Do not mark these 62 core/7 UI tests as passed until the actual Apple/Swift test results exist.
