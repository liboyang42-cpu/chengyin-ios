#if DEBUG
import SwiftUI

enum ProfileEditFixtureScenario {
    static func selected(arguments:[String])->String? {
        guard let i=arguments.firstIndex(of:"--uitesting-profile-edit-fixture"),arguments.indices.contains(i+1) else { return nil }
        return arguments[i+1]
    }
}

struct ProfileEditFixtureHost: View {
    private let coordinator: ProfileEditCoordinator
    init(scenario: String) {
        let mode: ProfileEditSyntheticService.Scenario
        switch scenario {
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
        NavigationStack {
            ProfileEditView(coordinator: coordinator, sessionRevision: 1)
                .safeAreaInset(edge: .top) {
                    Text("Synthetic profile fixture • no network")
                        .font(.caption).accessibilityIdentifier("profile.edit.fixture.notice")
                }
        }
    }
}
#endif
