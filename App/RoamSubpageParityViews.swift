import SwiftUI

// Mini-program subpackageRoam parity pieces (history RunCard, session footprint card, shared
// footprint receiver, POI node card, city voucher, city stamp). Read-only: every write stays
// with its existing dormant coordinator, and no view here samples location or opens a camera.

/// `scene-roam-history` summary strip: `{n}次漫游 · {km}公里 · 探{n}家`.
struct RoamHistoryParityStrip: View {
    let records: [RoamHistoryRecord]
    var body: some View {
        let summary = RoamHistoryStripSummary(records)
        Text("roamSub.w208.history.strip \(summary.trips) \(summary.kilometersText) \(summary.shopsText)")
            .font(.subheadline.weight(.semibold)).monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("roamSub.w208.history.strip")
    }
}

/// RunCard title: `{zone}漫游`, or 城市漫游 for the placeholder zone.
struct RoamRunCardTitle: View {
    let record: RoamHistoryRecord
    var font: Font = .title3
    var body: some View {
        switch RoamRunCardPresentation(record).title {
        case .zone(let zone): Text("roamSub.w208.history.zoneTitle \(zone)").font(font).bold()
        case .city: Text("roam.experience.cityWalk").font(font).bold()
        }
    }
}

/// RunCard date (M/D/YY), 公里 / 探店 / 用时, medal marks and `{n} 枚邮票`.
struct RoamRunCardParityMeta: View {
    let record: RoamHistoryRecord
    var body: some View {
        let card = RoamRunCardPresentation(record)
        VStack(alignment: .leading, spacing: 8) {
            if let date = card.dateShort { Text(verbatim: date).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            else { Text("roamSub.w208.history.dateUnavailable").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 20) {
                stat(card.distanceText, "roamSub.w208.history.km")
                stat(card.shopsText, "roamSub.w208.history.shops")
                stat(card.timeText, "roamSub.w208.history.duration")
            }
            if !card.medals.isEmpty || card.stamps > 0 {
                HStack(spacing: 8) {
                    ForEach(Array(card.medals.enumerated()), id: \.offset) { _, medal in
                        Image(systemName: "hexagon.fill").foregroundStyle(.tint).accessibilityLabel(Text(verbatim: medal))
                    }
                    if card.stamps > 0 {
                        Label { Text("roamSub.w208.history.stamps \(card.stamps)") } icon: { Image(systemName: "star") }
                            .font(.caption)
                    }
                }
            }
        }.accessibilityElement(children: .combine)
            .accessibilityIdentifier("roamSub.w208.history.runCard")
    }
    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// 那年今日 / 月度回顾 / 导出 row inside the history page. Export has no native screen yet.
@MainActor struct RoamHistoryToolsRow: View {
    let reader: (any RoamPassportToolsReading)?
    var body: some View {
        HStack(spacing: 12) {
            NavigationLink { RoamAnniversaryView(reader: reader) } label: { tool("roamSub.w208.history.tool.anniversary", "calendar") }
                .accessibilityIdentifier("roamSub.w208.history.tool.anniversary")
            NavigationLink { RoamMonthlyRecapView(reader: reader) } label: { tool("roamSub.w208.history.tool.recap", "list.bullet") }
                .accessibilityIdentifier("roamSub.w208.history.tool.recap")
            NavigationLink { RoamExportUnavailableView() } label: { tool("roamSub.w208.history.tool.export", "arrow.down.doc") }
                .accessibilityLabel(Text("roamSub.w208.history.tool.exportLabel"))
                .accessibilityIdentifier("roamSub.w208.history.tool.export")
        }.buttonStyle(.bordered)
    }
    private func tool(_ key: LocalizedStringKey, _ symbol: String) -> some View {
        VStack(spacing: 4) { Image(systemName: symbol); Text(key).font(.caption) }
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

struct RoamExportUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("roamSub.w208.history.tool.exportLabel", systemImage: "arrow.down.doc")
        } description: { Text("roamSub.w208.history.exportUnavailable") }
            .accessibilityIdentifier("roamSub.w208.history.exportUnavailable")
    }
}

/// `subpackageRoam/session` header: 本次漫游 + `dateFull · time`.
struct RoamSessionParityHeader: View {
    let record: RoamHistoryRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("roamSub.w208.session.title").font(.title2.bold())
            if let date = record.recordedAt {
                HStack(spacing: 4) {
                    Text(date, format: .dateTime.month().day().weekday(.abbreviated))
                    Text(verbatim: "· " + (record.durationText ?? "—"))
                }.font(.subheadline).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("roamSub.w208.session.header")
    }
}

/// `routeName` (session index.js) without inventing a place name.
struct RoamSessionRouteNameText: View {
    let name: RoamSessionRouteName
    var body: some View {
        switch name {
        case .zone(let zone): Text(verbatim: zone)
        case .places(let first, let count): Text("roamSub.w208.session.route.places \(first) \(count)")
        case .place(let place): Text("roamSub.w208.session.route.place \(place)")
        case .date(let month, let day): Text("roamSub.w208.session.route.date \(month) \(day)")
        case .generic: Text("roamSub.w208.session.route.generic")
        }
    }
}

/// Footprint card additions: route name, 已完成本次漫游, 探索度, 点亮 and the brand line.
/// No share link is published from iOS; the card says so with the source's own wording.
struct RoamShareCardParityFooter: View {
    let record: RoamHistoryRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoamSessionRouteNameText(name: RoamSessionRouteName(record)).font(.headline)
                .accessibilityIdentifier("roamSub.w208.share.routeName")
            Text("roamSub.w208.session.completeFact").font(.subheadline)
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    if let percent = record.explorePct { Text(verbatim: "\(percent)%").font(.headline.monospacedDigit()) }
                    else { Text(verbatim: "--%").font(.headline.monospacedDigit()) }
                    Text("roamSub.w208.share.explore").font(.caption2).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("roamSub.w208.share.explore")
                VStack(alignment: .leading) {
                    Text(verbatim: record.shops.map(String.init) ?? "—").font(.headline.monospacedDigit())
                    Text("roamSub.w208.share.lit").font(.caption2).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("roamSub.w208.share.lit")
            }
            Text("roamSub.w208.share.brand").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

struct RoamShareLinkDormantNotice: View {
    var body: some View {
        Label("roamSub.w208.share.linkNotGenerated", systemImage: "link.badge.plus")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("roamSub.w208.share.linkNotGenerated")
    }
}

/// Receiver mode of `subpackageRoam/session?shareToken=`: anonymous read of the coarse snapshot.
/// Without a reviewed reader the page states that it cannot open shared footprints.
@MainActor struct RoamSharedFootprintView: View {
    let token: String
    let reader: (any RoamShareSnapshotReading)?
    var onOpenRoam: (() -> Void)? = nil
    @State private var outcome: RoamShareSnapshotOutcome?
    @State private var generation = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch outcome {
                case nil:
                    ProgressView("roamSub.w208.shared.loading").frame(maxWidth: .infinity)
                        .accessibilityIdentifier("roamSub.w208.shared.loading")
                case .error?:
                    ContentUnavailableView {
                        Label("roamSub.w208.shared.errorTitle", systemImage: "wifi.exclamationmark")
                    } description: { Text("roamSub.w208.shared.errorHint") } actions: {
                        Button("roamSub.w208.shared.retry") { Task { await load() } }
                            .accessibilityIdentifier("roamSub.w208.shared.retry")
                    }.accessibilityIdentifier("roamSub.w208.shared.error")
                case .gone?:
                    ContentUnavailableView {
                        Label("roamSub.w208.shared.goneTitle", systemImage: "eye.slash")
                    } description: { Text("roamSub.w208.shared.goneHint") } actions: {
                        if let onOpenRoam { Button("roamSub.w208.shared.goRoam", action: onOpenRoam) }
                    }.accessibilityIdentifier("roamSub.w208.shared.gone")
                case .unavailable?:
                    ContentUnavailableView("roamSub.w208.shared.unavailable", systemImage: "lock",
                                           description: Text("roamSub.w208.shared.unavailableHint"))
                        .accessibilityIdentifier("roamSub.w208.shared.unavailable")
                case .ready(let snapshot)?:
                    snapshotCard(snapshot)
                }
            }.padding()
        }.navigationTitle(Text("roamSub.w208.session.title"))
            .task(id: token) { await load() }
    }
    private func snapshotCard(_ snapshot: RoamShareSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: snapshot.routeName).font(.title2.bold()).accessibilityIdentifier("roamSub.w208.shared.routeName")
            Text("roamSub.w208.session.completeFact")
            HStack(spacing: 4) {
                Text(Date(timeIntervalSince1970: Double(snapshot.ts) / 1000), format: .dateTime.month().day().weekday(.abbreviated))
                Text(verbatim: "· " + snapshot.time)
            }.foregroundStyle(.secondary)
            HStack(spacing: 20) {
                metric(snapshot.distance.map { String(format: "%.1f", $0) } ?? "—", Text(verbatim: "km"))
                metric(snapshot.explorePct.map { "\(Int($0))%" } ?? "--%", Text("roamSub.w208.share.explore"))
                metric(snapshot.shops.map(String.init) ?? "—", Text("roamSub.w208.share.lit"))
            }
            if snapshot.track.count < 2 { Text("roamSub.w208.shared.noTrack").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(snapshot.pois.enumerated()), id: \.offset) { _, place in
                Label { Text(verbatim: place.name) } icon: { Image(systemName: place.cat == "merchant" ? "storefront" : "mappin") }
            }
            Text("roamSub.w208.share.brand").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("roamSub.w208.shared.card")
    }
    private func metric(_ value: String, _ label: Text) -> some View {
        VStack(alignment: .leading) { Text(verbatim: value).font(.headline.monospacedDigit()); label.font(.caption2).foregroundStyle(.secondary) }
            .accessibilityElement(children: .combine)
    }
    private func load() async {
        generation += 1; let ticket = generation
        guard let parsed = RoamShareToken(token) else { outcome = .gone; return }
        guard let reader else { outcome = .unavailable; return }
        outcome = nil
        let result = await reader.snapshot(parsed)
        guard ticket == generation, !Task.isCancelled else { return }
        outcome = result
    }
}

