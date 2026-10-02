#if DEBUG
import SwiftUI

/// Explicit synthetic fixture only. No transport, model provider, credentials or grants.
@MainActor private final class MerchantTemplateAssistFixtureClient: MerchantTemplateAssistServing {
    let session: PublishingSession? = .init(namespace: "synthetic-assist", accountID: 901, epoch: UUID(), role: "merchant", region: .china)
    var canGenerate: Bool { true }
    func generate(_ input: MerchantTemplateAssistInput) async throws -> MerchantTemplateAssistResult {
        if ProcessInfo.processInfo.arguments.contains("--merchant-template-assist-permission") { throw MerchantTemplateAssistFailure.permission }
        if ProcessInfo.processInfo.arguments.contains("--merchant-template-assist-provider") { throw MerchantTemplateAssistFailure.provider }
        return try .init(.object(["template": .object([
            "title": .string("Synthetic riddle"), "questionAnswer": .string("Lantern"), "validationMethod": .number(1),
            "description": .string("A synthetic local draft"), "hint1": .string("Look by the door"), "medalName": .string("Synthetic badge")
        ])]))
    }
    func cancel() {}
}
@MainActor func merchantTemplateAssistFixture(_ coordinator: MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow {
    .init(coordinator: coordinator, client: MerchantTemplateAssistFixtureClient())
}
#endif
