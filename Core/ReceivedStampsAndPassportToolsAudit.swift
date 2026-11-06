import Foundation

/// Pure self-contained audit of `I00+I11` received stamps (`RoamReceivedStampRead` & `RoamReceivedStampPresentation`)
/// and `w2-09` passport private tools (`capsule`, `exploration-goals`, `exploration-export`,
/// `exploration-anniversary`, `monthly-recap`) + `RoamPrivateTools.xcstrings` bilingual completeness.
public enum ReceivedStampsAndPassportToolsAudit {

    // MARK: - Canonical Constants & Enums

    public static let receivedStampRoutePath = "api/roam/stamp/received"
    public static let maxReceivedStampPageSize = 50
    public static let roamPrivateToolsTableName = "RoamPrivateTools"

    public enum PassportPrivateTool: String, CaseIterable, Equatable, Sendable {
        case capsule = "capsule"
        case explorationGoals = "exploration-goals"
        case explorationExport = "exploration-export"
        case explorationAnniversary = "exploration-anniversary"
        case monthlyRecap = "monthly-recap"

        public var miniProgramSubpackagePath: String {
            "subpackageRoam/\(rawValue)"
        }
    }

    public static let expectedPrivateToolSlugs: [String] = PassportPrivateTool.allCases.map(\.rawValue)

    public enum AuditViolation: Equatable, Sendable {
        case invalidReceivedStampGrantPaths([String])
        case invalidReceivedStampPageSize(Int)
        case crossAccountOrEpochStampReadbackLeaked(expectedAccountID: Int, actualAccountID: Int, expectedEpoch: Int, actualEpoch: Int)
        case duplicateOrNonPositiveStampIDs([Int])
        case unmoderatedHiddenStampDisplayed(stampID: Int)
        case missingPassportPrivateTools([String])
        case liveMutationEnabledOnPassportPrivateTool(toolSlug: String)
        case incompleteRoamPrivateToolsLocalization(missingOrEmptyKeys: [String])
    }

    // MARK: - Pillar 1: I00+I11 RoamReceivedStampRead & RoamReceivedStampPresentation Account-Fenced Readback

    public struct StampRowCandidate: Equatable, Sendable {
        public let id: Int
        public let isVisible: Bool

        public init(id: Int, isVisible: Bool = true) {
            self.id = id
            self.isVisible = isVisible
        }
    }

    public struct ReceivedStampReadbackEvaluation: Equatable, Sendable {
        public let grantedPaths: Set<String>
        public let pageSize: Int
        public let activeAccountID: Int
        public let replyAccountID: Int
        public let activeEpoch: Int
        public let replyEpoch: Int
        public let visibleStampIDs: [Int]
        public let isGrantExact: Bool
        public let isAccountFenceIntact: Bool
        public let violations: [AuditViolation]

        public var isCompliant: Bool { violations.isEmpty }

        public init(
            grantedPaths: Set<String> = [ReceivedStampsAndPassportToolsAudit.receivedStampRoutePath],
            pageSize: Int = 20,
            activeAccountID: Int,
            replyAccountID: Int,
            activeEpoch: Int = 1,
            replyEpoch: Int = 1,
            rawRows: [StampRowCandidate] = [],
            displayedStampIDs: [Int]? = nil
        ) {
            self.grantedPaths = grantedPaths
            self.pageSize = pageSize
            self.activeAccountID = activeAccountID
            self.replyAccountID = replyAccountID
            self.activeEpoch = activeEpoch
            self.replyEpoch = replyEpoch

            let exactGrant = grantedPaths == [ReceivedStampsAndPassportToolsAudit.receivedStampRoutePath]
            self.isGrantExact = exactGrant

            let fenceOK = activeAccountID > 0
                && activeAccountID == replyAccountID
                && activeEpoch == replyEpoch
            self.isAccountFenceIntact = fenceOK

            let moderatedIDs = rawRows.filter(\.isVisible).map(\.id)
            let effectiveDisplayed = displayedStampIDs ?? (fenceOK ? moderatedIDs : [])
            self.visibleStampIDs = effectiveDisplayed

            var foundViolations: [AuditViolation] = []
            if !exactGrant {
                foundViolations.append(.invalidReceivedStampGrantPaths(grantedPaths.sorted()))
            }
            if pageSize < 1 || pageSize > ReceivedStampsAndPassportToolsAudit.maxReceivedStampPageSize || rawRows.count > pageSize {
                foundViolations.append(.invalidReceivedStampPageSize(pageSize))
            }
            if !fenceOK && !effectiveDisplayed.isEmpty {
                foundViolations.append(
                    .crossAccountOrEpochStampReadbackLeaked(
                        expectedAccountID: activeAccountID,
                        actualAccountID: replyAccountID,
                        expectedEpoch: activeEpoch,
                        actualEpoch: replyEpoch
                    )
                )
            }

            var seen = Set<Int>()
            var invalidIDs: [Int] = []
            for row in rawRows {
                if row.id <= 0 || !seen.insert(row.id).inserted {
                    invalidIDs.append(row.id)
                }
            }
            if !invalidIDs.isEmpty {
                foundViolations.append(.duplicateOrNonPositiveStampIDs(invalidIDs))
            }

            let hiddenIDs = Set(rawRows.filter { !$0.isVisible }.map(\.id))
            for id in effectiveDisplayed where hiddenIDs.contains(id) {
                foundViolations.append(.unmoderatedHiddenStampDisplayed(stampID: id))
            }

            self.violations = foundViolations
        }
    }

