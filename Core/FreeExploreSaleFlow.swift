import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// F10 free-exploration author path: publish for recruitment without a price, wait until every
/// merchant slot is filled (by a merchant or by the author), then fill prices in the editor and
/// publish for sale directly. Project review still happens at the first publication; this path
/// has no separate sale review. All production writes stay behind independent grants.
public enum FreeExploreSaleRoute {
    public static let readinessPath = "api/topic/fe/sale-readiness"
    public static let publishPath = "api/topic/fe/publish-for-sale"
}

/// GET api/topic/fe/sale-readiness data. Server facts only; nothing is inferred locally.
public struct FreeExploreSaleReadiness: Equatable {
    public let topicID: Int
    public let lifecycle: Int
    public let totalSlots: Int
    public let filledSlots: Int
    public let openSlots: Int
    public let canFillPrice: Bool
    public let canPublish: Bool
    public init(topicID: Int, lifecycle: Int, totalSlots: Int, filledSlots: Int, openSlots: Int, canFillPrice: Bool, canPublish: Bool) {
        self.topicID = topicID; self.lifecycle = lifecycle; self.totalSlots = totalSlots
        self.filledSlots = filledSlots; self.openSlots = openSlots; self.canFillPrice = canFillPrice; self.canPublish = canPublish
    }
    public init(_ data: ProjectEditJSON, expectedTopicID: Int) throws {
        guard let b = data.object, let topic = PublisherValue.integer(b["topicId"]), topic == expectedTopicID, topic > 0,
              let lifecycle = PublisherValue.integer(b["lifecycle"]), (0...7).contains(lifecycle) else { throw PublisherLifecycleError.incomplete }
        func count(_ key: String) throws -> Int {
            guard let value = PublisherValue.integer(b[key]), value >= 0 else { throw PublisherLifecycleError.incomplete }
            return value
        }
        func flag(_ key: String) throws -> Bool {
            guard case .bool(let value)? = b[key] else { throw PublisherLifecycleError.incomplete }
            return value
        }
        self.init(topicID: topic, lifecycle: lifecycle, totalSlots: try count("totalSlots"), filledSlots: try count("filledSlots"),
                  openSlots: try count("openSlots"), canFillPrice: try flag("canFillPrice"), canPublish: try flag("canPublish"))
    }
    public var priceState: FreeExplorePriceState { FreeExplorePriceState(self) }
}

/// What the editor's ticket price area may do for a free-exploration topic.
public enum FreeExplorePriceState: Equatable {
    /// Not a free-exploration topic, or readiness is unknown: keep the normal editor behaviour.
    case notApplicable
    /// lifecycle 1 (recruiting): price fields are disabled; "还有 N 个位置待承接".
    case awaitingSlots(open: Int)
    /// lifecycle 2 (awaiting price): the author enters prices and may publish for sale.
    case priceEntry(canPublish: Bool)
    /// lifecycle 3+ : already on sale or later; prices are frozen.
    case frozen
    public init(_ readiness: FreeExploreSaleReadiness?) {
        guard let readiness else { self = .notApplicable; return }
        switch readiness.lifecycle {
        case 1: self = .awaitingSlots(open: max(readiness.openSlots, 0))
        case 2: self = readiness.canFillPrice ? .priceEntry(canPublish: readiness.canPublish) : .awaitingSlots(open: max(readiness.openSlots, 0))
        case 3, 4, 5, 6: self = .frozen
        default: self = .notApplicable
        }
    }
    public var disablesPriceFields: Bool {
        switch self { case .awaitingSlots, .frozen: return true; default: return false }
    }
    /// Open slot count while awaiting suppliers; the view localizes it with "freeExplore.sale.openSlots".
    public var openSlotCount: Int? {
        guard case .awaitingSlots(let open) = self else { return nil }
        return open
    }
}

