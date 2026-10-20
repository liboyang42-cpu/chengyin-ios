import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained row describing a share card / poster export surface's HTTP status separation,
/// `@3x` render scale, and QR deep-link embedding policy.
public struct SharePosterSurfaceRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let surfaceTitle: String
    public let separates404Or410GoneFrom503Error: Bool
    public let rendersAt3xScale: Bool
    public let embedsSanitizedQRDeepLink: Bool
    public let summary: String

    public init(
        id: String,
        surfaceTitle: String,
        separates404Or410GoneFrom503Error: Bool,
        rendersAt3xScale: Bool,
        embedsSanitizedQRDeepLink: Bool,
        summary: String
    ) {
        self.id = id
        self.surfaceTitle = surfaceTitle
        self.separates404Or410GoneFrom503Error = separates404Or410GoneFrom503Error
        self.rendersAt3xScale = rendersAt3xScale
        self.embedsSanitizedQRDeepLink = embedsSanitizedQRDeepLink
        self.summary = summary
    }

    public var isSurfaceCompliant: Bool {
        separates404Or410GoneFrom503Error &&
            rendersAt3xScale &&
            embedsSanitizedQRDeepLink
    }
}

/// Self-contained snapshot for `roam-share-snapshot` `404/410` `.gone` vs `503` `.error`
/// separation, `@3x` poster export, and QR deep-link embedding.
public struct ShareCardPosterExportSnapshot: Sendable, Equatable {
    public let separatesGone404Or410From503Error: Bool
    public let exportsPosterAt3xScale: Bool
    public let embedsSanitizedQRDeepLink: Bool
    public let stripsPrivateCoordinatesAndTokensFromPoster: Bool
    public let rows: [SharePosterSurfaceRow]

    public init(
        separatesGone404Or410From503Error: Bool,
        exportsPosterAt3xScale: Bool,
        embedsSanitizedQRDeepLink: Bool,
        stripsPrivateCoordinatesAndTokensFromPoster: Bool = true,
        rows: [SharePosterSurfaceRow]
    ) {
        self.separatesGone404Or410From503Error = separatesGone404Or410From503Error
        self.exportsPosterAt3xScale = exportsPosterAt3xScale
        self.embedsSanitizedQRDeepLink = embedsSanitizedQRDeepLink
        self.stripsPrivateCoordinatesAndTokensFromPoster = stripsPrivateCoordinatesAndTokensFromPoster
        self.rows = rows
    }

    public var compliantRowCount: Int {
        rows.filter(\.isSurfaceCompliant).count
    }

    public var isAllCompliant: Bool {
        separatesGone404Or410From503Error &&
            exportsPosterAt3xScale &&
            embedsSanitizedQRDeepLink &&
            stripsPrivateCoordinatesAndTokensFromPoster &&
            !rows.isEmpty &&
            rows.allSatisfy(\.isSurfaceCompliant)
    }

    public static let defaultReady = ShareCardPosterExportSnapshot(
        separatesGone404Or410From503Error: true,
        exportsPosterAt3xScale: true,
        embedsSanitizedQRDeepLink: true,
        stripsPrivateCoordinatesAndTokensFromPoster: true,
        rows: [
            SharePosterSurfaceRow(
                id: "roam-share-snapshot-card",
                surfaceTitle: "漫游战报分享卡 (roam-share-snapshot)",
                separates404Or410GoneFrom503Error: true,
                rendersAt3xScale: true,
                embedsSanitizedQRDeepLink: true,
                summary: "404/410 映射为终态 .gone（分享已失效），503/网络故障映射为可重试 .error"
            ),
            SharePosterSurfaceRow(
                id: "activity-and-topic-poster-export",
                surfaceTitle: "活动与主题高清海报导出 (@3x ImageRenderer)",
                separates404Or410GoneFrom503Error: true,
                rendersAt3xScale: true,
                embedsSanitizedQRDeepLink: true,
                summary: "固定 @3x 像素密度渲染高清分享海报，保存相册仅在用户显式点击时触发"
            ),
            SharePosterSurfaceRow(
                id: "club-and-team-invite-qr-card",
                surfaceTitle: "俱乐部与小队二维码分享卡",
                separates404Or410GoneFrom503Error: true,
                rendersAt3xScale: true,
                embedsSanitizedQRDeepLink: true,
                summary: "内嵌经脱敏校验的公开二维码深链，绝不包含会话 Token 或私人据点坐标"
            )
        ]
    )
}

@MainActor
public struct WeChatShareCardAndPosterExportSectionView: View {
    public let snapshot: ShareCardPosterExportSnapshot

    public init(snapshot: ShareCardPosterExportSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "微信分享卡片与高清海报导出审计")
                    .font(.headline)
                    .accessibilityIdentifier("shareCardPosterExport.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllCompliant ? .green : .red)
                    .accessibilityIdentifier("shareCardPosterExport.overallStatus")

                Text(verbatim: Self.statusSeparationText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("shareCardPosterExport.statusSeparation")

                Text(verbatim: Self.posterScaleStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("shareCardPosterExport.posterScaleStatus")

                Text(verbatim: Self.qrDeepLinkStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("shareCardPosterExport.qrDeepLinkStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无分享卡片与海报导出检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("shareCardPosterExport.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    SharePosterSurfaceRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("shareCardPosterExport.section")
    }

    public static func overallStatusText(for snapshot: ShareCardPosterExportSnapshot) -> String {
        snapshot.isAllCompliant
            ? "整体状态：分享卡片与 @3x 海报导出链路全部就绪（\(snapshot.compliantRowCount)/\(snapshot.rows.count)）"
            : "整体状态：存在 404/503 状态混淆或海报导出配置缺失（\(snapshot.compliantRowCount)/\(snapshot.rows.count)）"
    }

    public static func statusSeparationText(for snapshot: ShareCardPosterExportSnapshot) -> String {
        snapshot.separatesGone404Or410From503Error
            ? "状态码严格区分：404/410 映射 .gone（终态无重试） · 503 映射 .error（可重试）"
            : "状态码混淆告警：404/410 .gone 与 503 .error 未严格区分"
    }

    public static func posterScaleStatusText(for snapshot: ShareCardPosterExportSnapshot) -> String {
        snapshot.exportsPosterAt3xScale
            ? "海报导出规格：固定 @3x 渲染精度且仅按用户手势写入相册"
            : "海报导出规格：未固定 @3x 渲染精度"
    }

    public static func qrDeepLinkStatusText(for snapshot: ShareCardPosterExportSnapshot) -> String {
        snapshot.embedsSanitizedQRDeepLink && snapshot.stripsPrivateCoordinatesAndTokensFromPoster
            ? "二维码深链安全：内嵌公开深链且剥离会话凭证与私人坐标"
            : "二维码深链告警：二维码深链缺失或未完成敏感参数剥离"
    }
}

@MainActor
private struct SharePosterSurfaceRowView: View {
    let row: SharePosterSurfaceRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.surfaceTitle)
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: row.isSurfaceCompliant ? "已对齐" : "告警")
                    .font(.caption)
                    .foregroundStyle(row.isSurfaceCompliant ? .green : .red)
            }

            Text(verbatim: row.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: "404/503 分离：\(row.separates404Or410GoneFrom503Error ? "通过" : "混淆") · 渲染倍率：\(row.rendersAt3xScale ? "@3x" : "非@3x") · QR 深链：\(row.embedsSanitizedQRDeepLink ? "已脱敏内嵌" : "缺失")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("shareCardPosterExport.row")
    }
}
