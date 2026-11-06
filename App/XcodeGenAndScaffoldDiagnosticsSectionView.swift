import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row for each of the 5 Xcode & SwiftPM targets checked by scaffold diagnostics:
/// `QuestifyCore`, `QuestifyApp`, `QuestifyCoreTests`, `QuestifyAppUnitTests`, and `QuestifyUITests`.
public struct XcodeTargetScaffoldRow: Identifiable, Equatable, Sendable {
    public enum TargetKind: String, CaseIterable, Equatable, Sendable {
        case questifyCore = "QuestifyCore"
        case questifyApp = "QuestifyApp"
        case questifyCoreTests = "QuestifyCoreTests"
        case questifyAppUnitTests = "QuestifyAppUnitTests"
        case questifyUITests = "QuestifyUITests"
    }

    public let id: String
    public let target: TargetKind
    public let sourceFolder: String
    public let registeredFileCount: Int
    public let uniqueBasenamesVerified: Bool
    public let schemeBuildableReferenceValid: Bool

    public init(
        id: String? = nil,
        target: TargetKind,
        sourceFolder: String,
        registeredFileCount: Int,
        uniqueBasenamesVerified: Bool,
        schemeBuildableReferenceValid: Bool
    ) {
        self.id = id ?? target.rawValue
        self.target = target
        self.sourceFolder = sourceFolder
        self.registeredFileCount = registeredFileCount
        self.uniqueBasenamesVerified = uniqueBasenamesVerified
        self.schemeBuildableReferenceValid = schemeBuildableReferenceValid
    }

    public var isCompliant: Bool {
        registeredFileCount > 0 && uniqueBasenamesVerified && schemeBuildableReferenceValid
    }
}

/// Self-contained snapshot for `generate_project.py` & `check_scaffold.py` diagnostics across all 5 targets.
public struct XcodeGenScaffoldSnapshot: Equatable, Sendable {
    public let pbxprojSemanticEquivalenceVerified: Bool
    public let bilingualCatalogComplete: Bool
    public let noForbiddenSigningArtifacts: Bool
    public let atsStrictnessVerified: Bool
    public let rows: [XcodeTargetScaffoldRow]

    public init(
        pbxprojSemanticEquivalenceVerified: Bool,
        bilingualCatalogComplete: Bool,
        noForbiddenSigningArtifacts: Bool,
        atsStrictnessVerified: Bool,
        rows: [XcodeTargetScaffoldRow]
    ) {
        self.pbxprojSemanticEquivalenceVerified = pbxprojSemanticEquivalenceVerified
        self.bilingualCatalogComplete = bilingualCatalogComplete
        self.noForbiddenSigningArtifacts = noForbiddenSigningArtifacts
        self.atsStrictnessVerified = atsStrictnessVerified
        self.rows = rows
    }

    public var compliantTargetCount: Int {
        rows.filter(\.isCompliant).count
    }

    public var isAllCompliant: Bool {
        pbxprojSemanticEquivalenceVerified &&
            bilingualCatalogComplete &&
            noForbiddenSigningArtifacts &&
            atsStrictnessVerified &&
            Set(rows.map(\.target)) == Set(XcodeTargetScaffoldRow.TargetKind.allCases) &&
            rows.allSatisfy(\.isCompliant)
    }

