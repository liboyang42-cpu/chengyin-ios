import Foundation

public enum ClubAIDesignFailure: Error, Equatable { case invalid, parse, empty, quota, identity, unavailable, unknown }
public struct ClubAIDesignInput: Equatable {
    public var idea: String
    public var style: String
    public var minutes: Int?
    public init(idea: String, style: String = "", minutes: Int? = nil) throws {
        guard !idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, minutes == nil || minutes! > 0 else { throw ClubAIDesignFailure.invalid }
        self.idea = idea.trimmingCharacters(in: .whitespacesAndNewlines); self.style = style.trimmingCharacters(in: .whitespacesAndNewlines); self.minutes = minutes
    }
    public var assistance: PublishingAssistance { .club(idea: idea, style: style.isEmpty ? nil : style, minutes: minutes) }
}
public struct ClubAIDesignResult: Equatable {
    public struct Node: Equatable {
        public let name: String
        public let address: String
        public let role: String
        public let task: String
        public let businessTime: String
    }
    public let title: String
    public let subtitle: String
    public let storyline: String
    public let fitReason: String
    public let tags: [String]
    public let risks: [String]
    public let minutes: Int?
    public let nodes: [Node]
    public let merchantSuggestions: [String]
    public let promoCopy: String
    public let traceID: String?
    public init(value: ProjectEditJSON) throws {
        guard let object = value.object else { throw ClubAIDesignFailure.parse }
        // VO contract says *any non-null* parseError invalidates every other field.
        if let error = object["parseError"], error != .null { throw ClubAIDesignFailure.parse }
        guard let rawPlan = object["plan"], rawPlan != .null else { throw ClubAIDesignFailure.empty }
        guard let plan = rawPlan.object else { throw ClubAIDesignFailure.parse }
        func text(_ key: String) -> String { plan[key]?.text ?? "" }
        func strings(_ value: ProjectEditJSON?) throws -> [String] {
            guard let value, value != .null else { return [] }
            guard let array = value.array, array.allSatisfy({ $0.text != nil }) else { throw ClubAIDesignFailure.parse }
            return array.compactMap(\.text)
        }
        title = text("title"); subtitle = text("subtitle"); storyline = text("storyline"); fitReason = text("fitReason")
        tags = try strings(plan["tags"]); risks = try strings(plan["risks"]); minutes = plan["estDurationMin"]?.integer
        if let rawNodes = plan["nodes"], rawNodes != .null, rawNodes.array == nil { throw ClubAIDesignFailure.parse }
        let rawNodes = plan["nodes"]?.array ?? []
        guard rawNodes.count <= 100 else { throw ClubAIDesignFailure.parse }
        nodes = try rawNodes.map { value in
            guard let row = value.object else { throw ClubAIDesignFailure.parse }
            return Node(name: row["merchantName"]?.text ?? "", address: row["address"]?.text ?? "", role: row["roleText"]?.text ?? "", task: row["task"]?.text ?? "", businessTime: row["businessTime"]?.text ?? "")
        }
        merchantSuggestions = try strings(object["merchantSuggestions"]); promoCopy = object["promoCopy"]?.text ?? ""; traceID = object["traceId"]?.text
        guard !title.isEmpty || !storyline.isEmpty || !nodes.isEmpty else { throw ClubAIDesignFailure.empty }
    }
    public func draft(clubID: Int) throws -> ProjectEditDraft {
        guard clubID > 0 else { throw ClubAIDesignFailure.invalid }
        var value = ProjectEditDraft(product: .city); value.clubID = clubID
        value.name = title; value.subtitle = subtitle; value.description = storyline
        value.preserved["aiGenerated"] = .number(1)
        if let traceID { value.preserved["aiTraceId"] = .string(traceID) }
        var chapter = ProjectEditChapter(); chapter.name = title; chapter.description = storyline
        chapter.nodes = nodes.map { item in
            var node = ProjectEditNode(); node.name = item.name; node.address = item.address
            node.description = [item.role, item.task].filter { !$0.isEmpty }.joined(separator: "\n")
            node.localMetadata["aiBusinessTimeSuggestion"] = .string(item.businessTime)
            // Club generation accepts an idea, not a user-confirmed place lookup. An AI
            // candidate/coordinate is never promoted to a verified native merchant/place.
            node.longitude = ""; node.latitude = ""; return node
        }
        value.chapters = [chapter]; return value
    }
}
@MainActor public protocol ClubAIDesignGenerating {
    func generate(_ input: ClubAIDesignInput, session: PublishingSession) async -> PublishingAuxiliaryOutcome
}
@MainActor public struct ClubAIDesignGenerator: ClubAIDesignGenerating {
    private let service: PublishingAuxiliaryService
    public init(service: PublishingAuxiliaryService) { self.service = service }
    public func generate(_ input: ClubAIDesignInput, session: PublishingSession) async -> PublishingAuxiliaryOutcome {
        do { let review = try service.prepare(input.assistance, session: session); return await service.confirm(review) }
        catch { return .notSent }
    }
}
@MainActor public final class ClubAIDesignFlow {
    private let generator: (any ClubAIDesignGenerating)?
    private let current: () -> PublishingSession?
    private var generation = 0
    private var resultSession: PublishingSession?
    private var storedResult: ClubAIDesignResult?
    private var storedInput: ClubAIDesignInput?
    private var storedGeneration: Int?
    private var resultOwnerRetired = false
    public var result: ClubAIDesignResult? {
        guard let resultSession else { return nil }
        if current() != resultSession {
            resultOwnerRetired = true; generation += 1; busy = false; clearResult(); return nil
        }
        guard !resultOwnerRetired, failure != .identity else { clearResult(); return nil }
        return storedResult
    }
    public var resultInput: ClubAIDesignInput? { result == nil ? nil : storedInput }
    public var resultGeneration: Int? { result == nil ? nil : storedGeneration }
    public var canAdoptResult: Bool { result != nil && !busy }
    public func resultIsPrevious(comparedTo input: ClubAIDesignInput?) -> Bool {
        guard result != nil, let storedInput else { return false }
        guard let input else { return true }
        return storedGeneration != generation || storedInput.minutes != input.minutes ||
            !storedInput.idea.utf8.elementsEqual(input.idea.utf8) || !storedInput.style.utf8.elementsEqual(input.style.utf8)
    }
    public private(set) var failure: ClubAIDesignFailure?
    public private(set) var busy = false
    public var isConfigured: Bool { generator != nil }
    public var canGenerate: Bool { isConfigured && !resultOwnerRetired && current() != nil && !busy && failure != .quota && failure != .identity && failure != .unknown }
    public init(generator: (any ClubAIDesignGenerating)?, current: @escaping () -> PublishingSession?) { self.generator = generator; self.current = current }
    private func clearResult() { storedResult = nil; storedInput = nil; storedGeneration = nil; resultSession = nil }
    public func cancel() { generation += 1; clearResult(); failure = nil; busy = false; resultOwnerRetired = false }
    public func generate(_ input: ClubAIDesignInput) async {
        _ = result // A changed owner cannot reuse an earlier result or queued generation.
        guard canGenerate else { if generator == nil { failure = .unavailable }; return }
        guard let generator, let session = current() else { failure = .unavailable; return }
        generation += 1; let request = generation; failure = nil; busy = true
        let outcome = await generator.generate(input, session: session)
        guard request == generation, current() == session, !Task.isCancelled else { if request == generation { cancel() }; return }
        busy = false
        switch outcome {
        case .acknowledged(let value):
            do {
                let candidate = try ClubAIDesignResult(value: value)
                storedResult = candidate; storedInput = input; storedGeneration = request; resultSession = session
            }
            catch { failure = error as? ClubAIDesignFailure ?? .parse }
        case .rejected(let message):
            if message.contains("今日AI次数已用完") { failure = .quota }
            else if message.contains("身份") || message.contains("登录") { failure = .identity }
            else { failure = .unavailable }
        case .unknown: failure = .unknown
        case .unavailable, .notSent: failure = .unavailable
        }
    }
    public func adopt(clubID: Int, generation expected: Int? = nil) throws -> ProjectEditDraft {
        guard !busy else { throw ClubAIDesignFailure.unavailable }
        guard resultSession != nil, current() == resultSession, let result else { throw ClubAIDesignFailure.identity }
        guard expected == nil || expected == storedGeneration else { throw ClubAIDesignFailure.invalid }
        return try result.draft(clubID: clubID)
    }
}
