import Foundation

/// Classification only. v1 prefixes and JSON do not authenticate a ticket or establish ownership.
/// Not Codable: credential-like code bytes never enter a journal or persisted fixture screenshot.
public struct MerchantRedemptionContext: Equatable {
    public enum Kind: String { case group, dynamicTicket, coupon, legacyTicket }
    public let kind: Kind
    fileprivate let code: String
    fileprivate let legacyType: String?
    public static func parse(_ raw: String) throws -> Self {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.utf8.count <= 16_384 else { throw MerchantBusinessFailure.invalid }
        if code.hasPrefix("v1.") {
            let parts = code.split(separator: ".", omittingEmptySubsequences: false)
            let type = parts.count >= 3 ? String(parts[2]) : ""
            if type.hasPrefix("group_") { return .init(kind: .group, code: code, legacyType: nil) }
            if ["activity", "topic"].contains(type) { return .init(kind: .dynamicTicket, code: code, legacyType: nil) }
            throw MerchantRedemptionFailure.unsupported
        }
        // Current source also accepts signed coupon presentation codes directly.
        // Prefix classification is never proof of authenticity; only the server verifies it.
        if code.hasPrefix("cq1."), code.split(separator: ".", omittingEmptySubsequences: false).count == 4 {
            return .init(kind: .coupon, code: code, legacyType: nil)
        }
        guard let object = try? JSONDecoder().decode(MerchantBusinessValue.self, from: Data(code.utf8)).object,
              let type = object.mbText("type"), let inner = object.mbText("code") else { throw MerchantBusinessFailure.invalid }
        if type == "coupon" { return .init(kind: .coupon, code: inner, legacyType: nil) }
        if ["activity", "topic"].contains(type) { return .init(kind: .legacyTicket, code: inner, legacyType: type) }
        throw MerchantBusinessFailure.invalid
    }
    public var endpoint: String {
        switch kind {
        case .group: return "api/verify/groupcode/redeem"
        case .coupon: return "api/coupon/verification"
        case .dynamicTicket: return "api/registration/scan_dynamic_code"
        case .legacyTicket: return "api/registration/scan_qr_code"
        }
    }
    public func request(choice: MerchantRedemptionChoice.Target? = nil) -> MerchantBusinessRequest {
        if let choice {
            switch choice {
            case .chapter(let id): return .form("api/registration/scan_qr_code_chapter", ["code": code, "chapterId": String(id.rawValue)])
            case .stationRegistration(let id): return .form("api/registration/scan_qr_code_station", ["code": code, "registrationMerchantId": String(id.rawValue)])
            }
        }
        var fields = ["code": code]; if let legacyType { fields["type"] = legacyType }
        return .form(endpoint, fields)
    }
}
public enum MerchantRedemptionFailure: Error, Equatable { case unsupported, denied, noChoices, unknown }
public struct MerchantRedemptionChoice: Equatable, Identifiable {
    public enum Target: Equatable, Hashable { case chapter(MerchantChapterID), stationRegistration(MerchantStationRegistrationID) }
    public let target: Target
    public let name: String?
    public var id: String {
        switch target { case .chapter(let id): return "chapter:\(id.rawValue)"; case .stationRegistration(let id): return "station-registration:\(id.rawValue)" }
    }
}
public struct MerchantRedemptionResult: Equatable {
    public enum Outcome: Equatable { case redeemed, needsChoice, failed }
    public let outcome: Outcome
    public let message: String?
    public let choices: [MerchantRedemptionChoice]
    public let chapterID: MerchantChapterID?
    public init(body: MerchantBusinessObject, kind: MerchantRedemptionContext.Kind) throws {
        let data = body["data"]?.object ?? [:]
        let code = try body.mbInt("code")
        if code == 401 { throw APIError.unauthorized }
        if code == 403 { throw MerchantBusinessFailure.denied }
        message = body.mbText("msg")
        var choices: [MerchantRedemptionChoice] = []
        // Source choice flags only apply to the legacy scan flow, before interpreting code.
        if kind == .legacyTicket, data["needChapterChoice"]?.bool == true || data["needStationChoice"]?.bool == true {
            guard !(data["needChapterChoice"]?.bool == true && data["needStationChoice"]?.bool == true) else { throw MerchantBusinessFailure.malformed }
            if data["needChapterChoice"]?.bool == true {
                if let described = data["chapters"]?.array, !described.isEmpty {
                    choices = try described.map { value in
                        guard let object = value.object else { throw MerchantBusinessFailure.malformed }
                        return .init(target: .chapter(try .init(object.mbInt("id", minimum: 1))), name: object.mbText("name") ?? object.mbText("title"))
                    }
                } else {
                    choices = try data.mbArray("chapterIds").map { value in
                        guard let id = value.integer else { throw MerchantBusinessFailure.malformed }
                        return .init(target: .chapter(try .init(id)), name: nil)
                    }
                }
            } else {
                choices = try data.mbObjects("stations").map { object in
                    // Never fall back to a station/POI id. A dedicated registrationMerchantId is required.
                    .init(target: .stationRegistration(try .init(object.mbInt("registrationMerchantId", minimum: 1))), name: object.mbText("name") ?? object.mbText("title"))
                }
            }
            guard !choices.isEmpty, Set(choices.map(\.id)).count == choices.count else { throw MerchantRedemptionFailure.noChoices }
            outcome = .needsChoice
        } else { outcome = code == 200 ? .redeemed : .failed }
        self.choices = choices
        if let id = data["chapterId"]?.integer { chapterID = try .init(id) } else { chapterID = nil }
    }
}
/// App host only exposes classification previews. End-to-end synthetic tests may inject this
/// coordinator. No camera, QR issuance, live dispatch, phone/copy or permission request occurs.
@MainActor public final class MerchantRedemptionCoordinator {
    private let service: MerchantBusinessService
    private let journal: any MerchantBusinessIntentStore
    private let currentSession: () -> MerchantBusinessSession?
    private var pending: (context: MerchantRedemptionContext, result: MerchantRedemptionResult, session: MerchantBusinessSession, merchantID: Int)?
    public private(set) var result: MerchantRedemptionResult?
    public private(set) var busy = false
    private var generation: UInt64 = 0
    public init(service: MerchantBusinessService, journal: any MerchantBusinessIntentStore, currentSession: @escaping () -> MerchantBusinessSession?) {
        self.service = service; self.journal = journal; self.currentSession = currentSession
    }
    public func begin(_ context: MerchantRedemptionContext, expectedMerchantID: Int? = nil) async throws {
        guard !busy, pending == nil else { throw MerchantBusinessFailure.pending }
        guard expectedMerchantID.map({ $0 > 0 }) ?? true else { throw MerchantBusinessFailure.invalid }
        guard let session = currentSession() else { throw APIError.unauthorized }
        try await perform(context, choice: nil, session: session, expectedMerchantID: expectedMerchantID, generation: generation)
    }
    public func choose(_ choice: MerchantRedemptionChoice.Target) async throws {
        guard !busy, let pending, pending.result.choices.contains(where: { $0.target == choice }), pending.session == currentSession() else { throw MerchantBusinessFailure.stale }
        self.pending = nil
        try await perform(pending.context, choice: choice, session: pending.session, expectedMerchantID: pending.merchantID, generation: generation)
    }
    public func cancelChoice() { generation &+= 1; pending = nil; result = nil }
    private func perform(_ context: MerchantRedemptionContext, choice: MerchantRedemptionChoice.Target?, session: MerchantBusinessSession, expectedMerchantID: Int?, generation: UInt64) async throws {
        guard service.canExecuteVerificationMutation else { throw MerchantBusinessFailure.disabled }
        busy = true; result = nil; defer { busy = false }
        let access = try await service.access(token: session.token)
        try access.require(["merchant:verify"])
        guard self.generation == generation, session == currentSession(), !Task.isCancelled, expectedMerchantID == nil || expectedMerchantID == access.merchantID else { throw MerchantBusinessFailure.stale }
        let scope = MerchantBusinessScope(realm: service.realm, accountID: session.accountID, epoch: session.epoch)
        // Coarse merchant redemption lock intentionally blocks scanning any next code after an uncertain result.
        let intent = MerchantBusinessIntent(scope: scope, merchantID: access.merchantID, target: "redemption", requestID: "local-" + UUID().uuidString)
        try journal.reserve(intent)
        do {
            // Even an injected storage callback may change the session while reserving.
            // Recheck immediately before transport; a reserved lock is retained conservatively.
            guard self.generation == generation, session == currentSession(), !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            let body = try await service.verificationEnvelope(context.request(choice: choice), token: session.token)
            let value = try MerchantRedemptionResult(body: body, kind: context.kind)
            guard self.generation == generation, session == currentSession(), !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            // needsChoice explicitly means no redemption; it is safe to reserve a new second-step intent.
            if choice != nil, value.outcome == .needsChoice { throw MerchantBusinessFailure.malformed }
            try journal.complete(intent); result = value
            if value.outcome == .needsChoice { pending = (context, value, session, access.merchantID) }
        } catch {
            if MerchantMutationFailureDisposition.provesNoDispatch(error) {
                try journal.complete(intent); throw error
            }
            throw MerchantBusinessFailure.unknown
        }
    }
}
