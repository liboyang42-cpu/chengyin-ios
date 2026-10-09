import Foundation

/// Lossless known-field carry-over is independent of permission. This policy only
/// recognizes an unchanged existing REVSHARE configuration; it never authorizes
/// a save, role, content slot, upload, creation or recruitment edit.
public enum ProjectChapterRecruitmentCarryOver {
    public static let fields = ["recruitEnabled", "termsMode", "categoryId", "category", "maxMerchant",
                                "perkMinValue", "maxPerHeadFee", "allowedValidationMethods", "maxNodeXp"]
    public static func rawFields(_ source: [String: ProjectEditJSON]) -> [String: ProjectEditJSON] {
        var result: [String: ProjectEditJSON] = [:]
        for key in fields { result[key] = source[key] }
        return result
    }
    public static func restoreRawFields(_ source: [String: ProjectEditJSON], in chapter: inout ProjectEditChapter) {
        // Assignment of nil removes initializer defaults for absent server fields.
        // Never parse, coerce, normalize or invent a missing recruitment value.
        for key in fields { chapter.preserved[key] = source[key] }
    }
    private static func revshare(_ fields: [String: ProjectEditJSON]) -> Bool {
        fields["termsMode"]?.text?.utf8.elementsEqual("REVSHARE".utf8) == true
    }
    private static func hasFee(_ fields: [String: ProjectEditJSON]) -> Bool {
        fields["maxPerHeadFee"] != nil && fields["maxPerHeadFee"] != .null
    }
    private static func needsProof(_ rows: [[String: ProjectEditJSON]], baseline: ProjectEditSnapshot?) -> Bool {
        rows.contains { revshare($0) || hasFee($0) } ||
        baseline?.draft.chapters.contains { revshare($0.preserved) || hasFee($0.preserved) } == true
    }
    public static func matchesFresh(_ fresh: ProjectEditSnapshot?, baseline: ProjectEditSnapshot) -> Bool {
        guard needsProof([], baseline: baseline) else { return true }
        guard let fresh, let bytes = ProjectEditPendingMaterials.exactData(baseline) else { return false }
        return ProjectEditPendingMaterials.exactData(fresh) == bytes
    }
    public static func allows(_ draft: ProjectEditDraft, baseline: ProjectEditSnapshot?) -> Bool {
        let rows = draft.chapters.map(\.preserved)
        guard needsProof(rows, baseline: baseline) else { return true }
        guard let baseline, let topicID = baseline.topicID, topicID > 0, baseline.scope == .full,
              draft.product == .freeExplore, baseline.draft.product == draft.product,
              draft.owner == baseline.draft.owner, let club = draft.clubID, club > 0, baseline.draft.clubID == club,
              draft.openMerchantPool == baseline.draft.openMerchantPool,
              !baseline.draft.baseRevision.isEmpty, draft.baseRevision.utf8.elementsEqual(baseline.draft.baseRevision.utf8),
              draft.chapters.map({ Data($0.id.utf8) }) == baseline.draft.chapters.map({ Data($0.id.utf8) }),
              !draft.chapters.contains(where: { $0.id.isEmpty }),
              Set(draft.chapters.map(\.id)).count == draft.chapters.count else { return false }
        return matches(rows, baseline: baseline)
    }
    public static func validatePayload(_ payload: [String: ProjectEditJSON], baseline: ProjectEditSnapshot?) throws {
        // Existing WHITELIST routing independently verifies the stripped body.
        if baseline?.scope == .whitelist, payload["chapters"] == nil { return }
        let rows = payload["chapters"]?.array?.compactMap(\.object) ?? []
        guard needsProof(rows, baseline: baseline) else { return }
        guard let baseline, baseline.scope == .full, let topicID = baseline.topicID, topicID > 0,
              payload["id"]?.integer == topicID,
              payload["scope"]?.text?.utf8.elementsEqual(baseline.draft.owner.rawValue.utf8) == true,
              payload["productType"]?.integer == ProjectEditProduct.freeExplore.rawValue,
              baseline.draft.product == .freeExplore, let club = baseline.draft.clubID, club > 0,
              payload["clubId"] == .number(Decimal(club)),
              payload["openMerchantPool"] == .number(baseline.draft.openMerchantPool ? 1 : 0),
              !baseline.draft.baseRevision.isEmpty,
              let array = payload["chapters"]?.array, rows.count == array.count,
              matches(rows, baseline: baseline) else { throw ProjectEditError.invalidDraft }
        // Wire payload has no revision field. The unchanged HTTP adapter still
        // binds this snapshot to fresh edit-detail and current session approval.
    }
    private static func matches(_ rows: [[String: ProjectEditJSON]], baseline: ProjectEditSnapshot) -> Bool {
        let original = baseline.draft.chapters.map(\.preserved)
        guard rows.count == original.count, !rows.isEmpty else { return false }
        var ids = Set<Int>()
        for (row, before) in zip(rows, original) {
            guard let id = before["id"]?.integer, id > 0, ids.insert(id).inserted, row["id"]?.integer == id,
                  let originalBytes = ProjectEditPendingMaterials.exactData(rawFields(before)),
                  ProjectEditPendingMaterials.exactData(rawFields(row)) == originalBytes else { return false }
            if revshare(before) || hasFee(before) {
                guard revshare(before), validRevshareShape(before) else { return false }
            }
        }
        return true
    }
    private static func optionalInteger(_ raw: ProjectEditJSON?, range: ClosedRange<Int>) -> Bool {
        guard let raw, raw != .null else { return true }
        guard let value = raw.integer else { return false }; return range.contains(value)
    }
    private static func optionalText(_ raw: ProjectEditJSON?) -> Bool { raw == nil || raw == .null || raw?.text != nil }
    private static func validRevshareShape(_ row: [String: ProjectEditJSON]) -> Bool {
        guard optionalInteger(row["recruitEnabled"], range: 0...1), optionalInteger(row["maxMerchant"], range: 0...127),
              optionalInteger(row["maxNodeXp"], range: 0...2_147_483_647),
              optionalInteger(row["categoryId"], range: 0...2_147_483_647), optionalText(row["category"]),
              row["perkMinValue"] == nil || row["perkMinValue"] == .null,
              validFee(row["maxPerHeadFee"]), validMethods(row["allowedValidationMethods"]) else { return false }
        return row["recruitEnabled"]?.integer != 1 || (row["categoryId"]?.integer ?? 0) > 0
    }
    private static func validFee(_ raw: ProjectEditJSON?) -> Bool {
        let value: Decimal
        switch raw {
        case .number(let number)?: value = number
        case .string(let text)?:
            // Preserve the string unchanged; support the mini's explicit ASCII
            // positive-decimal grammar only (no trim, sign or exponent rewrite).
            let bytes = Array(text.utf8), parts = bytes.split(separator: 46, omittingEmptySubsequences: false)
            guard !bytes.isEmpty, parts.count <= 2, !parts[0].isEmpty,
                  parts.allSatisfy({ $0.allSatisfy { (48...57).contains($0) } }),
                  parts.count == 1 || (1...2).contains(parts[1].count),
                  let parsed = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return false }
            value = parsed
        default: return false
        }
        guard !value.isNaN, value > 0 else { return false }
        var scaled = value * 100, rounded = Decimal()
        guard !scaled.isNaN else { return false }
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return rounded == scaled
    }
    private static func validMethods(_ raw: ProjectEditJSON?) -> Bool {
        guard let raw, raw != .null else { return true }
        guard let text = raw.text else { return false }
        func trim(_ bytes: [UInt8]) -> [UInt8] { Array(bytes.drop(while: { $0 <= 32 }).reversed().drop(while: { $0 <= 32 }).reversed()) }
        let bytes = Array(text.utf8)
        if trim(bytes).isEmpty { return true }
        // Java String.split(",") drops trailing empty parts, and trim() removes
        // only U+0000...U+0020. Split literal UTF-8 comma, never Characters.
        var parts = bytes.split(separator: 44, omittingEmptySubsequences: false).map(Array.init)
        while parts.last?.isEmpty == true { parts.removeLast() }
        return parts.allSatisfy { let value = trim($0); return value.count == 1 && (49...53).contains(value[0]) }
    }
}
