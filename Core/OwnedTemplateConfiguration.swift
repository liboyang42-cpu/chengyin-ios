import Foundation
import Observation

/// Exact legacy QA fields shared by the professional forms and owner-only read projection.
public enum TemplateQAField: String, CaseIterable, Hashable {
    case questionName, questionImg, questionAudio, questionAnswer, questionA, questionB, questionC, questionD
    case correctAnswer, hint1, hint2, answerReveal
    public var draftPath: WritableKeyPath<TemplateAuthoringDraft, String?> {
        switch self {
        case .questionName: return \.questionName; case .questionImg: return \.questionImg
        case .questionAudio: return \.questionAudio; case .questionAnswer: return \.questionAnswer
        case .questionA: return \.questionA; case .questionB: return \.questionB
        case .questionC: return \.questionC; case .questionD: return \.questionD
        case .correctAnswer: return \.correctAnswer; case .hint1: return \.hint1
        case .hint2: return \.hint2; case .answerReveal: return \.answerReveal
        }
    }
}
public enum OwnedTemplateText: Equatable {
    case missing, null, value(String), unsupported
    public var value: String? { if case .value(let value) = self { return value }; return nil }
    static func read(_ key: String, from fields: [String: PlayWireValue]) -> Self {
        guard let raw = fields[key] else { return .missing }
        switch raw { case .null: return .null; case .string(let text): return .value(text); default: return .unsupported }
    }
}
public enum OwnedTemplateProvenance: Equatable { case missing, null, value(Int), unsupported }
public struct OwnedTemplateStoryBeat: Identifiable, Equatable {
    public let id: Int
    public let text: OwnedTemplateText
    public let tag: OwnedTemplateText
    public let images: [String]
    public let unsupportedFields: [String]
}
/// Never Codable and never a publishing draft. Construct only after exact owner verification.
/// The immutable original response remains private/in-memory, including unknown/missing fields.
public struct OwnedTemplateConfigurationSnapshot {
    public let id: MemberPlayTemplateID
    public let accountID: Int
    public let title: OwnedTemplateText
    public let provenance: OwnedTemplateProvenance
    public let validationMethod: Int?
    public let sensor: OwnedTemplateSensorConfiguration?
    /// These methods are recognized for inspection only, never added to the writable enum.
    public var specializedMethodLabel: String? {
        switch validationMethod {
        case 6: return "templateOwnerSensor.preference"
        case 7: return "templateOwnerSensor.challenge"
        default: return nil
        }
    }
    public let story: [OwnedTemplateStoryBeat]
    public let storyText: OwnedTemplateText
    public let preferenceJson: OwnedTemplateText
    public let medalStyle: OwnedTemplateText
    public let unsupportedFields: [String]
    private let qa: [TemplateQAField: OwnedTemplateText]
    private let originalResponse: Data
    public var supportedQAMethod: TemplateAuthoringMethod? {
        guard let validationMethod, [1, 3].contains(validationMethod) else { return nil }
        return TemplateAuthoringMethod(rawValue: validationMethod)
    }
    public func field(_ field: TemplateQAField) -> OwnedTemplateText { qa[field] ?? .missing }
    func hasExactBaseline(_ bytes: Data) -> Bool { originalResponse == bytes }
    init(response: Data, requestedID: MemberPlayTemplateID, accountID: Int) throws {
        guard response.count <= 1_048_576, accountID > 0 else { throw APIError.malformedResponse }
        let envelope = try JSONDecoder().decode(PlayWireValue.self, from: response)
        guard envelope["code"].tolerantInteger == 200, let fields = envelope["data"].object, fields["id"]?.integer == requestedID.rawValue,
              fields["memberId"]?.integer == accountID else { throw APIError.malformedResponse }
        // Only after identity/owner validation may author-only values enter this projection.
        self.id = requestedID; self.accountID = accountID; originalResponse = response
        title = .read("title", from: fields); storyText = .read("storyText", from: fields)
        preferenceJson = .read("preferenceJson", from: fields)
        medalStyle = .read("medalStyle", from: fields)
        validationMethod = fields["validationMethod"]?.integer
        sensor = validationMethod == 7 ? OwnedTemplateSensorConfiguration(
            type: .read("sensorType", from: fields), config: .read("sensorConfig", from: fields)) : nil
        qa = Dictionary(uniqueKeysWithValues: TemplateQAField.allCases.map { ($0, OwnedTemplateText.read($0.rawValue, from: fields)) })
        if let value = fields["originalTemplateId"] {
            if case .null = value { provenance = .null }
            else if let id = value.integer, id >= 0 { provenance = .value(id) }
            else { provenance = .unsupported }
        } else { provenance = .missing }
        let known = Set(TemplateQAField.allCases.map(\.rawValue) + ["id", "memberId", "title", "originalTemplateId", "validationMethod", "storyJson", "storyText"])
        var unsupported = fields.keys.filter { !known.contains($0) }
        unsupported += qa.filter { $0.value == .unsupported }.map { $0.key.rawValue }
        if validationMethod != 1 && validationMethod != 3 { unsupported.append("validationMethod") }
        if title == .unsupported { unsupported.append("title") }
        if provenance == .unsupported { unsupported.append("originalTemplateId") }
        if storyText == .unsupported { unsupported.append("storyText") }
        unsupportedFields = Array(Set(unsupported)).sorted()
        switch fields["storyJson"] {
        case nil, .null?: story = []
        case .string(let raw)?:
            if raw.isEmpty { story = [] }
            else {
                let rows = try JSONDecoder().decode([PlayWireValue].self, from: Data(raw.utf8))
                guard rows.count <= 200, rows.allSatisfy({ $0.object != nil }) else { throw APIError.malformedResponse }
                story = rows.enumerated().map { index, row in
                    let value = row.object ?? [:]
                    var unknown = value.keys.filter { !["text", "tag", "img", "imgs"].contains($0) }
                    let images: [String]
                    if let array = row["imgs"].array {
                        images = array.compactMap { if case .string(let text) = $0 { return text }; return nil }
                        if images.count != array.count { unknown.append("imgs") }
                    } else if case .null = row["imgs"] {
                        switch row["img"] {
                        case .null: images = []
                        case .string(let legacy): images = legacy.isEmpty ? [] : [legacy]
                        default: images = []; unknown.append("img")
                        }
                    } else { images = []; unknown.append("imgs") }
                    let text = OwnedTemplateText.read("text", from: value), tag = OwnedTemplateText.read("tag", from: value)
                    if text == .unsupported { unknown.append("text") }; if tag == .unsupported { unknown.append("tag") }
                    return .init(id: index, text: text, tag: tag, images: images, unsupportedFields: Array(Set(unknown)).sorted())
                }
            }
        default: throw APIError.malformedResponse
        }
    }
}