/// POST api/topic/fe/publish-for-sale {topicId, ticketPrices:{"<ticketId>": price}}.
public struct FreeExplorePublishRequest: Equatable {
    public let topicID: Int
    public let ticketPrices: [Int: Decimal]
    public init(topicID: Int, ticketPrices: [Int: Decimal]) throws {
        guard topicID > 0, !ticketPrices.isEmpty,
              ticketPrices.allSatisfy({ $0.key > 0 && Self.validPrice($0.value) }) else { throw PublisherLifecycleError.incomplete }
        self.topicID = topicID; self.ticketPrices = ticketPrices
    }
    /// Builds from the editor's fresh read: every server ticket needs a typed, non-negative price
    /// with at most two decimals. Missing ticket IDs or prices never default to free.
    public init(topicID: Int, tickets: [ProjectEditTicket], prices: [String: String]) throws {
        var result: [Int: Decimal] = [:]
        for ticket in tickets {
            guard let id = OperationAdapterHTTP.positiveID(ticket.localMetadata["id"]),
                  let price = ProjectEditValidation.decimal(prices[ticket.id] ?? ticket.price), result[id] == nil else { throw PublisherLifecycleError.incomplete }
            result[id] = price
        }
        try self.init(topicID: topicID, ticketPrices: result)
    }
    static func validPrice(_ value: Decimal) -> Bool {
        var v = value, rounded = Decimal(); NSDecimalRound(&rounded, &v, 2, .plain)
        return !value.isNaN && value >= 0 && rounded == value && value <= Decimal(string: "99999999.99")!
    }
    public var fields: [String: ProjectEditJSON] {
        var prices: [String: ProjectEditJSON] = [:]
        for (id, price) in ticketPrices { prices[String(id)] = .number(price) }
        return ["topicId": .number(Decimal(topicID)), "ticketPrices": .object(prices)]
    }
    /// data {topicId, lifecycle:3}; any other shape is an unknown outcome.
    public func acknowledged(_ data: ProjectEditJSON) -> Bool {
        guard let b = data.object else { return false }
        return PublisherValue.integer(b["topicId"]) == topicID && PublisherValue.integer(b["lifecycle"]) == 3
    }
}

public extension ProjectEditDraft {
    /// Recruiting chapters with a server chapter ID: the merchant slots an author may fill.
    var selfSupplySlots: [CoopFlowSelfSupplySlot] {
        guard product == .freeExplore else { return [] }
        return chapters.compactMap { chapter in
            guard chapter.preserved["recruitEnabled"]?.integer == 1,
                  let id = OperationAdapterHTTP.positiveID(chapter.preserved["id"]) else { return nil }
            return CoopFlowSelfSupplySlot(chapterID: id, name: chapter.name)
        }
    }
}

/// Dormant adapters on the existing publisher client. Reads need the endpoint in the read grant;
/// publishing and self-supply each need their own grant. All default to nil (off).
public extension PublisherLifecycleHTTP {
    var canPublishForSale: Bool {
        guard let credential = credentials() else { return false }
        return permits(FreeExploreSaleRoute.publishPath, grant: grants.freeExploreSale, credential: credential)
    }
    var canSelfSupply: Bool {
        guard let credential = credentials() else { return false }
        return permits(CoopFlowSelfSupplyRoute.supplyPath, grant: grants.selfSupply, credential: credential)
    }
    func saleReadiness(topicID: Int) async throws -> FreeExploreSaleReadiness {
        let path = FreeExploreSaleRoute.readinessPath
        guard topicID > 0, let credential = credentials(), permits(path, grant: grants.reads, credential: credential) else { throw PublisherLifecycleError.unavailable }
        guard var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
        components.queryItems = [URLQueryItem(name: "topicId", value: String(topicID))]
        guard let url = components.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credential.token, forHTTPHeaderField: "Authorization")
        let envelope = try await send(request, credential: credential)
        return try FreeExploreSaleReadiness(envelope["data"] ?? .null, expectedTopicID: topicID)
    }
    func publishForSale(_ value: FreeExplorePublishRequest) async throws -> PublisherLifecycleOutcome {
        let path = FreeExploreSaleRoute.publishPath
        guard let credential = credentials(), permits(path, grant: grants.freeExploreSale, credential: credential) else { return .notSent }
        let envelope: [String: ProjectEditJSON]
        do { envelope = try await send(request(path: path, fields: value.fields, json: true, credential: credential), credential: credential) }
        catch PublisherLifecycleError.rejected(let message) { return .rejected(message) }
        catch PublisherLifecycleError.stale { return .notSent }
        catch { return .unknown }
        return value.acknowledged(envelope["data"] ?? .null) ? .acknowledged(message: envelope["msg"]?.text, newTopicID: nil) : .unknown
    }
    func selfSupply(_ value: CoopFlowSelfSupplyRequest) async throws -> Int {
        try CoopFlowSelfSupplyRequest.offerID(await coopWrite(value.path, body: value.body))
    }
    func withdrawSelfSupply(_ value: CoopFlowSelfSupplyWithdrawal) async throws -> Int {
        try CoopFlowSelfSupplyWithdrawal.lifecycle(await coopWrite(value.path, body: value.body))
    }
    private func coopWrite(_ path: String, body: CoopFlowJSON) async throws -> CoopFlowJSON {
        guard CoopFlowSelfSupplyRoute.paths.contains(path), let credential = credentials(),
              permits(path, grant: grants.selfSupply, credential: credential) else { throw CoopFlowFailure.disabled }
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: path, body: body.canonical(), token: credential.token)
        let envelope = try await send(request, credential: credential)
        let data = try JSONDecoder().decode(CoopFlowJSON.self, from: JSONEncoder().encode(envelope["data"] ?? .null))
        return data
    }
}
