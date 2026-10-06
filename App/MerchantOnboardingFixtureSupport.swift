#if DEBUG
import SwiftUI

/// Opt-in offline fixture only. No production service, Photos permission or network is used.
@MainActor
struct MerchantOnboardingFixtureRoot: View {
    @StateObject private var fixture: MerchantOnboardingFixture
    private let coordinator: MerchantOnboardingCoordinator
    init(name: String) {
        let fixture = MerchantOnboardingFixture(name: name)
        _fixture = StateObject(wrappedValue: fixture)
        coordinator = MerchantOnboardingCoordinator(server: fixture)
    }
    static func selected(arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--uitesting-merchant-onboarding-fixture"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    var body: some View {
        NavigationStack {
            MerchantOnboardingView(session: fixture, coordinator: coordinator)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        if let diagnostics = MerchantOnboardingFixtureDiagnostics.current {
                            MerchantOnboardingDiagnosticNotice(diagnostics: diagnostics)
                        } else {
                            Text("merchant.onboarding.fixture.notice").font(.caption)
                                .accessibilityIdentifier("merchant.onboarding.fixture.notice")
                        }
                        Text(String(fixture.submissionCount)).accessibilityIdentifier("merchant.onboarding.fixture.writeCount")
                        Text(String(fixture.uploadCount)).accessibilityIdentifier("merchant.onboarding.fixture.uploadCount")
                    }.padding(8).background(.bar)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("merchant.onboarding.fixture.changeAccount") { fixture.replaceAccount() }
                            .accessibilityIdentifier("merchant.onboarding.fixture.changeAccount")
                    }
                }
        }
    }
}

@MainActor
final class MerchantOnboardingFixture: MerchantOnboardingObserving, MerchantOnboardingServing {
    let isConfigured = true
    @Published var isSignedIn = true
    @Published var sessionRevision: UInt64 = 1
    @Published private(set) var submissionCount = 0
    @Published private(set) var uploadCount = 0
    private var account = 90001
    var identity: ProfileReadIdentity? { isSignedIn ? .init(accountID: account, epoch: sessionRevision) : nil }
    private let name: String
    private var reads = 0
    private var submitted = false
    init(name: String) { self.name = name }
    func replaceAccount() { account += 1; sessionRevision += 1; submitted = false }
    private func validate(_ expected: ProfileReadIdentity) throws {
        guard identity == expected else { throw CancellationError() }
    }
    func application(expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingSnapshot {
        reads += 1
        try await Task.sleep(nanoseconds: 60_000_000); try validate(expectedIdentity)
        if name == "retry" && reads == 1 { throw APIError.malformedResponse }
        if submitted { return .application(try application(status: 0, accountStatus: 0)) }
        switch name {
        case "pending": return .application(try application(status: 0, accountStatus: 0))
        case "rejected", "submit-unknown", "submit-rejected", "identity-required", "identity-error": return .application(try application(status: 2, accountStatus: 0))
        case "disabled": return .application(try application(status: 2, accountStatus: 2))
        case "activation": return .application(try application(status: 1, accountStatus: 0))
        case "effective": return .application(try application(status: 1, accountStatus: 1))
        default: return .none
        }
    }
    func identityRegistered(expectedIdentity: ProfileReadIdentity) async throws -> Bool {
        try validate(expectedIdentity)
        if name == "identity-error" { throw APIError.malformedResponse }
        return name != "identity-required"
    }
    func uploadLicense(_ image: MerchantOnboardingImage, expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingLicense {
        try validate(expectedIdentity)
        uploadCount += 1
        // Explicitly synthetic receipt inside DEBUG. The production form has no URL text field.
        return try MerchantOnboardingLicense(serverURL: "https://fixtures.example/merchant-license.jpg")
    }
    func submit(_ draft: MerchantOnboardingDraft, expectedIdentity: ProfileReadIdentity) async throws {
        try validate(expectedIdentity)
        submissionCount += 1
        try await Task.sleep(nanoseconds: 150_000_000)
        try validate(expectedIdentity)
        if name == "submit-rejected" {
            throw MerchantOnboardingWriteError.rejected(.init(code: 409, message: String(localized: "merchant.onboarding.fixture.rejection")))
        }
        submitted = true
        if name == "submit-unknown" { throw MerchantOnboardingWriteError.outcomeUnknown }
    }
    private func application(status: Int, accountStatus: Int) throws -> MerchantOnboardingApplication {
        let fields: [String: Any] = [
            "id": 7701, "status": status, "accountStatus": accountStatus,
            "name": "Example Store", "preference": "Example category", "phone": "2025550100",
            "address": "Example address", "businessTime": "周一至周日 10:00-22:00", "description": "Offline example",
            "businessLicense": "https://fixtures.example/merchant-license.jpg",
            "reson": String(localized: "merchant.onboarding.fixture.rejection"),
            "disableReason": String(localized: "merchant.onboarding.fixture.disabled"), "createTime": "2026-01-01 10:00:00"
        ]
        return try JSONDecoder().decode(MerchantOnboardingApplication.self, from: JSONSerialization.data(withJSONObject: fields))
    }
}

/// Bounded event evidence for the two explicitly selected synthetic UI scenarios.
/// It records no draft fields, identities, URLs, credentials or service responses.
@MainActor
final class MerchantOnboardingFixtureDiagnostics: ObservableObject {
    enum Event: String { case reset, leave, reapplyEntered, reapplyBusy, reapplyLocked, reapplyEdited, reapplyInvalid }
    static let current = make(arguments: ProcessInfo.processInfo.arguments, emit: { print($0) })
    private let emit: (String) -> Void
    private var emitted = 0
    private var events: [String] = []
    @Published private(set) var evidence = ""
    private init(emit: @escaping (String) -> Void) { self.emit = emit }
    static func make(arguments: [String], emit: @escaping (String) -> Void) -> MerchantOnboardingFixtureDiagnostics? {
        let marker = "--uitesting-merchant-onboarding-fixture"
        let optIn = "--uitesting-merchant-onboarding-diagnostics"
        let indices = arguments.indices.filter { arguments[$0] == marker }
        guard indices.count == 1, let index = indices.first, index + 1 < arguments.count,
              ["rejected", "submit-unknown"].contains(arguments[index + 1]),
              arguments.filter({ $0 == optIn }).count == 1 else { return nil }
        return MerchantOnboardingFixtureDiagnostics(emit: emit)
    }
    func record(_ event: Event, busy: Bool, locked: Bool, editing: Bool, step: Int) {
        guard emitted < 16 else { return }
        emitted += 1
        let boundedStep = (1...4).contains(step) ? String(step) : "invalid"
        let entry = "MERCHANT_ONBOARDING_FIXTURE_DIAGNOSTIC event=" + event.rawValue +
             ";busy=" + (busy ? "1" : "0") + ";locked=" + (locked ? "1" : "0") +
             ";editing=" + (editing ? "1" : "0") + ";step=" + boundedStep
        events.append(entry); evidence = events.joined(separator: " | ")
        emit(entry)
    }
}

/// Only this existing notice leaf observes diagnostic changes; the Form does not.
@MainActor
private struct MerchantOnboardingDiagnosticNotice: View {
    @ObservedObject var diagnostics: MerchantOnboardingFixtureDiagnostics
    var body: some View {
        Text("merchant.onboarding.fixture.notice").font(.caption)
            .accessibilityIdentifier("merchant.onboarding.fixture.notice")
            .accessibilityValue(diagnostics.evidence)
    }
}
#endif
