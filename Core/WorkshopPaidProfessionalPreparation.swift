import Foundation

/// Reuses the existing independently approved protected-body and owner generic-draft metadata
/// readers. No metadata value is substituted for protected text or a professional authoring schema.
@MainActor public final class WorkshopPaidProfessionalPreparation {
    private let bodyReader: any WorkshopPaidInstalledTextReading
    private let installReader: any WorkshopPaidInstallServing
    public init(bodyReader: any WorkshopPaidInstalledTextReading, installReader: any WorkshopPaidInstallServing) {
        self.bodyReader = bodyReader; self.installReader = installReader
    }
    func body(_ reference: WorkshopPaidInstalledTextReference, lifetime: WorkshopPaidProfessionalLifetime) async throws -> WorkshopPaidInstalledText {
        try lifetime.check()
        let bridge = WorkshopPaidInstalledTextLifetime { (try? lifetime.check()) != nil }
        defer { bridge.revoke() }
        let value = try await bodyReader.detail(reference, lifetime: bridge)
        try lifetime.check(); return value
    }
    func currentDraft(_ reference: WorkshopPaidInstalledTextReference, body: WorkshopPaidInstalledText,
                      lifetime: WorkshopPaidProfessionalLifetime) async throws -> WorkshopPaidInstallTarget {
        try lifetime.check()
        let bridge = WorkshopPaidInstallLifetime { (try? lifetime.check()) != nil }
        defer { bridge.revoke() }
        var cursor: Int64?
        // Bound this read action. An older/absent target remains unavailable, never fabricated.
        for _ in 0..<10 {
            let page = try await installReader.targets(licenseId: reference.item.licenseId, before: cursor, lifetime: bridge)
            try lifetime.check()
            if let value = page.items.first(where: { $0.targetDraftId == body.originalTargetDraftID }) {
                guard value.businessType == "TOPIC" else { throw WorkshopPaidProfessionalIssue.invalid }; return value
            }
            guard let next = page.nextBeforeDraftId, next > body.originalTargetDraftID else { throw WorkshopPaidProfessionalIssue.unavailable }
            guard cursor == nil || next < cursor! else { throw WorkshopPaidProfessionalIssue.malformed }; cursor = next
        }
        throw WorkshopPaidProfessionalIssue.unavailable
    }
}