/// Session-scoped owner-only host. No save, mutation transport, local draft store or journal.
@available(macOS 14.0, *)
@MainActor @Observable public final class OwnedTemplateConfigurationHost {
    @ObservationIgnored private let transport: TemplateShelfReadTransport?
    @ObservationIgnored private var retained: OwnedTemplateConfigurationSnapshot?
    private var contentRevision = 0
    @ObservationIgnored private var generation = 0
    public private(set) var loading = false
    public private(set) var failed = false
    public var available: Bool { transport?.available == true }
    public var snapshot: OwnedTemplateConfigurationSnapshot? {
        _ = contentRevision
        guard available else { retained = nil; return nil }; return retained
    }
    public init(transport: TemplateShelfReadTransport?) { self.transport = transport }
    public func clear() { generation += 1; retained = nil; contentRevision += 1; loading = false; failed = false }
    public func load(id: MemberPlayTemplateID) async {
        clear(); guard let transport, available else { failed = true; return }
        let stamp = generation; loading = true
        do {
            let result = try await transport.ownedConfiguration(id, acceptsResult: { [weak self] in
                self?.generation == stamp
            })
            guard stamp == generation, available, !Task.isCancelled else { if stamp == generation { clear() }; return }
            retained = result; contentRevision += 1; loading = false
        } catch {
            guard stamp == generation else { return }
            guard available, !Task.isCancelled else { clear(); return }
            loading = false; failed = true
        }
    }
}
