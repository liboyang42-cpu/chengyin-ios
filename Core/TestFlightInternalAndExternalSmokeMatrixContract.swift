import Foundation

/// Pure self-contained value-type contract modeling the Day-5 TestFlight 6-Journey
/// Real-Device Smoke Matrix:
/// 1. `"tf-smoke-01-auth-and-session-gate"`,
/// 2. `"tf-smoke-02-city-roam-and-stamp-unlock"`,
/// 3. `"tf-smoke-03-story-walking-and-durable-recovery"`,
/// 4. `"tf-smoke-04-npc-chat-and-tts-audio"`,
/// 5. `"tf-smoke-05-merchant-store-and-apply-wizard"`,
/// 6. `"tf-smoke-06-club-enrollment-and-settlement"`.
public struct TestFlightSmokeJourneyCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let journeyTitle: String
    public let hasAutomatedUITestTwin: Bool
    public let verifiesZeroCrashAndZeroBlankScreen: Bool
    public let verifiesFailClosedOrAllowlistedWrites: Bool

    public init(
        id: String,
        journeyTitle: String,
        hasAutomatedUITestTwin: Bool = true,
        verifiesZeroCrashAndZeroBlankScreen: Bool = true,
        verifiesFailClosedOrAllowlistedWrites: Bool = true
    ) {
        self.id = id
        self.journeyTitle = journeyTitle
        self.hasAutomatedUITestTwin = hasAutomatedUITestTwin
        self.verifiesZeroCrashAndZeroBlankScreen = verifiesZeroCrashAndZeroBlankScreen
        self.verifiesFailClosedOrAllowlistedWrites = verifiesFailClosedOrAllowlistedWrites
    }

    public var isCompliant: Bool {
        hasAutomatedUITestTwin
            && verifiesZeroCrashAndZeroBlankScreen
            && verifiesFailClosedOrAllowlistedWrites
    }
}

public struct TestFlightInternalAndExternalSmokeMatrixContract: Sendable, Equatable {
    public static let canonicalJourneys: [TestFlightSmokeJourneyCheck] = [
        TestFlightSmokeJourneyCheck(
            id: "tf-smoke-01-auth-and-session-gate",
            journeyTitle: "Journey 01 — Auth, Regional Scope, Single-Flight 401 & Account Deletion Purge",
            hasAutomatedUITestTwin: true,
            verifiesZeroCrashAndZeroBlankScreen: true,
            verifiesFailClosedOrAllowlistedWrites: true
        ),
        TestFlightSmokeJourneyCheck(
            id: "tf-smoke-02-city-roam-and-stamp-unlock",
            journeyTitle: "Journey 02 — City Roam Map, Tile Fog Readback & Stamp Unlock",
            hasAutomatedUITestTwin: true,
            verifiesZeroCrashAndZeroBlankScreen: true,
            verifiesFailClosedOrAllowlistedWrites: true
        ),
        TestFlightSmokeJourneyCheck(
            id: "tf-smoke-03-story-walking-and-durable-recovery",
            journeyTitle: "Journey 03 — Story-Ordered Walking Navigation & Durable Command Journal Recovery",
            hasAutomatedUITestTwin: true,
            verifiesZeroCrashAndZeroBlankScreen: true,
            verifiesFailClosedOrAllowlistedWrites: true
        ),
        TestFlightSmokeJourneyCheck(
            id: "tf-smoke-04-npc-chat-and-tts-audio",
            journeyTitle: "Journey 04 — NPC Chat Dialogue & TTS Audio Playback Lifecycle",
            hasAutomatedUITestTwin: true,
            verifiesZeroCrashAndZeroBlankScreen: true,
            verifiesFailClosedOrAllowlistedWrites: true
        ),
        TestFlightSmokeJourneyCheck(
            id: "tf-smoke-05-merchant-store-and-apply-wizard",
            journeyTitle: "Journey 05 — Merchant Store Station, Two-Step Redemption & Apply Wizard",
            hasAutomatedUITestTwin: true,
            verifiesZeroCrashAndZeroBlankScreen: true,
            verifiesFailClosedOrAllowlistedWrites: true
        ),
        TestFlightSmokeJourneyCheck(
            id: "tf-smoke-06-club-enrollment-and-settlement",
            journeyTitle: "Journey 06 — Club Access POST, Series Schedule, Enrollment & Settlement Readback",
            hasAutomatedUITestTwin: true,
            verifiesZeroCrashAndZeroBlankScreen: true,
            verifiesFailClosedOrAllowlistedWrites: true
        ),
    ]

    public init() {}

    public static func evaluate(
        journeys: [TestFlightSmokeJourneyCheck] = canonicalJourneys
    ) -> (totalJourneys: Int, compliantJourneys: Int, isTestFlightSmokeReady: Bool) {
        let totalJourneys = journeys.count
        let compliantJourneys = journeys.filter(\.isCompliant).count
        let expectedIDs = Set(canonicalJourneys.map(\.id))
        let hasAllCanonicalIDs = totalJourneys == canonicalJourneys.count && Set(journeys.map(\.id)) == expectedIDs
        let isTestFlightSmokeReady = !journeys.isEmpty
            && hasAllCanonicalIDs
            && compliantJourneys == totalJourneys
        return (
            totalJourneys: totalJourneys,
            compliantJourneys: compliantJourneys,
            isTestFlightSmokeReady: isTestFlightSmokeReady
        )
    }
}
