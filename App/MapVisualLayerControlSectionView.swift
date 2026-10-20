import SwiftUI

/// F-W13 / MV01–MV05 / MV12 / MV19 SwiftUI section view displaying resolved map visual tokens,
/// bottom-to-top layer order, projected annotation marker states, and coordinate datum badges.
@MainActor
public struct MapVisualLayerControlSectionView: View {
    public let theme: MapVisualHostThemeSnapshot
    public let orderedLayers: [MapLayerOrder]
    public let projections: [MapAnnotationVisualProjection]
    public let coordinateObservation: MapCoordinateObservation?
    public let onSelectAnnotation: ((MapSourceKey) -> Void)?

    public init(
        theme: MapVisualHostThemeSnapshot = MapVisualHostBridge.resolveTheme(systemIsDark: false),
        orderedLayers: [MapLayerOrder] = MapVisualHostBridge.orderedLayers(),
        projections: [MapAnnotationVisualProjection] = [],
        coordinateObservation: MapCoordinateObservation? = nil,
        onSelectAnnotation: ((MapSourceKey) -> Void)? = nil
    ) {
        self.theme = theme
        self.orderedLayers = orderedLayers
        self.projections = projections
        self.coordinateObservation = coordinateObservation
        self.onSelectAnnotation = onSelectAnnotation
    }

    public var body: some View {
        Group {
            Section {
                HStack {
                    Text(verbatim: "外观模式")
                    Spacer()
                    Text(verbatim: theme.appearance == .night ? "夜间 (Night)" : "日间 (Day)")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("mapVisual.theme.appearance")

                HStack {
                    Text(verbatim: "样式清单版本")
                    Spacer()
                    Text(verbatim: theme.manifestVersion)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(verbatim: theme.isCandidatePalette ? "候选色板" : "已审色板")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(theme.isCandidatePalette ? Color.orange.opacity(0.18) : Color.green.opacity(0.18))
                        )
                        .accessibilityIdentifier("mapVisual.theme.candidateBadge")
                }

                HStack {
                    Text(verbatim: "对比度校验")
                    Spacer()
                    Text(
                        verbatim: theme.contrastShortfalls.isEmpty
                            ? "WCAG 对比度达标"
                            : "存在不足: \(theme.contrastShortfalls.joined(separator: ", "))"
                    )
                    .font(.caption)
                    .foregroundStyle(theme.contrastShortfalls.isEmpty ? Color.secondary : Color.red)
                }
                .accessibilityIdentifier("mapVisual.theme.contrastStatus")

                if let observation = coordinateObservation {
                    HStack {
                        Text(verbatim: "坐标基准")
                        Spacer()
                        Text(verbatim: Self.datumBadgeText(for: observation.datum))
                            .font(.caption.monospaced().weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                            .accessibilityIdentifier("mapVisual.coordinate.datumBadge")
                    }
                }
            } header: {
                Text(verbatim: "地图视觉与坐标状态")
            }
            .accessibilityIdentifier("mapVisual.theme.section")

            Section {
                ForEach(orderedLayers, id: \.rawValue) { layer in
                    HStack {
                        Text(verbatim: "#\(layer.rawValue)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(verbatim: Self.layerDisplayName(layer))
                        Spacer()
                    }
                    .accessibilityIdentifier("mapVisual.layer.\(layer.rawValue)")
                }
            } header: {
                Text(verbatim: "图层渲染顺序 (底→顶)")
            }
            .accessibilityIdentifier("mapVisual.layers.section")

            if !projections.isEmpty {
                Section {
                    ForEach(projections, id: \.key) { projection in
                        Button {
                            onSelectAnnotation?(projection.key)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: projection.symbolName)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle().stroke(
                                            swatchColor(projection.tintColor),
                                            lineWidth: projection.strokeWidth
                                        )
                                    )
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: projection.title)
                                        .font(.subheadline.weight(.medium))
                                    Text(
                                        verbatim: "\(Self.stateDisplayName(projection.effectiveState)) · 线宽 \(String(format: "%.1f", projection.strokeWidth)) · \(projection.allowsPrimaryAction ? "可交互" : "不可执行主操作")"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(verbatim: Self.datumBadgeText(for: projection.coordinate.datum))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("mapVisual.annotation.\(projection.key.type.rawValue).\(projection.key.id)")
                    }
                } header: {
                    Text(verbatim: "标注视觉状态投影")
                }
                .accessibilityIdentifier("mapVisual.annotations.section")
            }
        }
    }

    public static func datumBadgeText(for datum: WalkingCoordinateDatum) -> String {
        switch datum {
        case .wgs84:
            return "WGS-84"
        case .gcj02:
            return "GCJ-02"
        }
    }

    public static func layerDisplayName(_ layer: MapLayerOrder) -> String {
        switch layer {
        case .basemap:
            return "基础底图 (Basemap)"
        case .operationZone:
            return "运营区域层 (Operation Zone)"
        case .fog:
            return "个人迷雾层 (Personal Fog)"
        case .routeAndTarget:
            return "路线与当前目标 (Route & Target)"
        case .gameMarkers:
            return "玩法与探索点位 (Game Markers)"
        case .consentedPeers:
            return "已授权同伴位置 (Consented Peers)"
        case .ownLocation:
            return "当前自身定位 (Own Location)"
        case .controls:
            return "地图交互控件 (Controls)"
        }
    }

    public static func stateDisplayName(_ state: MapMarkerVisualState) -> String {
        switch state {
        case .standard:
            return "常规"
        case .interactive:
            return "可交互"
        case .selected:
            return "已选中"
        case .active:
            return "当前进行中"
        case .completed:
            return "已完成"
        case .locked:
            return "未解锁"
        case .unavailable:
            return "不可用"
        case .inReview:
            return "审核中"
        }
    }

    private func swatchColor(_ styleColor: MapStyleColor) -> Color {
        Color(
            red: styleColor.red,
            green: styleColor.green,
            blue: styleColor.blue,
            opacity: styleColor.opacity
        )
    }
}
