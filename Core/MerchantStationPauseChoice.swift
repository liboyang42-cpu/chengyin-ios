import Foundation

/// An explicit choice from this station's current approved fallback projection.
/// Keep identity and displayed consequences together; array order is not identity.
public struct MerchantStationPauseChoice: Hashable {
    public let sourceNodeID: Int
    public let targetNodeID: Int
    public let planCode: String
    public let planVersion: Int
    public let nodeName: String
    public let playerMessage: String
    public init?(option: MerchantContentValue) {
        guard let source = option["sourceNodeId"].safeInteger, source > 0,
              let target = option["nodeId"].safeInteger, target > 0, source != target,
              let code = option["planCode"].text,
              code.range(of: #"^[A-Z][A-Z0-9_]{1,63}$"#, options: .regularExpression) != nil,
              let version = option["planVersion"].safeInteger, version > 0,
              let name = option["nodeName"].text, !name.isEmpty,
              let message = option["playerMessage"].text, !message.isEmpty else { return nil }
        sourceNodeID = source; targetNodeID = target; planCode = code; planVersion = version
        nodeName = name; playerMessage = message
    }
    public static func available(in projection: MerchantStationProjection, nodeID: Int) -> [Self] {
        projection.fallbackOptions.compactMap(Self.init(option:)).filter { $0.sourceNodeID == nodeID }
    }
    /// Nil is the user's explicit no-fallback choice, never an automatic replacement
    /// for a missing, reordered or changed previously selected plan.
    public static func pausePayload(reasonCode: String, reason: String, resumeEta: String,
                                    selection: Self?, projection: MerchantStationProjection,
                                    nodeID: Int) throws -> [String: MerchantContentValue] {
        var fields: [String: MerchantContentValue] = ["reasonCode": .string(reasonCode), "resumeEta": .string(resumeEta)]
        let note = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { fields["reason"] = .string(note) }
        if let selection {
            let choices = available(in: projection, nodeID: nodeID)
            guard selection.sourceNodeID == nodeID, choices.filter({ $0 == selection }).count == 1 else {
                throw MerchantContentFailure.invalid
            }
            fields["fallbackPlanCode"] = .string(selection.planCode)
            fields["fallbackPlanVersion"] = .integer(selection.planVersion)
        }
        return fields
    }
}

public extension MerchantStationCommand {
    /// Presentation only. fields()/validate(projection:) still own command validity.
    var pausesWithoutFallback: Bool {
        action == .pause && payload["fallbackPlanCode"] == nil && payload["fallbackPlanVersion"] == nil
    }
}
