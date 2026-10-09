import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ActivityAssociatedPlaysViewTests: XCTestCase {
    func testReadOnlyMetadataRowBuildsWithoutReaderTemplateIDOrDestination() throws {
        let row = try JSONDecoder().decode(ActivityAssociatedPlay.self, from: Data(#"{"title":"Synthetic play","players":"2–6","duration":30.5}"#.utf8))
        let host = UIHostingController(rootView: ActivityAssociatedPlayRow(play: row).environment(\.dynamicTypeSize, .accessibility3))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertEqual(row.players, "2–6"); XCTAssertEqual(row.durationMinutes, 30.5)
        XCTAssertNotNil(host.view)
    }
    func testEmptyAndUnknownRowsDoNotCreateFallbackActivitiesOrValues() throws {
        XCTAssertTrue(ActivityAssociatedPlaysSection(plays: []).plays.isEmpty)
        let row = try JSONDecoder().decode(ActivityAssociatedPlay.self, from: Data("{}".utf8))
        let view = ActivityAssociatedPlayRow(play: row)
        XCTAssertNil(view.play.title); XCTAssertNil(view.play.players); XCTAssertNil(view.play.durationMinutes)
    }
}
