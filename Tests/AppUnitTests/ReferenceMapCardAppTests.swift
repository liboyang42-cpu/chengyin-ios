import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ReferenceMapCardAppTests: XCTestCase {
    func testMissingMalformedAndNonHTTPSImagesStayAbsent() {
        for source in [nil, "", "not an image URL", "http://example.com/image.png", "https://user:secret@example.com/image.png"] {
            XCTAssertNil(QuestifyCardArtwork.safeURL(source))
        }
        XCTAssertEqual(QuestifyCardArtwork.safeURL("https://example.com/image.png")?.absoluteString, "https://example.com/image.png")
    }
    func testBilingualCardGrowsForCompleteSubtitleAtMaximumType() {
        func height(title: String, subtitle: String, size: DynamicTypeSize) -> CGFloat {
            let card = QuestifyImageEntityCard(imageSource: nil, title: title, subtitle: subtitle, minimumHeight: 230) {
                QuestifyImageEntityMetadata(label: "searchMap.kind.merchant", value: "商户 Merchant", systemImage: "storefront")
            }.dynamicTypeSize(size)
            let host = UIHostingController(rootView: card)
            host.traitOverrides.accessibilityContrast = .high
            XCTAssertEqual(host.traitCollection.accessibilityContrast, .high)
            return host.sizeThatFits(in: CGSize(width: 300, height: 20_000)).height
        }
        let short = height(title: "Place", subtitle: "Address", size: .large)
        let long = height(title: ReferenceMapCardFixtureView.longTitle, subtitle: ReferenceMapCardFixtureView.longSubtitle, size: .large)
        let maximum = height(title: ReferenceMapCardFixtureView.longTitle, subtitle: ReferenceMapCardFixtureView.longSubtitle, size: .accessibility5)
        XCTAssertGreaterThan(long, short)
        XCTAssertGreaterThan(maximum, long)
        XCTAssertTrue(maximum.isFinite)
    }
    func testSummaryConstructionNeverStartsLocationOrDirections() throws {
        let fixture = WalkingNavigationFixtureSupport()
        let model = try XCTUnwrap(fixture.factory.make(reference: .init(kind: .cityNode, id: 71)))
        let summary = ActiveDestinationSummary(phase: model.phase, target: model.target, route: model.route, progress: model.progress) { EmptyView() }
        let host = UIHostingController(rootView: summary)
        _ = host.sizeThatFits(in: CGSize(width: 300, height: 20_000))
        XCTAssertEqual(model.phase, .ready)
        XCTAssertNil(model.target); XCTAssertNil(model.route); XCTAssertNil(model.progress)
    }
    func testRoutingFixtureWaitsForCancellationAndNextStartCanComplete() async throws {
        let fixture = WalkingNavigationFixtureSupport(scenario: "routing")
        let model = try XCTUnwrap(fixture.factory.make(reference: .init(kind: .cityNode, id: 71)))
        let operation = Task { await model.start() }
        for _ in 0..<100 { if fixture.directions.hasPendingCalculation { break }; await Task.yield() }
        XCTAssertTrue(fixture.directions.hasPendingCalculation)
        XCTAssertEqual(model.phase, .routing); XCTAssertNil(model.route)
        model.cancel(); await operation.value
        XCTAssertFalse(fixture.directions.hasPendingCalculation)
        XCTAssertEqual(model.phase, .cancelled); XCTAssertNil(model.route)
        await model.start()
        XCTAssertEqual(model.phase, .navigating); XCTAssertNotNil(model.route)
    }
    func testScopeFixtureIsExplicitlyArmedAndUsesOrdinaryInvalidation() async throws {
        XCTAssertNil(WalkingNavigationFixtureSupport().scopeExpiryAction)
        let fixture = WalkingNavigationFixtureSupport(scenario: "expiredScope")
        let model = try XCTUnwrap(fixture.factory.make(reference: .init(kind: .cityNode, id: 71)))
        await model.start()
        XCTAssertEqual(model.phase, .navigating); XCTAssertNotNil(model.route)
        let expire = try XCTUnwrap(fixture.scopeExpiryAction)
        expire(); model.synchronize()
        XCTAssertEqual(model.phase, .failed(.staleContext))
        XCTAssertNil(model.route); XCTAssertNil(model.target); XCTAssertNil(model.progress)
    }

}
