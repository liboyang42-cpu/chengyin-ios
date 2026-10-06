import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class PublicMerchantFixtureOwnershipTests: XCTestCase {
    private func reader(_ owner: PublicMerchantHomeFixtureState, scope: UUID = UUID()) -> PublicMerchantHomeHTTPReader {
        .init(configuration: owner.configuration, transport: owner.transport, scope: scope, isOfflineExample: true)
    }
    private var target: PublicMerchantHomeTarget { .ownerMemberID(PublicMerchantOwnerID(41)!) }
    func testReaderReconstructionRetriesSameSyntheticRequestSequence() async throws {
        let owner = PublicMerchantHomeFixtureState(scenario: "retry"), scope = UUID()
        do { _ = try await reader(owner, scope: scope).home(target); XCTFail("First fixture request must fail") }
        catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .retryable) }
        let home = try await reader(owner, scope: scope).home(target)
        XCTAssertEqual(home.name, "Fixture shop"); XCTAssertEqual(home.id, 73); XCTAssertEqual(home.memberId, 41)
    }
    func testChangingReadScopeKeepsCounterAndReturnsNewExactFeaturedID() async throws {
        let owner = PublicMerchantHomeFixtureState(scenario: "featured-switch")
        let first = try await reader(owner, scope: UUID()).home(target)
        let second = try await reader(owner, scope: UUID()).home(target)
        XCTAssertEqual(first.publicFeatured(for: target)?.route, .activity(601))
        XCTAssertEqual(second.publicFeatured(for: target)?.route, .activity(602))
    }
    func testSeparateMountedFixtureOwnersDoNotShareFirstRequestState() async throws {
        for _ in 0..<2 {
            let owner = PublicMerchantHomeFixtureState(scenario: "retry")
            do { _ = try await reader(owner).home(target); XCTFail("Each independent host must start at its first request") }
            catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .retryable) }
        }
    }
    private final class Refresh: ObservableObject { @Published var revision = 0 }
    private struct Host: View {
        @ObservedObject var refresh: Refresh
        let observe: (PublicMerchantHomeFixtureState) -> Void
        var body: some View {
            PublicMerchantHomeFixtureView(scenario: "retry", ownerObserver: observe, probeRevision: refresh.revision)
        }
    }
    func testActualHostedParentRedrawRetainsTransportSessionAndJournalOwner() async throws {
        let refresh = Refresh()
        var owners: [PublicMerchantHomeFixtureState] = []
        let host = UIHostingController(rootView: Host(refresh: refresh, observe: { owners.append($0) }))
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<100 { if !owners.isEmpty { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        let original = try XCTUnwrap(owners.first), before = owners.count
        refresh.revision += 1
        for _ in 0..<100 { if owners.count > before { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertGreaterThan(owners.count, before, "The actual SwiftUI host must rebuild its fixture value")
        for current in owners {
            XCTAssertTrue(current === original)
            XCTAssertTrue(current.transport === original.transport)
            XCTAssertTrue(current.journal === original.journal)
            XCTAssertEqual(current.session.scope, original.session.scope)
        }
    }
}
