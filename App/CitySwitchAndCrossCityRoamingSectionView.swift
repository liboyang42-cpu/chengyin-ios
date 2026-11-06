import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Presentation row modeling a cross-city roaming & city-switch isolation invariant:
/// - `cityCode` + account cache partitioning
/// - In-flight request generation fencing & cancellation on city switch
/// - Map viewport & `CityDeltaStream` sequence reset on city transition
public struct CityIsolationSurfaceRow: Sendable, Equatable, Identifiable {
    public enum SurfaceID: String, CaseIterable, Sendable, Equatable {
        case cityAndAccountCachePartition = "city_account_cache_partition"
        case inFlightRequestCancellation = "inflight_request_cancellation"
        case mapViewportAndDeltaReset = "map_viewport_delta_reset"
    }

    public let id: String
    public let surface: SurfaceID
    public let title: String
    public let detail: String
    public let statusBadgeText: String
    public let isIsolated: Bool

    public init(
        surface: SurfaceID,
        title: String,
        detail: String,
        statusBadgeText: String,
        isIsolated: Bool = true
    ) {
        self.id = surface.rawValue
        self.surface = surface
        self.title = title
        self.detail = detail
        self.statusBadgeText = statusBadgeText
        self.isIsolated = isIsolated
    }
}

/// Self-contained snapshot for `CitySwitchAndCrossCityRoamingSectionView`.
public struct CitySwitchIsolationSnapshot: Sendable, Equatable {
    public let activeCityCode: String
    public let previousCityCode: String?
    public let rows: [CityIsolationSurfaceRow]
    public let cancelsInFlightReadsOnCityChange: Bool
    public let resetsViewportAndDeltaCursorOnSwitch: Bool

    public var isCrossCityIsolationSafe: Bool {
        !activeCityCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && rows.count == 3
            && rows.allSatisfy(\.isIsolated)
            && cancelsInFlightReadsOnCityChange
            && resetsViewportAndDeltaCursorOnSwitch
    }

    public init(
        activeCityCode: String = "310100",
        previousCityCode: String? = "110100",
        rows: [CityIsolationSurfaceRow],
        cancelsInFlightReadsOnCityChange: Bool = true,
        resetsViewportAndDeltaCursorOnSwitch: Bool = true
    ) {
        self.activeCityCode = activeCityCode
        self.previousCityCode = previousCityCode
        self.rows = rows
        self.cancelsInFlightReadsOnCityChange = cancelsInFlightReadsOnCityChange
        self.resetsViewportAndDeltaCursorOnSwitch = resetsViewportAndDeltaCursorOnSwitch
    }

    public static let defaultReady = CitySwitchIsolationSnapshot(
        activeCityCode: "310100",
        previousCityCode: "110100",
        rows: [
            CityIsolationSurfaceRow(
                surface: .cityAndAccountCachePartition,
                title: "cityCode + 账户双维缓存分区",
                detail: "漫游瓦片、同城俱乐部与城市节点缓存均绑定 (accountID, epoch, cityCode)，严禁跨城串读。",
                statusBadgeText: "PARTITIONED",
                isIsolated: true
            ),
            CityIsolationSurfaceRow(
                surface: .inFlightRequestCancellation,
                title: "切城在途请求代际取消 (Generation Fence)",
                detail: "切换城市时递增查询代际并取消旧城市在途请求，迟到的上一城响应一律丢弃。",
                statusBadgeText: "FENCED",
                isIsolated: true
            ),
            CityIsolationSurfaceRow(
                surface: .mapViewportAndDeltaReset,
                title: "地图视口与增量流游标重置",
                detail: "跨城切换后重置地图 bbox 游标与 CityDeltaStream 序列号，从新城市快照重新同步。",
                statusBadgeText: "CURSOR_RESET",
                isIsolated: true
            )
        ],
        cancelsInFlightReadsOnCityChange: true,
        resetsViewportAndDeltaCursorOnSwitch: true
    )
}

/// SwiftUI section view displaying `cityCode` + account cache partitioning, in-flight request cancellation
/// on city switch, and map viewport delta reset using `Text(verbatim:)` exclusively (`0` new `.xcstrings` keys).
@MainActor
public struct CitySwitchAndCrossCityRoamingSectionView: View {
    public let snapshot: CitySwitchIsolationSnapshot

    public init(snapshot: CitySwitchIsolationSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            HStack {
                Text(
                    verbatim: snapshot.isCrossCityIsolationSafe
                        ? "跨城漫游与切城隔离：3/3 项已启用代际围栏与缓存分区"
                        : "跨城漫游与切城隔离：检测到跨城缓存污染或在途请求串读风险"
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: snapshot.isCrossCityIsolationSafe ? "ISOLATED" : "BLEED_RISK")
                    .font(.caption.monospaced())
                    .foregroundStyle(snapshot.isCrossCityIsolationSafe ? .green : .red)
            }
            .accessibilityIdentifier("citySwitchIsolation.summary")

            HStack {
                Text(verbatim: "当前生效城市代码 (cityCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    verbatim: snapshot.previousCityCode != nil
                        ? "\(snapshot.previousCityCode ?? "") → \(snapshot.activeCityCode)"
                        : snapshot.activeCityCode
                )
                .font(.caption.monospaced())
            }
            .accessibilityIdentifier("citySwitchIsolation.cityCode")

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(verbatim: row.statusBadgeText)
                            .font(.caption.monospaced())
                            .foregroundStyle(row.isIsolated ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                            .accessibilityIdentifier("citySwitchIsolation.row.\(row.id).status")
                    }
                    Text(verbatim: row.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("citySwitchIsolation.row.\(row.id)")
            }

            if !snapshot.isCrossCityIsolationSafe {
                Text(verbatim: "告警：检测到切换城市后未取消旧城市在途请求或未重置地图增量流游标，存在跨城数据串读风险。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("citySwitchIsolation.warningBanner")
            }
        } header: {
            Text(verbatim: "城市切换与跨城漫游状态隔离")
        }
        .accessibilityIdentifier("citySwitchIsolation.section")
    }
}