/// `scene-roam-poi-detail` node card. Favorite, interaction and completion are writes and stay
/// read-only labels here; 出示核销码 only opens the existing approval-gated voucher view.
@MainActor struct RoamPOINodeParityCard: View {
    let node: RoamNodeDetail
    var stampDestination: (() -> AnyView)? = nil
    var body: some View {
        let card = RoamPOINodePresentation(node)
        VStack(alignment: .leading, spacing: 10) {
            Text("roamSub.w208.poi.badge").font(.caption.weight(.semibold)).foregroundStyle(.tint)
            if let title = node.templateTitle { Text(verbatim: title).font(.headline) }
            else if !node.name.isEmpty { Text(verbatim: node.name).font(.headline) }
            else { Text("roamSub.w208.poi.taskUnknown").font(.headline) }
            if card.offline {
                Text(LocalizedStringKey(card.offlineKeepsVoucher ? "roamSub.w208.poi.offlineVoucher" : "roamSub.w208.poi.offline"))
                    .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("roamSub.w208.poi.offline")
            }
            HStack(spacing: 0) {
                Text(LocalizedStringKey(card.validationKey))
                if card.grantsCoupon { Text("roamSub.w208.poi.coupon") }
            }.font(.footnote).accessibilityElement(children: .combine).accessibilityIdentifier("roamSub.w208.poi.method")
            Label(LocalizedStringKey(node.favorited ? "roamSub.w208.poi.favorited" : "roamSub.w208.poi.favorite"), systemImage: node.favorited ? "heart.fill" : "heart")
                .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("roamSub.w208.poi.favoriteState")
            if node.coordinate == nil { Label("roamSub.w208.poi.noNavigation", systemImage: "location.slash").font(.footnote).foregroundStyle(.secondary) }
            NavigationLink {
                RoamCityStampFlowView(kind: "sign", place: node.name.isEmpty ? nil : node.name, cameraDestination: stampDestination)
            } label: { Label("roamSub.w208.poi.dropStamp", systemImage: "envelope") }
                .frame(minHeight: 44).accessibilityIdentifier("roamSub.w208.poi.dropStamp")
            if card.primary == .showVoucher {
                NavigationLink { RoamCityVoucherCodeView(poiID: node.poiId, name: node.name) } label: {
                    Label(LocalizedStringKey(card.primaryKey), systemImage: "qrcode")
                }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                    .accessibilityIdentifier("roamSub.w208.poi.primary")
            } else {
                Button(LocalizedStringKey(card.primaryKey)) {}.buttonStyle(.borderedProminent).frame(minHeight: 44)
                    .disabled(true).accessibilityIdentifier("roamSub.w208.poi.primary")
                if card.primary == .interact {
                    Text("roamSub.w208.poi.interactDormant").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("roamSub.w208.poi.node")
    }
}

/// 据点未开放或已下线 (HTTP/business 410). Not retryable.
struct RoamPOIUnavailableView: View {
    var onBack: (() -> Void)? = nil
    var body: some View {
        ContentUnavailableView {
            Label("roamSub.w208.poi.unavailable", systemImage: "mappin.slash")
        } description: { Text("roamSub.w208.poi.unavailableHint") } actions: {
            if let onBack { Button("roamSub.w208.poi.backToMap", action: onBack) }
        }.accessibilityIdentifier("roamSub.w208.poi.unavailable")
    }
}

/// 找不到这个据点: the entry carried no poiId, so a retry cannot help.
struct RoamPOIMissingView: View {
    var onBack: (() -> Void)? = nil
    var body: some View {
        ContentUnavailableView {
            Label("roamSub.w208.poi.missing", systemImage: "questionmark.circle")
        } description: { Text("roamSub.w208.poi.missingHint") } actions: {
            if let onBack { Button("roamSub.w208.poi.backToMap", action: onBack) }
        }.accessibilityIdentifier("roamSub.w208.poi.missing")
    }
}

/// `subpackageRoam/citynode-code`: opened from a known city node, the code is requested on appear
/// (still behind the existing VerificationCodeApproval). A missing poiId has no retry.
@MainActor struct RoamCityVoucherCodeView: View {
    let poiID: Int?
    var name: String? = nil
    @Environment(\.verificationCodeFactory) private var codeFactory
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if let poiID, poiID > 0 {
            if let codeFactory {
                VerificationCodeView(model: codeFactory(.init(kind: .cityVoucher, id: poiID)),
                                     title: RoamCityVoucherCopy.displayName(name), autoIssue: true)
            } else {
                ContentUnavailableView("roamSub.w208.voucher.disabled", systemImage: "lock",
                                       description: Text("roamSub.w208.voucher.desc"))
                    .accessibilityIdentifier("roamSub.w208.voucher.disabled")
            }
        } else {
            ContentUnavailableView {
                Label("roamSub.w208.voucher.missing", systemImage: "qrcode")
            } description: { Text("roamSub.w208.voucher.missingHint") } actions: {
                Button("roamSub.w208.voucher.back") { dismiss() }.accessibilityIdentifier("roamSub.w208.voucher.back")
            }.accessibilityIdentifier("roamSub.w208.voucher.missing")
        }
    }
}

/// `subpackageRoam/citystamp` write step. The photo comes from the existing stamp camera; posting
/// and exchanging run only through RoamStampExchangeCoordinator, which stays dormant until its
/// executor is approved. A receipt (live or DEBUG fixture) moves to the print slip.
@MainActor struct RoamCityStampFlowView: View {
    let kind: String?
    let place: String?
    var cameraDestination: (() -> AnyView)? = nil
    var exchange: RoamStampExchangeCoordinator? = nil
    var draft: RoamStampExchangeDraft? = nil
    var fixtureReceipt: RoamStampExchangeReceipt? = nil
    @State private var note = ""
    @State private var receipt: RoamStampExchangeReceipt?
    @State private var working = false
    @State private var failed = false
    private let openedAt = Date()
    private var placeText: Text { place.map { Text(verbatim: $0) } ?? Text("roamSub.w208.stamp.defaultPlace") }
    private var canSend: Bool { exchange != nil && draft != nil && !working }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(RoamStampSlip.titleKey(kind: kind))).font(.title2.bold())
                    HStack(spacing: 4) { Text(verbatim: RoamStampSlip.dateLabel(openedAt) + " ·"); placeText }
                        .font(.subheadline).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("roamSub.w208.stamp.header")
                if let receipt { RoamStampSlipView(slip: RoamStampSlip(receipt), place: placeText, openedAt: openedAt) }
                else { writeStep }
            }.padding()
        }.navigationTitle(Text(LocalizedStringKey(RoamStampSlip.titleKey(kind: kind))))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("roamSub.w208.stamp.flow")
    }
    private var writeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("roamSub.w208.stamp.noteHeader").font(.headline)
                Spacer()
                Text(verbatim: "\(note.count)/\(RoamStampSlip.captionLimit)").font(.caption.monospacedDigit())
                    .accessibilityIdentifier("roamSub.w208.stamp.counter")
            }
            TextField("roamSub.w208.stamp.placeholder", text: $note, axis: .vertical)
                .lineLimit(2...4).textFieldStyle(.roundedBorder)
                .onChange(of: note) { _, value in if value.count > RoamStampSlip.captionLimit { note = String(value.prefix(RoamStampSlip.captionLimit)) } }
                .accessibilityIdentifier("roamSub.w208.stamp.note")
            NavigationLink { if let cameraDestination { cameraDestination() } else { RoamStampCameraView() } } label: {
                Label("roamSub.w208.stamp.takePhoto", systemImage: "camera")
            }.frame(minHeight: 44).accessibilityIdentifier("roamSub.w208.stamp.takePhoto")
            Text("roamSub.w208.stamp.dragHint").font(.footnote).foregroundStyle(.secondary)
            Button {
                Task { await send() }
            } label: { Text(LocalizedStringKey(working ? "roamSub.w208.stamp.sending" : "roamSub.w208.stamp.send")).frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.borderedProminent).disabled(!canSend && fixtureReceipt == nil)
                .accessibilityIdentifier("roamSub.w208.stamp.send")
            if failed { Text("roamSub.w208.stamp.retry").font(.footnote).foregroundStyle(.red).accessibilityIdentifier("roamSub.w208.stamp.failed") }
            if exchange == nil && fixtureReceipt == nil {
                Text("roamSub.w208.stamp.dormant").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("roamSub.w208.stamp.dormant")
            }
        }
    }
    private func send() async {
        if let fixtureReceipt { receipt = fixtureReceipt; return }
        guard let exchange, let draft, !working else { return }
        working = true; failed = false
        defer { working = false }
        await exchange.submitOrRetry(draft)
        switch exchange.phase {
        case .exchanged, .noExchange: receipt = exchange.receipt
        case .unavailable: failed = false
        default: failed = true
        }
    }
}

