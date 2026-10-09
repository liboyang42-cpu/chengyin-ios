import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamEventDestinationViewTests: XCTestCase {
    private func event(_ kind: String = "activity") throws -> RoamEvent {
        try JSONDecoder().decode(RoamEvent.self, from: Data("{\"kind\":\"\(kind)\",\"id\":7,\"title\":\"Synthetic event\"}".utf8))
    }
    private func scope(_ reader: any RoamReading, presentation: UUID) throws -> RoamEventNavigationScope {
        try XCTUnwrap(.init(readerID: ObjectIdentifier(reader), identity: reader.identity, area: reader.searchArea,
                           presentationID: presentation, isConfigured: reader.isConfigured))
    }
    func testBuildingOverviewDoesNotInvokeFullDetailFactory() throws {
        let reader = RoamFixtureReader(), event = try event()
        var destinations: [RoamEventDestination] = []
        let host = UIHostingController(rootView: RoamItemDetailView(item: .event(event), reader: reader,
            eventDestination: { value in destinations.append(value); return AnyView(Text("Synthetic detail")) }))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertTrue(destinations.isEmpty)
    }
    func testActualReaderScopeKeepsActivityAndTopicFactoryTargetsDistinct() throws {
        let reader = RoamFixtureReader(), context = try scope(reader, presentation: UUID())
        var destinations: [RoamEventDestination] = []
        for kind in ["activity", "topic"] {
            let event = try event(kind)
            let selection = try XCTUnwrap(RoamEventNavigationSelection(event: event, currentEvent: event, rendered: context, current: context))
            if selection.mayRemainOpen(in: context) { destinations.append(selection.destination) }
        }
        XCTAssertEqual(destinations, [.activity(7), .topic(7)])
    }
    func testNativeReaderReplacementAndUnavailableReaderCannotOpenCapturedTarget() throws {
        let firstReader = RoamFixtureReader(), replacement = RoamFixtureReader(), event = try event()
        let presentation = UUID(), first = try scope(firstReader, presentation: presentation), current = try scope(replacement, presentation: presentation)
        let selection = try XCTUnwrap(RoamEventNavigationSelection(event: event, currentEvent: event, rendered: first, current: first))
        XCTAssertFalse(selection.mayRemainOpen(in: current))
        XCTAssertNil(RoamEventNavigationSelection(event: event, currentEvent: event, rendered: first, current: current))
        let disabled = RoamFixtureReader(scenario: .unconfigured)
        let unavailable = RoamEventNavigationScope(readerID: ObjectIdentifier(disabled), identity: disabled.identity,
            area: disabled.searchArea, presentationID: presentation, isConfigured: disabled.isConfigured)
        XCTAssertNil(unavailable); XCTAssertFalse(selection.mayRemainOpen(in: unavailable))
    }
}
