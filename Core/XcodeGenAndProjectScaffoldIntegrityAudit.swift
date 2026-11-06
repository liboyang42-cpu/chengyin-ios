import Foundation

/// Pure value-type audit of Xcode project generation, SwiftPM/Xcode target boundaries,
/// `Questify.xcodeproj/project.pbxproj` zero-drift scaffold checks, and `.xcstrings` catalog
/// builder scripts:
/// - The 5 canonical targets (`QuestifyCore`, `QuestifyApp`, `QuestifyCoreTests`, `QuestifyAppUnitTests`, `QuestifyUITests`)
/// - Deterministic `tools/generate_project.py` & `tools/check_scaffold.py` verification (`project.pbxproj` zero drift)
/// - `tools/check_roam_private_tools.py` & `.xcstrings` catalog regeneration scripts (`build_roam_private_tools_localizations.py`, `build_merchant_store_parity_localizations.py`)
public enum XcodeGenAndProjectScaffoldIntegrityAudit {

    // MARK: - Canonical Targets & Tool Scripts

    public enum CanonicalTarget: String, CaseIterable, Equatable, Sendable {
        case questifyCore = "QuestifyCore"
        case questifyApp = "QuestifyApp"
        case questifyCoreTests = "QuestifyCoreTests"
        case questifyAppUnitTests = "QuestifyAppUnitTests"
        case questifyUITests = "QuestifyUITests"

        public var sourceRootDirectory: String {
            switch self {
            case .questifyCore: return "Core"
            case .questifyApp: return "App"
            case .questifyCoreTests: return "Tests/CoreTests"
            case .questifyAppUnitTests: return "Tests/AppUnitTests"
            case .questifyUITests: return "Tests/AppUITests"
            }
        }

        public var isTestTarget: Bool {
            switch self {
            case .questifyCore, .questifyApp:
                return false
            case .questifyCoreTests, .questifyAppUnitTests, .questifyUITests:
                return true
            }
        }
    }

    public static let canonicalTargetNames: [String] = CanonicalTarget.allCases.map(\.rawValue)

    public static let requiredScaffoldScripts: [String] = [
        "tools/generate_project.py",
        "tools/check_scaffold.py",
        "tools/check_roam_private_tools.py",
        "tools/build_roam_private_tools_localizations.py",
        "tools/build_merchant_store_parity_localizations.py"
    ]

    public enum ScaffoldViolation: Equatable, Sendable {
        case missingCanonicalTargets([String])
        case unexpectedTargetPresent(String)
        case duplicateSwiftBasenames(target: String, stems: [String])
        case pbxprojDriftDetected(committedDigest: String, generatedDigest: String)
        case unreferencedSwiftSources([String])
        case missingScaffoldScripts([String])
        case roamPrivateToolsCheckFailed
        case incompleteBilingualCatalog(tableName: String, missingLanguagesForKeys: [String])
    }

    // MARK: - Pillar 1: 5-Target Completeness & Basename Uniqueness

    public struct TargetTopologyEvaluation: Equatable, Sendable {
        public let presentTargets: [String]
        public let missingTargets: [String]
        public let duplicateStemsByTarget: [String: [String]]
        public let violations: [ScaffoldViolation]

        public var hasAllFiveCanonicalTargets: Bool {
            missingTargets.isEmpty && presentTargets.count == CanonicalTarget.allCases.count
        }

        public var isCompliant: Bool { violations.isEmpty }

        public init(
            presentTargets: [String] = XcodeGenAndProjectScaffoldIntegrityAudit.canonicalTargetNames,
            swiftFilesByTarget: [String: [String]] = [:]
        ) {
            self.presentTargets = presentTargets
            let presentSet = Set(presentTargets)
            let missing = XcodeGenAndProjectScaffoldIntegrityAudit.canonicalTargetNames.filter { !presentSet.contains($0) }
            self.missingTargets = missing

            var foundViolations: [ScaffoldViolation] = []
            if !missing.isEmpty {
                foundViolations.append(.missingCanonicalTargets(missing))
            }
            let canonicalSet = Set(XcodeGenAndProjectScaffoldIntegrityAudit.canonicalTargetNames)
            for target in presentTargets where !canonicalSet.contains(target) {
                foundViolations.append(.unexpectedTargetPresent(target))
            }

            var dupesByTarget: [String: [String]] = [:]
            for (target, paths) in swiftFilesByTarget {
                var countsByStem: [String: Int] = [:]
                for path in paths where path.lowercased().hasSuffix(".swift") {
                    let filename = (path as NSString).lastPathComponent
                    let stem = (filename as NSString).deletingPathExtension.lowercased()
                    countsByStem[stem, default: 0] += 1
                }
                let duplicateStems = countsByStem.filter { $0.value > 1 }.map(\.key).sorted()
                if !duplicateStems.isEmpty {
                    dupesByTarget[target] = duplicateStems
                    foundViolations.append(.duplicateSwiftBasenames(target: target, stems: duplicateStems))
                }
            }
            self.duplicateStemsByTarget = dupesByTarget
            self.violations = foundViolations.sorted { String(describing: $0) < String(describing: $1) }
        }
    }

    public static func auditTargetTopology(
        presentTargets: [String] = canonicalTargetNames,
        swiftFilesByTarget: [String: [String]] = [:]
    ) -> TargetTopologyEvaluation {
        TargetTopologyEvaluation(
            presentTargets: presentTargets,
            swiftFilesByTarget: swiftFilesByTarget
        )
    }

