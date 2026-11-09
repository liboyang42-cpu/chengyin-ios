import Foundation

/// The legacy v1 `api/workshop/purchased/*` routes now answer the standard AjaxResult envelope
/// `{"code":409,"msg":"WORKSHOP_CONTRACT_UPGRADE_REQUIRED"}` (HTTP 200). That handler executes
/// nothing: it is a definite "this client must update", never an empty list, a failed read or an
/// unknown write outcome. A pending install command stays saved; it is not acknowledged here.
public enum WorkshopContractUpgrade {
    public static let message = "WORKSHOP_CONTRACT_UPGRADE_REQUIRED"
    public static let code = 409
    private struct Envelope: Decodable { let code: Int?; let msg: String? }

    /// True only for the exact refusal: business code 409 (or HTTP 409) together with the exact message.
    public static func isRequired(data: Data, status: Int) -> Bool {
        guard status == code || (200..<300).contains(status), !data.isEmpty, data.count <= 4_096,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.msg == message else { return false }
        return envelope.code == code || (envelope.code == nil && status == code)
    }
}