    public static let compliantSample = XcodeGenScaffoldSnapshot(
        pbxprojSemanticEquivalenceVerified: true,
        bilingualCatalogComplete: true,
        noForbiddenSigningArtifacts: true,
        atsStrictnessVerified: true,
        rows: [
            XcodeTargetScaffoldRow(
                target: .questifyCore,
                sourceFolder: "Core",
                registeredFileCount: 280,
                uniqueBasenamesVerified: true,
                schemeBuildableReferenceValid: true
            ),
            XcodeTargetScaffoldRow(
                target: .questifyApp,
                sourceFolder: "App",
                registeredFileCount: 240,
                uniqueBasenamesVerified: true,
                schemeBuildableReferenceValid: true
            ),
            XcodeTargetScaffoldRow(
                target: .questifyCoreTests,
                sourceFolder: "Tests/CoreTests",
                registeredFileCount: 210,
                uniqueBasenamesVerified: true,
                schemeBuildableReferenceValid: true
            ),
            XcodeTargetScaffoldRow(
                target: .questifyAppUnitTests,
                sourceFolder: "Tests/AppUnitTests",
                registeredFileCount: 145,
                uniqueBasenamesVerified: true,
                schemeBuildableReferenceValid: true
            ),
            XcodeTargetScaffoldRow(
                target: .questifyUITests,
                sourceFolder: "Tests/AppUITests",
                registeredFileCount: 38,
                uniqueBasenamesVerified: true,
                schemeBuildableReferenceValid: true
            )
        ]
    )
}

@MainActor
public struct XcodeGenAndScaffoldDiagnosticsSectionView: View {
    public let snapshot: XcodeGenScaffoldSnapshot

    public init(snapshot: XcodeGenScaffoldSnapshot = .compliantSample) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Xcode 工程生成与脚手架一致性诊断")
                    .font(.headline)
                    .accessibilityIdentifier("xcodeScaffoldAudit.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllCompliant ? .green : .red)
                    .accessibilityIdentifier("xcodeScaffoldAudit.overallStatus")

                Text(verbatim: Self.pbxprojStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("xcodeScaffoldAudit.pbxprojStatus")

                Text(verbatim: Self.catalogStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("xcodeScaffoldAudit.catalogStatus")

                Text(verbatim: Self.signingAndAtsStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("xcodeScaffoldAudit.signingAndAtsStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无工程目标脚手架检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("xcodeScaffoldAudit.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    XcodeTargetScaffoldRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("xcodeScaffoldAudit.section")
    }

    public static func overallStatusText(for snapshot: XcodeGenScaffoldSnapshot) -> String {
        snapshot.isAllCompliant
            ? "整体状态：五大工程 Target 与脚手架校验全部通过（\(snapshot.compliantTargetCount)/\(snapshot.rows.count)）"
            : "整体状态：存在未通过的工程 Target 或脚手架检查项（\(snapshot.compliantTargetCount)/\(snapshot.rows.count)）"
    }

    public static func pbxprojStatusText(for snapshot: XcodeGenScaffoldSnapshot) -> String {
        snapshot.pbxprojSemanticEquivalenceVerified
            ? "工程等价性：project.pbxproj 与 generate_project.py 语义完全一致"
            : "工程等价性：project.pbxproj 与生成器输出存在偏差"
    }

    public static func catalogStatusText(for snapshot: XcodeGenScaffoldSnapshot) -> String {
        snapshot.bilingualCatalogComplete
            ? "双语词表：en / zh-Hans 词条完整且无未注册表引用"
            : "双语词表：存在缺失翻译或未注册的词表键"
    }

    public static func signingAndAtsStatusText(for snapshot: XcodeGenScaffoldSnapshot) -> String {
        let signing = snapshot.noForbiddenSigningArtifacts ? "无证书/私钥残留" : "检测到违规证书文件"
        let ats = snapshot.atsStrictnessVerified ? "ATS 严格启用" : "ATS 配置异常"
        return "安全基线：\(signing) · \(ats)"
    }
}

@MainActor
private struct XcodeTargetScaffoldRowView: View {
    let row: XcodeTargetScaffoldRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "\(row.target.rawValue) (\(row.sourceFolder))")
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: row.isCompliant ? "已对齐" : "异常")
                    .font(.caption)
                    .foregroundStyle(row.isCompliant ? .green : .red)
            }

            Text(verbatim: "注册源码数：\(row.registeredFileCount) · 文件名唯一：\(row.uniqueBasenamesVerified ? "通过" : "冲突") · Scheme 引用：\(row.schemeBuildableReferenceValid ? "有效" : "缺失")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("xcodeScaffoldAudit.row")
    }
}
