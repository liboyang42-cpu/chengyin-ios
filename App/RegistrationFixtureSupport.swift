#if DEBUG
import SwiftUI

enum RegistrationFixtureScenario: String, CaseIterable {
    case standard, noPaymentParameters, unknownAmounts, quoteError, participantsError
    case createTimeout, readbackError, conflictingStatus, soldOut, disabled, signupClosed
    case waitlistWaiting, waitlistOffer, waitlistExpiringOffer, waitlistClaimed, waitlistConverted, waitlistOrderError
    var isWaitlist: Bool { self == .waitlistWaiting || isOffer || isOrder }
    var isOrder: Bool { self == .waitlistClaimed || self == .waitlistConverted || self == .waitlistOrderError }
    var isOffer: Bool { self == .waitlistOffer || self == .waitlistExpiringOffer }
    static func selected(arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: "--uitesting-registration-fixture"),
              arguments.indices.contains(index + 1) else { return nil }
        return Self(rawValue: arguments[index + 1])
    }
}

/// Explicit offline fixtures only. Every response is in-memory synthetic JSON. No URL,
/// HTTP transport, production credential, consent endpoint or payment SDK is referenced.
@MainActor
private final class RegistrationFixtureStore: RegistrationCoordinatingService, ProfileReading, RegistrationWaitlistServing {
    let scenario: RegistrationFixtureScenario
    let isConfigured = true
    let identity: ProfileReadIdentity? = .init(accountID: 9400, epoch: 1)
    private var waitlistState = "NONE"
    private var offerDeadline: String
    private var quotes = 0
    init(_ scenario: RegistrationFixtureScenario) {
        self.scenario = scenario
        offerDeadline = ISO8601DateFormatter().string(from: scenario == .waitlistExpiringOffer ? Date.distantFuture : Date().addingTimeInterval(3600))
        if scenario.isOffer { waitlistState = "OFFERED" }
        if scenario.isOrder { waitlistState = scenario == .waitlistConverted ? "CONVERTED" : "CLAIMED" }
    }
    func armOfferExpiry() {
        guard scenario == .waitlistExpiringOffer else { return }
        offerDeadline = ISO8601DateFormatter().string(from: Date().addingTimeInterval(20))
    }
    func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote {
        quotes += 1
        if scenario == .quoteError, quotes == 1 { throw URLError(.notConnectedToInternet) }
        if scenario == .unknownAmounts { return try decode(#"{"pointsUsable":true,"quoteSign":"offline-only"}"#) }
        let amount = selection.ticketID == 9403 ? 0 : (selection.usePoints ? 10 : 12.5)
        return try decode("""
        {"payAmount":\(amount),"pointsUsed":\(selection.usePoints ? 250 : 0),
         "pointsDeductYuan":\(selection.usePoints ? 2.5 : 0),"pointsUsable":true,
         "memberDiscountYuan":0,"couponDeductYuan":0,"clubMember":false,
         "quoteSign":"offline-only-\(selection.ticketID ?? 0)-\(selection.usePoints)"}
        """)
    }
    func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult {
        if scenario.isOffer {
            guard intent.selection.waitlistOffer == intent.waitlistOffer, intent.waitlistOffer?.id == 9405,
                  intent.waitlistOffer?.token == "offline-only-offer" else { throw APIError.invalidRequest }
        }
        if scenario == .createTimeout { throw URLError(.timedOut) }
        if scenario == .noPaymentParameters || intent.selection.ticketID == 9403 {
            return try decode(#"{"registrationId":9401,"registrationNo":"OFFLINE-9401","payableAmount":0}"#)
        }
        return try decode("""
        {"registrationId":9401,"registrationNo":"OFFLINE-9401","payableAmount":\(intent.selection.usePoints ? 10 : 12.5),"payParams":{"fixture":"non-executable"}}
        """)
    }
    func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot {
        if scenario == .readbackError { throw URLError(.notConnectedToInternet) }
        if scenario == .conflictingStatus { return try decode(#"{"id":9401,"registrationStatus":3,"paymentStatus":2,"verificationStatus":0}"#) }
        return try decode(#"{"id":9401,"registrationStatus":1,"paymentStatus":1,"verificationStatus":0}"#)
    }
    func status(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus {
        guard scope.activityID == 9400, scope.ticketID == 9401 else { throw APIError.invalidRequest }
        let offer = waitlistState == "OFFERED" ? ",\"offerToken\":\"offline-only-offer\",\"offerExpiresAt\":\"\(offerDeadline)\"" : ""
        let order = scenario.isOrder ? ",\"registrationId\":9417" : ""
        return try decode("{\"id\":9405,\"activityId\":9400,\"ticketId\":9401,\"memberId\":9400,\"state\":\"\(waitlistState)\",\"eligibilityState\":\"ELIGIBLE\",\"waitlistJoinAllowed\":true\(offer)\(order)}")
    }
    func join(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus {
        waitlistState = "WAITING"; return try await status(scope)
    }
    func cancel(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus {
        waitlistState = "CANCELLED"; return try await status(scope)
    }
    func profileParticipants() async throws -> [ProfileParticipant] {
        if scenario == .participantsError { throw URLError(.notConnectedToInternet) }
        return try decode(#"[{"id":9401,"fullName":"Fixture Guest","mobilePhone":"13800000000"},{"id":9402,"fullName":"Fixture Default","mobilePhone":"13900000000","isDefault":true}]"#)
    }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.invalidRequest }
    func profileOrders() async throws -> [ProfileOrder] { [] }
    func profileOrder(id: Int) async throws -> ProfileOrder {
        guard scenario.isOrder, id == 9417 else { throw APIError.invalidRequest }
        if scenario == .waitlistOrderError { throw URLError(.notConnectedToInternet) }
        return try decode(#"{"id":9417,"memberId":9400,"ownerType":2,"ownerId":9400,"ticketId":9401,"registrationNo":"OFFLINE-WAITLIST-9417","registrationStatus":0,"paymentStatus":0,"cmsActivity":{"name":"Synthetic waitlist order"}}"#)
    }
    func profileBadges() async throws -> ProfileBadgeWall { .init(identities: [], medals: []) }
    private func decode<T: Decodable>(_ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }
}

@MainActor
private final class RegistrationFixtureModel: ObservableObject {
    let store: RegistrationFixtureStore
    let coordinator: RegistrationCoordinator
    let activity: ActivityDetail?
    let scenario: RegistrationFixtureScenario
    private(set) var expiryFlow: RegistrationUIFlow?
    @Published private(set) var expiryArmed = false
    init(scenario: RegistrationFixtureScenario) {
        self.scenario = scenario
        let store = RegistrationFixtureStore(scenario)
        self.store = store
        coordinator = RegistrationCoordinator(service: store, makeRequestID: { "offline-fixture-retained-intent" })
        try? coordinator.setAccount(id: 9400, token: "offline-fixture-unused-token")
        activity = try? JSONDecoder().decode(ActivityDetail.self, from: Data("""
        {"id":9400,"name":"Offline fixture activity","startDate":"2026-10-12","endDate":"2026-10-12",
         "addressName":"Synthetic meeting point","omsTicketList":[
         {"id":9401,"name":"Standard fixture ticket","price":12.5,"remainingInventory":\(scenario == .soldOut || scenario.isWaitlist ? 0 : 4),"startTime":\(scenario == .signupClosed ? "\"2020-01-01 00:00:00\"" : "null")},
         {"id":9402,"name":"Unknown-price fixture ticket","price":null,"remainingInventory":null},
         {"id":9403,"name":"Zero-price fixture ticket","price":0,"remainingInventory":2}]}
        """.utf8))
        if scenario == .waitlistExpiringOffer, let activity {
            expiryFlow = RegistrationUIFlow(activity: activity, coordinator: coordinator,
                participantReader: store, currentIdentity: { store.identity }, quoteEnabled: true,
                creationPolicy: .offlineFixture, waitlistService: store)
        }
    }
    func armOfferExpiry() async {
        guard scenario == .waitlistExpiringOffer, let expiryFlow, !expiryArmed else { return }
        expiryArmed = true
        store.armOfferExpiry()
        // Refresh only the synthetic status once, then let the unchanged real clock expire it.
        await expiryFlow.loadWaitlist()
    }
}

/// The same coordinator survives reopening the sheet: no replacement after uncertainty.
@MainActor
struct RegistrationFixtureHostView: View {
    @StateObject private var model: RegistrationFixtureModel
    @State private var presented = true
    init(scenario: RegistrationFixtureScenario = .standard) {
        _model = StateObject(wrappedValue: RegistrationFixtureModel(scenario: scenario))
    }
    var body: some View {
        VStack(spacing: 20) {
            Text("registration.form.fixtureNotice")
            Button("registration.form.open") { presented = true }
                .accessibilityIdentifier("registration.fixture.open")
        }
        .sheet(isPresented: $presented) {
            if let flow = model.expiryFlow {
                RegistrationSheetView(fixtureFlow: flow)
                    .safeAreaInset(edge: .bottom) {
                        if !model.expiryArmed {
                            Button("Arm synthetic offer expiry") { Task { await model.armOfferExpiry() } }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("registration.fixture.armExpiry")
                        }
                    }
                    .modifier(AccessibilityFixtureOptions())
            } else if let activity = model.activity {
                RegistrationSheetView(activity: activity, coordinator: model.coordinator,
                                      participantReader: model.store, orderReader: model.store, currentIdentity: { model.store.identity },
                                      quoteEnabled: true,
                                      creationPolicy: model.scenario == .disabled ? .disabled : .offlineFixture,
                                      waitlistService: model.scenario.isWaitlist ? model.store : nil)
                    .modifier(AccessibilityFixtureOptions())
            }
        }
    }
}

#Preview("Registration · offline") { RegistrationFixtureHostView() }
#Preview("Registration · unknown outcome") { RegistrationFixtureHostView(scenario: .createTimeout) }
#Preview("Registration · live create disabled") { RegistrationFixtureHostView(scenario: .disabled) }
#endif
