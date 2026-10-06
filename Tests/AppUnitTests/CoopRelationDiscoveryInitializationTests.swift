import XCTest
import SwiftUI
import UIKit
@testable import Questify

#if DEBUG
@MainActor final class CoopRelationDiscoveryInitializationTests: XCTestCase {
    private func wait(_ stage: String, _ condition: @escaping () -> Bool,
                      file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(stage, file: file, line: line)
        throw CancellationError()
    }

    func testDefaultModelInitializationHostsDiscoveryWithoutAnInjectedModel() async throws {
        let reader = CoopRelationFixtureReader(scenario: "mixed")
        let view = CoopRelationDiscoveryView(reader: reader)
        XCTAssertEqual(reader.reads, 0, "Constructing the view must not dispatch a read")
        let host = UIHostingController(rootView: NavigationStack { view })
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await wait("the actor-created default model reads the real discovery") { reader.reads == 1 }
        XCTAssertNotNil(host.view.window)
        XCTAssertEqual(reader.reads, 1)
        XCTAssertEqual(reader.ownerReads, 0)
        XCTAssertEqual(reader.clubReads, 0)
    }

    func testInjectedModelInitializationLoadsTheExactSuppliedInstance() async throws {
        let reader = CoopRelationFixtureReader(scenario: "mixed")
        let model = CoopRelationDiscoveryModel()
        let owner = CoopRelationPresentationOwner()
        let view = CoopRelationDiscoveryView(reader: reader, model: model, presentation: owner)
        XCTAssertEqual(reader.reads, 0)
        XCTAssertFalse(model.isCurrent(reader: reader))
        let host = UIHostingController(rootView: NavigationStack { view })
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await wait("the exact injected model receives the discovery result") { model.isCurrent(reader: reader) }
        XCTAssertNotNil(host.view.window)
        XCTAssertEqual(reader.reads, 1)
        XCTAssertNotNil(model.value)
        XCTAssertNil(owner.selection)
        XCTAssertEqual(reader.ownerReads, 0)
        XCTAssertEqual(reader.clubReads, 0)
    }
}
#endif
