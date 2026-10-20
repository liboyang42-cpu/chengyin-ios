import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained row modeling photo library (`PHPickerViewController`) and camera (`AVCaptureDevice`)
/// permission posture, `.limited` / `.denied` graceful degradation, and manual/Settings fallback.
public struct MediaPermissionFlowRow: Sendable, Equatable, Identifiable {
    public enum FlowKind: String, Sendable, Equatable {
        case phpickerZeroPermission = "phpickerZeroPermission"
        case limitedOrDeniedDegradation = "limitedOrDeniedDegradation"
        case cameraManualAndSettingsFallback = "cameraManualAndSettingsFallback"
    }

    public enum Status: String, Sendable, Equatable {
        case ready
        case degradedWarning
        case blocked
    }

    public let id: String
    public let kind: FlowKind
    public let title: String
    public let permissionPolicy: String
    public let fallbackMechanism: String
    public let status: Status

    public init(
        id: String,
        kind: FlowKind,
        title: String,
        permissionPolicy: String,
        fallbackMechanism: String,
        status: Status
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.permissionPolicy = permissionPolicy
        self.fallbackMechanism = fallbackMechanism
        self.status = status
    }

    public var badgeText: String {
        switch status {
        case .ready:
            return "READY"
        case .degradedWarning:
            return "DEGRADED"
        case .blocked:
            return "BLOCKED"
        }
    }
}

/// Self-contained snapshot for `PHPickerViewController` zero-permission selection, `.limited` / `.denied`
/// graceful degradation, and manual/Settings fallback readiness.
public struct PhotoCameraPermissionSnapshot: Sendable, Equatable {
    public let usesOutOfProcessPHPicker: Bool
    public let supportsManualCodeAndAlbumFallbackOnCameraDenied: Bool
    public let rows: [MediaPermissionFlowRow]

    public init(
        usesOutOfProcessPHPicker: Bool,
        supportsManualCodeAndAlbumFallbackOnCameraDenied: Bool,
        rows: [MediaPermissionFlowRow]
    ) {
        self.usesOutOfProcessPHPicker = usesOutOfProcessPHPicker
        self.supportsManualCodeAndAlbumFallbackOnCameraDenied = supportsManualCodeAndAlbumFallbackOnCameraDenied
        self.rows = rows
    }

    public static let defaultReady = PhotoCameraPermissionSnapshot(
        usesOutOfProcessPHPicker: true,
        supportsManualCodeAndAlbumFallbackOnCameraDenied: true,
        rows: [
            MediaPermissionFlowRow(
                id: "phpicker-zero-permission",
                kind: .phpickerZeroPermission,
                title: "系统相册选择 (PHPickerViewController)",
                permissionPolicy: "进程外系统选择器，默认无需申请全量 PHPhotoLibrary 读权限",
                fallbackMechanism: "用户直接选取单张或多张图片，取消选择时保持原表单草稿不丢失",
                status: .ready
            ),
            MediaPermissionFlowRow(
                id: "limited-denied-degradation",
                kind: .limitedOrDeniedDegradation,
                title: "受限/拒绝状态优雅降级 (.limited / .denied)",
                permissionPolicy: "当保存海报或印章卡片遇到 .limited / .denied 时不崩溃、不死循环弹窗",
                fallbackMechanism: "提供系统分享面板 (ShareLink / UIActivityViewController) 与设置页引导",
                status: .ready
            ),
            MediaPermissionFlowRow(
                id: "camera-manual-settings-fallback",
                kind: .cameraManualAndSettingsFallback,
                title: "相机扫码与拍照降级兜底 (AVCaptureDevice)",
                permissionPolicy: "仅在用户点击扫码或拍照核验时按需检查相机权限",
                fallbackMechanism: "相机受拒或不可用时开放相册选图、手动输入口令及跳转系统设置入口",
                status: .ready
            )
        ]
    )

    public var readyCount: Int {
        rows.filter { $0.status == .ready }.count
    }

    public var degradedCount: Int {
        rows.filter { $0.status == .degradedWarning }.count
    }

    public var isFullyReady: Bool {
        usesOutOfProcessPHPicker
            && supportsManualCodeAndAlbumFallbackOnCameraDenied
            && rows.allSatisfy { $0.status == .ready }
    }

    public var summaryText: String {
        "就绪 \(readyCount)/\(rows.count) · 降级告警 \(degradedCount) · PHPicker 免权限 \(usesOutOfProcessPHPicker ? "已启用" : "未启用")"
    }
}

/// Renders `PHPickerViewController` zero-permission selection, `.limited`/`.denied` graceful degradation,
/// and manual/Settings fallback readiness using `Text(verbatim:)` throughout.
@MainActor
public struct PhotoLibraryAndCameraPermissionSectionView: View {
    public let snapshot: PhotoCameraPermissionSnapshot

    public init(snapshot: PhotoCameraPermissionSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            HStack {
                Text(verbatim: "相册与相机权限合规状态")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: snapshot.isFullyReady ? "最小权限合规 (READY)" : "存在降级告警")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((snapshot.isFullyReady ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    .foregroundStyle(snapshot.isFullyReady ? Color.green : Color.orange)
                    .accessibilityIdentifier("photoCameraPermission.overallBadge")
            }

            LabeledContent {
                Text(verbatim: snapshot.summaryText)
                    .font(.footnote.monospacedDigit())
            } label: {
                Text(verbatim: "权限链路汇总")
            }
            .accessibilityIdentifier("photoCameraPermission.summary")

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: row.badgeText)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor(for: row.status).opacity(0.15), in: Capsule())
                            .foregroundStyle(badgeColor(for: row.status))
                    }
                    Text(verbatim: "策略：\(row.permissionPolicy)")
                        .font(.caption)
                    Text(verbatim: "兜底：\(row.fallbackMechanism)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("photoCameraPermission.row.\(row.id)")
            }
        } header: {
            Text(verbatim: "相册与相机权限及降级兜底核查")
        }
        .accessibilityIdentifier("photoCameraPermission.section")
    }

    private func badgeColor(for status: MediaPermissionFlowRow.Status) -> Color {
        switch status {
        case .ready:
            return .green
        case .degradedWarning:
            return .orange
        case .blocked:
            return .red
        }
    }
}