    public static func auditReceivedStampReadback(
        grantedPaths: Set<String> = [receivedStampRoutePath],
        pageSize: Int = 20,
        activeAccountID: Int,
        replyAccountID: Int,
        activeEpoch: Int = 1,
        replyEpoch: Int = 1,
        rawRows: [StampRowCandidate] = [],
        displayedStampIDs: [Int]? = nil
    ) -> ReceivedStampReadbackEvaluation {
        ReceivedStampReadbackEvaluation(
            grantedPaths: grantedPaths,
            pageSize: pageSize,
            activeAccountID: activeAccountID,
            replyAccountID: replyAccountID,
            activeEpoch: activeEpoch,
            replyEpoch: replyEpoch,
            rawRows: rawRows,
            displayedStampIDs: displayedStampIDs
        )
    }

    // MARK: - Pillar 2: w2-09 5 Passport Private Tools Audit

    public struct PassportPrivateToolsEvaluation: Equatable, Sendable {
        public let registeredToolSlugs: [String]
        public let missingToolSlugs: [String]
        public let toolsWithLiveMutationEnabled: [String]
        public let violations: [AuditViolation]

        public var hasAllFiveTools: Bool {
            missingToolSlugs.isEmpty && Set(registeredToolSlugs).isSuperset(of: expectedPrivateToolSlugs)
        }

        public var isCompliant: Bool { violations.isEmpty }

        public init(
            registeredToolSlugs: [String] = ReceivedStampsAndPassportToolsAudit.expectedPrivateToolSlugs,
            toolsWithLiveMutationEnabled: [String] = []
        ) {
            self.registeredToolSlugs = registeredToolSlugs
            let present = Set(registeredToolSlugs)
            let missing = ReceivedStampsAndPassportToolsAudit.expectedPrivateToolSlugs.filter { !present.contains($0) }
            self.missingToolSlugs = missing
            self.toolsWithLiveMutationEnabled = toolsWithLiveMutationEnabled

            var foundViolations: [AuditViolation] = []
            if !missing.isEmpty {
                foundViolations.append(.missingPassportPrivateTools(missing))
            }
            for slug in toolsWithLiveMutationEnabled {
                foundViolations.append(.liveMutationEnabledOnPassportPrivateTool(toolSlug: slug))
            }
            self.violations = foundViolations
        }
    }

    public static func auditPassportPrivateTools(
        registeredToolSlugs: [String] = expectedPrivateToolSlugs,
        toolsWithLiveMutationEnabled: [String] = []
    ) -> PassportPrivateToolsEvaluation {
        PassportPrivateToolsEvaluation(
            registeredToolSlugs: registeredToolSlugs,
            toolsWithLiveMutationEnabled: toolsWithLiveMutationEnabled
        )
    }

    // MARK: - Pillar 3: Bilingual RoamPrivateTools.xcstrings Completeness Audit

    public struct BilingualStringEntry: Equatable, Sendable {
        public let key: String
        public let english: String?
        public let simplifiedChinese: String?

        public init(key: String, english: String?, simplifiedChinese: String?) {
            self.key = key
            self.english = english
            self.simplifiedChinese = simplifiedChinese
        }

        public var isComplete: Bool {
            guard let en = english?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty,
                  let zh = simplifiedChinese?.trimmingCharacters(in: .whitespacesAndNewlines), !zh.isEmpty else {
                return false
            }
            return true
        }
    }

    public struct RoamPrivateToolsCatalogEvaluation: Equatable, Sendable {
        public let tableName: String
        public let totalKeyCount: Int
        public let incompleteKeys: [String]
        public let violations: [AuditViolation]

        public var isBilingualComplete: Bool { totalKeyCount > 0 && incompleteKeys.isEmpty && violations.isEmpty }

        public init(
            tableName: String = ReceivedStampsAndPassportToolsAudit.roamPrivateToolsTableName,
            entries: [BilingualStringEntry]
        ) {
            self.tableName = tableName
            self.totalKeyCount = entries.count
            let incomplete = entries.filter { !$0.isComplete }.map(\.key).sorted()
            self.incompleteKeys = incomplete

            var foundViolations: [AuditViolation] = []
            if entries.isEmpty {
                foundViolations.append(.incompleteRoamPrivateToolsLocalization(missingOrEmptyKeys: ["<empty_catalog>"]))
            } else if !incomplete.isEmpty {
                foundViolations.append(.incompleteRoamPrivateToolsLocalization(missingOrEmptyKeys: incomplete))
            }
            self.violations = foundViolations
        }
    }

    public static func auditRoamPrivateToolsCatalog(
        entries: [BilingualStringEntry]
    ) -> RoamPrivateToolsCatalogEvaluation {
        RoamPrivateToolsCatalogEvaluation(entries: entries)
    }
}