/// Print step: slip fields, deterministic bars, tear (drag ≥ 80 pt) and scratch reveal. Reduce
/// Motion and VoiceOver get plain buttons; 收下，出发 stays locked until the caption is revealed.
@MainActor struct RoamStampSlipView: View {
    let slip: RoamStampSlip
    let place: Text
    let openedAt: Date
    @Environment(\.dismiss) private var dismiss
    @QuestifyReduceMotion private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var torn = false
    @State private var pull: CGFloat = 0
    @State private var scratched: CGFloat = 0
    @State private var revealed = false
    private static let tearDistance: CGFloat = 80
    private static let scratchNeeded: CGFloat = 600
    private var plainControls: Bool { reduceMotion || voiceOver }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !slip.got {
                VStack(alignment: .leading, spacing: 6) {
                    if let reason = slip.reason { Text(verbatim: reason).font(.headline) }
                    else { Text("roamSub.w208.stamp.noTicket").font(.headline) }
                    Text("roamSub.w208.stamp.noTicketHint").foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("roamSub.w208.stamp.noExchange")
            } else {
                paper.offset(y: torn ? 0 : pull)
                    .gesture(DragGesture().onChanged { value in
                        guard !torn, !plainControls else { return }
                        pull = max(0, value.translation.height)
                    }.onEnded { _ in
                        guard !torn else { return }
                        if pull >= Self.tearDistance { torn = true }
                        withAnimation(reduceMotion ? nil : .spring) { pull = 0 }
                    })
                if !torn {
                    Text("roamSub.w208.stamp.tearHint").font(.footnote).foregroundStyle(.secondary)
                    if plainControls {
                        Button("roamSub.w208.stamp.tear") { torn = true }.accessibilityIdentifier("roamSub.w208.stamp.tear")
                    }
                } else if !revealed {
                    Text("roamSub.w208.stamp.scratchHint").font(.footnote).foregroundStyle(.secondary)
                    Button("roamSub.w208.stamp.scratch") { revealed = true }.accessibilityIdentifier("roamSub.w208.stamp.scratch")
                } else {
                    Text("roamSub.w208.stamp.takeHint").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button {
                dismiss()
            } label: { Text("roamSub.w208.stamp.done").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.borderedProminent).disabled(slip.got && !revealed)
                .accessibilityIdentifier("roamSub.w208.stamp.done")
            if slip.got && !revealed { Text("roamSub.w208.stamp.revealFirst").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var paper: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("roamSub.w208.stamp.departure").font(.caption2).foregroundStyle(.secondary)
                    place.font(.headline)
                    Text(openedAt, format: .dateTime.hour().minute()).font(.caption)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("roamSub.w208.stamp.serialLabel").font(.caption2).foregroundStyle(.secondary)
                    Text(verbatim: slip.serial).font(.title3.monospacedDigit().bold()).accessibilityIdentifier("roamSub.w208.stamp.serial")
                    Text("roamSub.w208.stamp.serialHint").font(.caption2)
                }
            }
            Divider()
            HStack {
                VStack(alignment: .leading) { Text("roamSub.w208.stamp.leftBy").font(.caption2).foregroundStyle(.secondary); Text("roamSub.w208.stamp.someone").font(.caption) }
                Spacer()
                VStack(alignment: .leading) {
                    Text("roamSub.w208.stamp.leftAt").font(.caption2).foregroundStyle(.secondary)
                    Text(verbatim: slip.leftAt ?? "—").font(.caption.monospacedDigit())
                }
            }
            Divider()
            Text("roamSub.w208.stamp.forYou").font(.caption2).foregroundStyle(.secondary)
            ZStack {
                Group {
                    if let caption = slip.caption { Text(verbatim: caption) } else { Text("roamSub.w208.stamp.noCaption") }
                }.font(.body).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityHidden(!revealed)
                    .accessibilityIdentifier("roamSub.w208.stamp.caption")
                if !revealed {
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(max(0.15, 1 - Double(scratched / Self.scratchNeeded))))
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            guard torn, !plainControls else { return }
                            scratched += abs(value.translation.width) / 8 + abs(value.translation.height) / 8
                            if scratched >= Self.scratchNeeded * 0.6 { revealed = true }
                        })
                        .accessibilityHidden(true)
                }
            }
            Divider()
            HStack(spacing: 0) {
                ForEach(Array(slip.bars.enumerated()), id: \.offset) { _, bar in
                    Rectangle().frame(width: CGFloat(bar.width), height: 28).padding(.trailing, CGFloat(bar.gap))
                }
            }.accessibilityHidden(true)
        }.padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain).accessibilityIdentifier("roamSub.w208.stamp.slip")
    }
}

/// `citynode-code` title (node name, default 据点) and 出示给商家扫码,即可领取优惠券.
struct RoamCityVoucherHeading: View {
    let title: String?
    var body: some View {
        VStack(spacing: 6) {
            if let title { Text(verbatim: title).font(.title2.bold()) } else { Text("roamSub.w208.voucher.defaultName").font(.title2.bold()) }
            Text("roamSub.w208.voucher.desc").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("roamSub.w208.voucher.heading")
    }
}
