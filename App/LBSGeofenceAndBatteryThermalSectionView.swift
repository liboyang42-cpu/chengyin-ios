import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Presentation row modeling an adaptive LBS / geofence power & thermal operating policy:
/// - Adaptive `CLLocationManager` horizontal accuracy & distance filter
/// - `ProcessInfo.ThermalState` (`serious` / `critical`) sampling throttle
/// - Background & stationary GPS idle cutoff
public struct LBSBatteryThermalModeRow: Sendable, Equatable, Identifiable {
    public enum PolicyID: String, CaseIterable, Sendable, Equatable {
        case adaptiveLocationAccuracy = "adaptive_location_accuracy"
        case thermalStateThrottling = "thermal_state_throttling"
        case backgroundGPSIdleCutoff = "background_gps_idle_cutoff"
    }

    public let id: String
    public let policy: PolicyID
    public let title: String
    public let detail: String
    public let targetMetricText: String
    public let isCompliant: Bool

    public init(
        policy: PolicyID,
        title: String,
        detail: String,
        targetMetricText: String,
        isCompliant: Bool = true
    ) {
        self.id = policy.rawValue
        self.policy = policy
        self.title = title
        self.detail = detail
        self.targetMetricText = targetMetricText
        self.isCompliant = isCompliant
    }
}

/// Self-contained snapshot for `LBSGeofenceAndBatteryThermalSectionView`.
public struct LBSBatteryThermalSnapshot: Sendable, Equatable {
    public let rows: [LBSBatteryThermalModeRow]
    public let idleCutoffSeconds: Int
    public let throttlesOnSeriousOrCriticalThermal: Bool
    public let disablesBackgroundContinuousGPSWhenNotInPlay: Bool

    public var isBatteryAndThermalSafe: Bool {
        rows.count == 3
            && rows.allSatisfy(\.isCompliant)
            && (15...300).contains(idleCutoffSeconds)
            && throttlesOnSeriousOrCriticalThermal
            && disablesBackgroundContinuousGPSWhenNotInPlay
    }

    public init(
        rows: [LBSBatteryThermalModeRow],
        idleCutoffSeconds: Int = 60,
        throttlesOnSeriousOrCriticalThermal: Bool = true,
        disablesBackgroundContinuousGPSWhenNotInPlay: Bool = true
    ) {
        self.rows = rows
        self.idleCutoffSeconds = idleCutoffSeconds
        self.throttlesOnSeriousOrCriticalThermal = throttlesOnSeriousOrCriticalThermal
        self.disablesBackgroundContinuousGPSWhenNotInPlay = disablesBackgroundContinuousGPSWhenNotInPlay
    }

    public static let defaultReady = LBSBatteryThermalSnapshot(
        rows: [
            LBSBatteryThermalModeRow(
                policy: .adaptiveLocationAccuracy,
                title: "CLLocationManager 自适应精度分级",
                detail: "仅在主动步行打卡窗口使用十米级定位；普通漫游浏览降级为百米级显著位置变化。",
                targetMetricText: "10m (打卡) / 100m (漫游)",
                isCompliant: true
            ),
            LBSBatteryThermalModeRow(
                policy: .thermalStateThrottling,
                title: "设备温控降频保护 (Thermal Throttling)",
                detail: "当 ThermalState 进入 serious 或 critical 时自动延长采样间隔并暂停高耗能地图特效。",
                targetMetricText: "Serious/Critical 自动降频",
                isCompliant: true
            ),
            LBSBatteryThermalModeRow(
                policy: .backgroundGPSIdleCutoff,
                title: "后台与静止 GPS 空闲切断",
                detail: "退出进行中剧本或退入后台满空闲阈值后立即停止连续定位采样，防止后台耗电发热。",
                targetMetricText: "60s 空闲自动切断",
                isCompliant: true
            )
        ],
        idleCutoffSeconds: 60,
        throttlesOnSeriousOrCriticalThermal: true,
        disablesBackgroundContinuousGPSWhenNotInPlay: true
    )
}

/// SwiftUI section view displaying adaptive `CLLocationManager` accuracy, thermal state throttling,
/// and background GPS idle cutoff using `Text(verbatim:)` exclusively (`0` new `.xcstrings` keys).
@MainActor
public struct LBSGeofenceAndBatteryThermalSectionView: View {
    public let snapshot: LBSBatteryThermalSnapshot

    public init(snapshot: LBSBatteryThermalSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            HStack {
                Text(
                    verbatim: snapshot.isBatteryAndThermalSafe
                        ? "LBS 围栏与温控功耗策略：3/3 项符合低功耗防发热基线"
                        : "LBS 围栏与温控功耗策略：检测到后台持续采样或温控未降频风险"
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: snapshot.isBatteryAndThermalSafe ? "OPTIMAL" : "DRAIN_RISK")
                    .font(.caption.monospaced())
                    .foregroundStyle(snapshot.isBatteryAndThermalSafe ? .green : .red)
            }
            .accessibilityIdentifier("lbsBatteryThermal.summary")

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(verbatim: row.targetMetricText)
                            .font(.caption.monospaced())
                            .foregroundStyle(row.isCompliant ? .secondary : .red)
                            .accessibilityIdentifier("lbsBatteryThermal.row.\(row.id).metric")
                    }
                    Text(verbatim: row.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("lbsBatteryThermal.row.\(row.id)")
            }

            HStack {
                Text(verbatim: "后台空闲 GPS 切断阈值")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "\(snapshot.idleCutoffSeconds)s")
                    .font(.caption.monospaced())
            }
            .accessibilityIdentifier("lbsBatteryThermal.idleCutoff")

            if !snapshot.isBatteryAndThermalSafe {
                Text(verbatim: "告警：当前定位或温控策略未满足低功耗门禁，可能导致后台电量异常消耗或机身过热。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("lbsBatteryThermal.warningBanner")
            }
        } header: {
            Text(verbatim: "LBS 地理围栏与温控低功耗守护")
        }
        .accessibilityIdentifier("lbsBatteryThermal.section")
    }
}