    // MARK: - Pillar 2: Deterministic generate_project.py & check_scaffold.py Zero-Drift Verification

    public struct ProjectZeroDriftEvaluation: Equatable, Sendable {
        public let committedPbxprojDigest: String
        public let generatedPbxprojDigest: String
        public let unreferencedSwiftFiles: [String]
        public let isZeroDrift: Bool
        public let violations: [ScaffoldViolation]

        public var isCompliant: Bool { isZeroDrift && unreferencedSwiftFiles.isEmpty && violations.isEmpty }

        public init(
            committedPbxprojDigest: String,
            generatedPbxprojDigest: String,
            diskSwiftFiles: Set<String> = [],
            pbxprojReferencedSwiftFiles: Set<String> = []
        ) {
            self.committedPbxprojDigest = committedPbxprojDigest
            self.generatedPbxprojDigest = generatedPbxprojDigest
            let zeroDrift = !committedPbxprojDigest.isEmpty && committedPbxprojDigest == generatedPbxprojDigest
            self.isZeroDrift = zeroDrift

            let unreferenced = diskSwiftFiles.subtracting(pbxprojReferencedSwiftFiles).sorted()
            self.unreferencedSwiftFiles = unreferenced

            var foundViolations: [ScaffoldViolation] = []
            if !zeroDrift {
                foundViolations.append(
                    .pbxprojDriftDetected(
                        committedDigest: committedPbxprojDigest,
                        generatedDigest: generatedPbxprojDigest
                    )
                )
            }
            if !unreferenced.isEmpty {
                foundViolations.append(.unreferencedSwiftSources(unreferenced))
            }
            self.violations = foundViolations
        }
    }

    public static func auditProjectZeroDrift(
        committedPbxprojDigest: String,
        generatedPbxprojDigest: String,
        diskSwiftFiles: Set<String> = [],
        pbxprojReferencedSwiftFiles: Set<String> = []
    ) -> ProjectZeroDriftEvaluation {
        ProjectZeroDriftEvaluation(
            committedPbxprojDigest: committedPbxprojDigest,
            generatedPbxprojDigest: generatedPbxprojDigest,
            diskSwiftFiles: diskSwiftFiles,
            pbxprojReferencedSwiftFiles: pbxprojReferencedSwiftFiles
        )
    }

    // MARK: - Pillar 3: Roam Private Tools & Bilingual .xcstrings Catalog Scripts

    public struct LocalizationCatalogEntry: Equatable, Sendable {
        public let key: String
        public let englishValue: String?
        public let simplifiedChineseValue: String?

        public init(key: String, englishValue: String?, simplifiedChineseValue: String?) {
            self.key = key
            self.englishValue = englishValue
            self.simplifiedChineseValue = simplifiedChineseValue
        }

        public var isBilingualComplete: Bool {
            guard let en = englishValue?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty,
                  let zh = simplifiedChineseValue?.trimmingCharacters(in: .whitespacesAndNewlines), !zh.isEmpty else {
                return false
            }
            return true
        }
    }

    public struct LocalizationAndToolingEvaluation: Equatable, Sendable {
        public let presentScripts: [String]
        public let missingScripts: [String]
        public let roamPrivateToolsCheckPassed: Bool
        public let incompleteKeysByTable: [String: [String]]
        public let violations: [ScaffoldViolation]

        public var isCompliant: Bool { violations.isEmpty }

        public init(
            presentScripts: [String] = XcodeGenAndProjectScaffoldIntegrityAudit.requiredScaffoldScripts,
            roamPrivateToolsCheckPassed: Bool = true,
            catalogsByTable: [String: [LocalizationCatalogEntry]] = [:]
        ) {
            self.presentScripts = presentScripts
            let presentSet = Set(presentScripts)
            let missing = XcodeGenAndProjectScaffoldIntegrityAudit.requiredScaffoldScripts.filter { !presentSet.contains($0) }
            self.missingScripts = missing
            self.roamPrivateToolsCheckPassed = roamPrivateToolsCheckPassed

            var foundViolations: [ScaffoldViolation] = []
            if !missing.isEmpty {
                foundViolations.append(.missingScaffoldScripts(missing))
            }
            if !roamPrivateToolsCheckPassed {
                foundViolations.append(.roamPrivateToolsCheckFailed)
            }

            var incompleteByTable: [String: [String]] = [:]
            for tableName in catalogsByTable.keys.sorted() {
                let entries = catalogsByTable[tableName] ?? []
                let badKeys = entries.filter { !$0.isBilingualComplete }.map(\.key).sorted()
                if !badKeys.isEmpty {
                    incompleteByTable[tableName] = badKeys
                    foundViolations.append(
                        .incompleteBilingualCatalog(tableName: tableName, missingLanguagesForKeys: badKeys)
                    )
                }
            }
            self.incompleteKeysByTable = incompleteByTable
            self.violations = foundViolations
        }
    }

    public static func auditLocalizationAndTooling(
        presentScripts: [String] = requiredScaffoldScripts,
        roamPrivateToolsCheckPassed: Bool = true,
        catalogsByTable: [String: [LocalizationCatalogEntry]] = [:]
    ) -> LocalizationAndToolingEvaluation {
        LocalizationAndToolingEvaluation(
            presentScripts: presentScripts,
            roamPrivateToolsCheckPassed: roamPrivateToolsCheckPassed,
            catalogsByTable: catalogsByTable
        )
    }
}
