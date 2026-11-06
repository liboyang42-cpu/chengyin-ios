#if DEBUG
import SwiftUI
import Observation

enum ProfileEditFixtureScenario {
    static func selected(arguments:[String])->String? {
        guard let i=arguments.firstIndex(of:"--uitesting-profile-edit-fixture"),arguments.indices.contains(i+1) else { return nil }
        return arguments[i+1]
    }
}

struct ProfileEditFixtureHost: View {
    private let coordinator: ProfileEditCoordinator
    private let returnScenario: String?
    init(scenario: String) {
        returnScenario = scenario.hasPrefix("savedReturn") ? scenario : nil
        let mode: ProfileEditSyntheticService.Scenario
        switch scenario {
        case "contactQR": mode = .contactQR
        case "preferenceRemoval": mode = .preferenceRemoval
        case "caseRemoval": mode = .caseRemoval
        case "portfolioImages": mode = .portfolioImages
        case "refreshFailure": mode = .refreshFailure
        case "rejected": mode = .rejected
        case "unknown": mode = .unknown
        case "missing": mode = .missingPreservation
        default: mode = .success
        }
        let session = try! ProfileEditSession(accountID: 901, epoch: 1, token: "synthetic-profile-token")
        coordinator = ProfileEditCoordinator(service: ProfileEditSyntheticService(scenario: mode), currentSession: { session })
    }
    var body: some View {
        if let returnScenario {
            ProfileSavedReturnFixtureHost(scenario: returnScenario)
        } else {
            NavigationStack {
                ProfileEditView(coordinator: coordinator, sessionRevision: 1, onSaved: {})
                    .safeAreaInset(edge: .top) {
                        Text("Synthetic profile fixture • no network")
                            .font(.caption).accessibilityIdentifier("profile.edit.fixture.notice")
                    }
            }
        }
    }
}
/// A real navigation destination using the production editor's default dismissal.
/// Both the store and coordinator survive parent view updates.
@MainActor @Observable private final class ProfileSavedReturnFixtureData: ProfileEditServing {
    let scenario: String
    var session: ProfileEditSession?
    var name = "Synthetic return profile"
    var introduction = "Original return introduction"
    var writes = 0
    var parentVisits = 0
    var displayedIntroduction = ""
    var readbackFails = false
    var coordinator: ProfileEditCoordinator!
    init(scenario: String) {
        self.scenario = scenario
        session = try! .init(accountID: 901, epoch: 1, token: "synthetic-return-only", viewerRevision: 1)
        coordinator = .init(service: self, currentSession: { [weak self] in self?.session })
    }
    func read(token: String) async throws -> ProfileEditSnapshot {
        if readbackFails { throw APIError.httpStatus(503) }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject:
            ["id": 901, "nickname": name, "introduction": introduction, "avatar": "", "wechat": "", "casePics": "", "tagIds": ""]))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        writes += 1
        if scenario == "savedReturnRejected" { throw ProfileEditWriteError.rejected(.init(code: 422)) }
        name = payload.name; introduction = payload.introduction
        if scenario == "savedReturnUnknown" { throw ProfileEditWriteError.outcomeUnknown }
        if scenario == "savedReturnReadFailure" { readbackFails = true }
        if scenario == "savedReturnSwitch" {
            session = try .init(accountID: 902, epoch: 2, token: "synthetic-return-other", viewerRevision: 2)
        }
    }
    func parentAppeared() async {
        parentVisits += 1
        // The parent reads its source; it never copies the editor's unsaved draft.
        if let session, let value = try? await read(token: session.token), value.id == session.identity.accountID {
            displayedIntroduction = value.introduction
        }
    }
}

@MainActor private struct ProfileSavedReturnFixtureHost: View {
    @State private var data: ProfileSavedReturnFixtureData
    init(scenario: String) { _data = State(initialValue: ProfileSavedReturnFixtureData(scenario: scenario)) }
    var body: some View {
        NavigationStack {
            List {
                Text(verbatim: data.displayedIntroduction).accessibilityIdentifier("profile.savedReturnFixture.introduction")
                NavigationLink("Edit synthetic return profile") {
                    ProfileEditView(coordinator: data.coordinator, sessionRevision: 1)
                }.accessibilityIdentifier("profile.savedReturnFixture.open")
            }
            .task { await data.parentAppeared() }
        }
        .safeAreaInset(edge: .bottom) {
            Text(verbatim: "Visits: \(data.parentVisits) Writes: \(data.writes)")
                .font(.caption).accessibilityIdentifier("profile.savedReturnFixture.counts")
        }
    }
}
#endif
