import SwiftUI

enum MerchantCityNodeCopy {
    static let table = "MerchantCityNode"
    static func text(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: table) }
    static func string(_ key: String) -> String { String(localized: String.LocalizationValue(key), table: table) }
    static func format(_ key: String, _ arguments: CVarArg...) -> String { String(format: string(key), arguments: arguments) }
    /// Business messages stay verbatim; transport failures use the mini client's network copy.
    @MainActor static func failure(_ c: MerchantContentCoordinator, fallback: String) -> String {
        if let message = c.serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty { return message }
        switch c.issue {
        case "merchant.content.loadFailed"?: return string("merchantCityNode.error.network")
        case "merchant.content.unknown"?: return string("merchantCityNode.write.unknown")
        case "merchant.content.denied"?: return string("merchantCityNode.permission.manage")
        case "merchant.content.disabled"?: return string("merchantCityNode.write.disabled")
        case "merchant.content.signedOut"?: return string("merchantCityNode.error.signedOut")
        default: return fallback
        }
    }
}

struct MerchantCityNodeBadge: View {
    let key: String
    let tone: Color
    var body: some View {
        MerchantCityNodeCopy.text(key).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(tone).background(tone.opacity(0.14), in: Capsule())
    }
}

struct MerchantCityNodeInlineError: View {
    let titleKey: String
    let message: String
    let actionKey: String
    let identifier: String
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label { MerchantCityNodeCopy.text(titleKey).font(.subheadline.weight(.semibold)) } icon: { Image(systemName: "exclamationmark.circle") }
            Text(verbatim: message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(action: action) { MerchantCityNodeCopy.text(actionKey) }.font(.footnote.weight(.semibold))
                .accessibilityIdentifier(identifier)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
    }
}

/// Native counterpart of mini `pages/merchant/citynode/index` (成为节点).
@MainActor struct MerchantCityNodeHubView: View {
    private struct Poster: Identifiable, Equatable {
        enum Phase: Equatable { case loading, ready(MerchantCityNodePosterCode), failed(String) }
        let id = UUID()
        let poiID: Int
        var phase: Phase
    }
    let service: any MerchantContentServing
    let businessReader: (any MerchantBusinessReading)?
    let businessJournal: (any MerchantBusinessIntentStore)?
    let placeSearch: (any PublishingPlaceSearching)?
    let isOfflineFixture: Bool
    private let templateSeed: Int?
    @StateObject private var model: MerchantContentViewModel
    @StateObject private var claimModel: MerchantContentViewModel
    @State private var canVerify = false
    @State private var showsClaim = false
    @State private var showsCreate = false
    @State private var showsInfo = false
    @State private var confirming = false
    @State private var target: String?
    @State private var claimTarget: String?
    @State private var toast: String?
    @State private var poster: Poster?
    @State private var posterTicket = 0
    @State private var everLoaded = false
    @State private var listEverLoaded = false

    init(service: any MerchantContentServing, businessReader: (any MerchantBusinessReading)? = nil,
         businessJournal: (any MerchantBusinessIntentStore)? = nil, placeSearch: (any PublishingPlaceSearching)? = nil,
         isOfflineFixture: Bool = false, templateSeed: Int? = nil) {
        self.service = service; self.businessReader = businessReader; self.businessJournal = businessJournal
        self.placeSearch = placeSearch; self.isOfflineFixture = isOfflineFixture; self.templateSeed = templateSeed
        _model = StateObject(wrappedValue: MerchantContentViewModel(service: service, query: .city))
        _claimModel = StateObject(wrappedValue: MerchantContentViewModel(service: service, query: .claimable(keyword: "")))
    }
    private var c: MerchantContentCoordinator { model.coordinator }
    private var idle: Bool { !c.busy && !c.locked && c.review == nil && !confirming }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) { content }.padding()
        }
        .navigationTitle(MerchantCityNodeCopy.string("merchantCityNode.title"))
        .task(id: service.scope) { await reload(); everLoaded = true }
        .refreshable { if idle { await reload() } }
        .onAppear { if everLoaded, idle { Task { await reload() } } }
        .onDisappear { model.suspend() }
        .overlay(alignment: .bottom) { toastView }
        .task(id: toast) { if toast != nil { try? await Task.sleep(nanoseconds: 4_000_000_000); toast = nil } }
        .alert(MerchantCityNodeCopy.string("merchantCityNode.info.title"), isPresented: $showsInfo) {
            Button(MerchantCityNodeCopy.string("merchantCityNode.action.ok"), role: .cancel) { }
        } message: { MerchantCityNodeCopy.text("merchantCityNode.info.body") }
        .confirmationDialog(dialogTitle(c.review?.command), isPresented: Binding(get: { c.isCurrent && c.review != nil && !showsClaim },
            set: { if !$0 && !confirming { model.cancel() } }), titleVisibility: .visible) {
            if let review = c.review {
                Button(confirmLabel(review.command), role: isDestructive(review.command) ? .destructive : nil) {
                    confirming = true; Task { await confirm(review) }
                }.accessibilityIdentifier("cityNodeHub.confirm")
                Button(MerchantCityNodeCopy.string("merchantCityNode.action.cancel"), role: .cancel) { model.cancel() }
            }
        } message: { dialogMessage(c.review?.command) }
        .sheet(isPresented: $showsClaim, onDismiss: { claimModel.cancel() }) { claimSheet }
        .sheet(item: $poster, onDismiss: { posterTicket += 1 }) { shown in posterSheet(shown) }
        .navigationDestination(isPresented: $showsCreate) {
            MerchantCityNodeCreateView(service: service, placeSearch: placeSearch, isOfflineFixture: isOfflineFixture, templateSeed: templateSeed)
        }
    }

    @ViewBuilder private var content: some View {
        if c.isCurrent, let snapshot = c.snapshot { ready(snapshot) }
        else if c.busy || c.loadedScope != service.scope {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 16).fill(.quaternary).frame(height: 88) }
            }.redacted(reason: .placeholder).accessibilityIdentifier("cityNodeHub.loading")
        } else if c.issue == "merchant.content.denied" {
            state(title: "merchantCityNode.permission.title", sub: MerchantCityNodeCopy.string("merchantCityNode.permission.sub"), identifier: "cityNodeHub.noPermission", retry: false)
        } else {
            state(title: "merchantCityNode.load.title", sub: MerchantCityNodeCopy.string(c.issue == "merchant.content.signedOut" ? "merchantCityNode.error.signedOut" : "merchantCityNode.load.sub"),
                  identifier: "cityNodeHub.loadError", retry: true)
        }
    }

    private func state(title: String, sub: String, identifier: String, retry: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: retry ? "wifi.exclamationmark" : "lock").font(.largeTitle).foregroundStyle(.secondary)
            MerchantCityNodeCopy.text(title).font(.headline)
            Text(verbatim: sub).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if retry {
                Button { Task { await reload() } } label: { MerchantCityNodeCopy.text("merchantCityNode.action.retry") }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("cityNodeHub.retry")
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 40).accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }

    @ViewBuilder private func ready(_ s: MerchantContentSnapshot) -> some View {
        let p = MerchantCityNodeHubProjection(list: s.value)
        intro(p.quota)
        Button { goCreate(p.quota) } label: {
            HStack { MerchantCityNodeCopy.text("merchantCityNode.place.action"); Spacer(); Image(systemName: "arrow.right") }
                .font(.headline).padding().frame(maxWidth: .infinity)
                .background(p.quota.state == .full || p.quota.state == .none ? Color.secondary.opacity(0.25) : Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(p.quota.state == .full || p.quota.state == .none ? Color.secondary : Color.white)
        }.buttonStyle(.plain).accessibilityIdentifier("cityNodeHub.place")
        HStack(spacing: 12) {
            Button { openClaim() } label: { Label { MerchantCityNodeCopy.text("merchantCityNode.claim.open") } icon: { Image(systemName: "plus") } }
                .buttonStyle(.bordered).accessibilityIdentifier("cityNodeHub.claim")
            if canVerify, let businessReader, let businessJournal {
                NavigationLink { CityNodeRedeemView(reader: businessReader, journal: businessJournal) } label: {
                    Label { MerchantCityNodeCopy.text("merchantCityNode.scan.open") } icon: { Image(systemName: "qrcode.viewfinder") }
                }.buttonStyle(.bordered).accessibilityIdentifier("cityNodeHub.scan")
            }
        }
        HStack(alignment: .firstTextBaseline) {
            MerchantCityNodeCopy.text("merchantCityNode.section.title").font(.title3.bold())
            Spacer()
            Text(verbatim: MerchantCityNodeCopy.format("merchantCityNode.section.count", p.itemCount)).font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("cityNodeHub.count")
        }
        if c.locked {
            VStack(alignment: .leading, spacing: 6) {
                MerchantCityNodeCopy.text("merchantCityNode.write.lockedTitle").font(.subheadline.weight(.semibold))
                MerchantCityNodeCopy.text("merchantCityNode.write.lockedBody").font(.footnote).foregroundStyle(.secondary)
                Button { Task { await reload() } } label: { MerchantCityNodeCopy.text("merchantCityNode.write.readback") }
                    .font(.footnote.weight(.semibold)).disabled(c.busy).accessibilityIdentifier("cityNodeHub.readback")
            }.padding(10).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("cityNodeHub.locked")
        }
        ForEach(p.applications) { applicationRow($0) }
        if p.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "mappin.slash").font(.largeTitle).foregroundStyle(.secondary)
                MerchantCityNodeCopy.text("merchantCityNode.empty.title").font(.headline)
                MerchantCityNodeCopy.text("merchantCityNode.empty.sub").font(.subheadline).foregroundStyle(.secondary)
                if p.showsEmptyPlacementAction {
                    Button { goCreate(p.quota) } label: { MerchantCityNodeCopy.text("merchantCityNode.place.action") }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("cityNodeHub.empty.place")
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 28).accessibilityElement(children: .contain).accessibilityIdentifier("cityNodeHub.empty")
        }
        ForEach(p.nodes) { nodeRow($0) }
        if !service.permitsWrites || !isOfflineFixture {
            MerchantCityNodeCopy.text("merchantCityNode.write.disabled").font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("cityNodeHub.writesDisabled")
        }
    }

    @ViewBuilder private func intro(_ quota: MerchantCityQuota) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                MerchantCityNodeCopy.text("merchantCityNode.intro").font(.subheadline)
                Button { showsInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel(MerchantCityNodeCopy.text("merchantCityNode.info.title")).accessibilityIdentifier("cityNodeHub.info")
            }
            switch quota.state {
            case .unknown:
                if c.busy { MerchantCityNodeCopy.text("merchantCityNode.quota.loading").font(.footnote).foregroundStyle(.secondary) }
                else {
                    MerchantCityNodeInlineError(titleKey: "merchantCityNode.quota.unknownTitle", message: MerchantCityNodeCopy.string("merchantCityNode.quota.unknownSub"),
                        actionKey: "merchantCityNode.action.retry", identifier: "cityNodeHub.quota.retry") { if idle { Task { await reload() } } }
                }
            default:
                Text(verbatim: quotaLine(quota)).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("cityNodeHub.quota")
            }
        }
    }

    private func quotaLine(_ quota: MerchantCityQuota) -> String {
        let base = MerchantCityNodeCopy.format("merchantCityNode.quota.line", quota.used ?? 0, quota.maximum ?? 0)
        switch quota.state {
        case .none: return base + MerchantCityNodeCopy.string("merchantCityNode.quota.noneSuffix")
        case .full: return base + MerchantCityNodeCopy.string("merchantCityNode.quota.fullSuffix")
        default: return base
        }
    }

    private func rowKey(_ command: MerchantContentCommand) -> String { command.key + ":" + command.scopeKey }
    private func rowFailure(_ key: String) -> Bool {
        target == key && !c.busy && c.review == nil && c.receipt == nil && c.issue != nil && !confirming
    }

    @ViewBuilder private func applicationRow(_ row: MerchantCityNodeApplicationRow) -> some View {
        let cancel = MerchantContentCommand.cancelClaim(poiID: row.id)
        let key = rowKey(cancel), working = target == key && (c.busy || confirming)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(verbatim: MerchantCityNodeCopy.format("merchantCityNode.application.title",
                    MerchantCityNodeCopy.string(row.kind == .claim ? "merchantCityNode.application.claim" : "merchantCityNode.application.placement"),
                    row.name ?? MerchantCityNodeCopy.string("merchantCityNode.application.fallbackName"))).font(.headline)
                Spacer()
                switch row.audit {
                case .reviewing: MerchantCityNodeBadge(key: "merchantCityNode.audit.reviewing", tone: .secondary)
                case .approved: MerchantCityNodeBadge(key: "merchantCityNode.audit.approved", tone: .green)
                case .rejected: MerchantCityNodeBadge(key: "merchantCityNode.audit.rejected", tone: .orange)
                }
            }
            if row.audit == .rejected, let reason = row.auditReason {
                VStack(alignment: .leading, spacing: 2) {
                    MerchantCityNodeCopy.text("merchantCityNode.audit.reason").font(.caption.weight(.semibold))
                    Text(verbatim: reason).font(.footnote)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("cityNodeHub.reason.\(row.id)")
            }
            if row.withdrawable {
                Button { prepare(cancel) } label: {
                    MerchantCityNodeCopy.text(working ? "merchantCityNode.withdraw.working" : "merchantCityNode.withdraw.action")
                }.buttonStyle(.bordered).disabled(!idle).accessibilityIdentifier("cityNodeHub.withdraw.\(row.id)")
            }
            if rowFailure(key) {
                MerchantCityNodeInlineError(titleKey: "merchantCityNode.withdraw.failed", message: MerchantCityNodeCopy.failure(c, fallback: MerchantCityNodeCopy.string("merchantCityNode.withdraw.fallback")),
                    actionKey: "merchantCityNode.action.retry", identifier: "cityNodeHub.withdraw.retry.\(row.id)") { prepare(cancel) }
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain).accessibilityIdentifier("cityNodeHub.application.\(row.id)")
    }

    @ViewBuilder private func nodeRow(_ row: MerchantCityNodeRow) -> some View {
        let toggle = MerchantContentCommand.cityStatus(poiID: row.id, online: !row.isOnline)
        let key = rowKey(toggle), working = target == key && (c.busy || confirming)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(verbatim: row.name).font(.headline)
                Spacer()
                MerchantCityNodeBadge(key: row.isOnline ? "merchantCityNode.node.online" : "merchantCityNode.node.offline", tone: row.isOnline ? .green : .secondary)
            }
            Text(verbatim: [row.templateTitle ?? MerchantCityNodeCopy.string("merchantCityNode.node.noTemplate"), row.tags].compactMap { $0 }.joined(separator: " · "))
                .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("cityNodeHub.node.sub.\(row.id)")
            HStack {
                if row.usesPosterCode && canVerify && service is any MerchantCityNodePosterReading {
                    Button { loadPoster(row.id) } label: { Label { MerchantCityNodeCopy.text("merchantCityNode.poster.open") } icon: { Image(systemName: "qrcode") } }
                        .accessibilityIdentifier("cityNodeHub.poster.\(row.id)")
                }
                Spacer()
                Button { prepare(toggle) } label: {
                    MerchantCityNodeCopy.text(working ? "merchantCityNode.node.working" : row.isOnline ? "merchantCityNode.node.takeOffline" : "merchantCityNode.node.putOnline")
                }.buttonStyle(.bordered).disabled(!idle).accessibilityIdentifier("cityNodeHub.toggle.\(row.id)")
            }
            if rowFailure(key) {
                MerchantCityNodeInlineError(titleKey: row.isOnline ? "merchantCityNode.node.offlineFailed" : "merchantCityNode.node.onlineFailed",
                    message: MerchantCityNodeCopy.failure(c, fallback: MerchantCityNodeCopy.string(row.isOnline ? "merchantCityNode.node.offlineFallback" : "merchantCityNode.node.onlineFallback")),
                    actionKey: "merchantCityNode.action.retry", identifier: "cityNodeHub.toggle.retry.\(row.id)") { prepare(toggle) }
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain).accessibilityIdentifier("cityNodeHub.node.\(row.id)")
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(verbatim: toast).font(.subheadline).padding(.horizontal, 16).padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule()).padding(.bottom, 24).accessibilityIdentifier("cityNodeHub.toast")
        }
    }

    // MARK: Actions

    private func reload() async {
        await model.load()
        if c.isCurrent, c.snapshot != nil { listEverLoaded = true }
        await refreshVerify()
    }
    private func refreshVerify() async {
        guard let businessReader, let merchantID = c.snapshot?.access.merchantID else { canVerify = false; return }
        let scope = service.scope
        let access = try? await businessReader.access()
        guard scope == service.scope else { return }
        canVerify = access.map { MerchantCityNodeVerifyGrant.allows(permissions: $0.permissions, accessMerchantID: $0.merchantID, contentMerchantID: merchantID) } ?? false
    }
    private func writable(_ command: MerchantContentCommand) -> Bool {
        guard let path = try? command.request().path else { return false }
        return MerchantCityNodeWriteGate.enabled(permitsWrites: service.permitsWrites, isOfflineExample: isOfflineFixture, path: path)
    }
    private func goCreate(_ quota: MerchantCityQuota) {
        guard idle else { return }
        switch quota.state {
        case .unknown: toast = MerchantCityNodeCopy.string("merchantCityNode.place.quotaRetry"); Task { await reload() }
        case .none: toast = MerchantCityNodeCopy.string("merchantCityNode.place.noQuota")
        case .full: toast = MerchantCityNodeCopy.string("merchantCityNode.place.full")
        case .available: showsCreate = true
        }
    }
    private func prepare(_ command: MerchantContentCommand) {
        guard idle else { return }
        guard writable(command) else { toast = MerchantCityNodeCopy.string("merchantCityNode.write.disabled"); return }
        target = rowKey(command); model.prepare(command)
    }
    private func confirm(_ review: MerchantContentReview) async {
        await model.confirm(review); confirming = false
        guard let receipt = c.receipt else { return }
        switch review.command {
        case .cancelClaim:
            toast = MerchantCityNodeCopy.string("merchantCityNode.withdraw.success"); claimModel.invalidate()
        case .cityStatus:
            toast = receipt.data.text.flatMap { $0.isEmpty ? nil : $0 } ?? MerchantCityNodeCopy.string("merchantCityNode.node.updated")
        default: break
        }
        target = nil
        await reload()
    }

    // MARK: Claim sheet

    private func openClaim() {
        guard idle else { return }
        showsClaim = true
    }
    private var claimSheet: some View {
        NavigationStack {
            ScrollView { LazyVStack(alignment: .leading, spacing: 14) { claimContent }.padding() }
                .navigationTitle(MerchantCityNodeCopy.string("merchantCityNode.claim.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button { showsClaim = false } label: { MerchantCityNodeCopy.text("merchantCityNode.action.close") }.accessibilityIdentifier("cityNodeHub.claim.close")
                } }
                .task { if claimModel.coordinator.snapshot == nil && !claimModel.coordinator.busy { await claimModel.load() } }
                .confirmationDialog(dialogTitle(claimModel.coordinator.review?.command), isPresented: Binding(
                    get: { claimModel.coordinator.isCurrent && claimModel.coordinator.review != nil },
                    set: { if !$0 && !confirming { claimModel.cancel() } }), titleVisibility: .visible) {
                    if let review = claimModel.coordinator.review {
                        Button(confirmLabel(review.command)) { confirming = true; Task { await confirmClaim(review) } }
                            .accessibilityIdentifier("cityNodeHub.claim.confirm")
                        Button(MerchantCityNodeCopy.string("merchantCityNode.action.cancel"), role: .cancel) { claimModel.cancel() }
                    }
                } message: { dialogMessage(claimModel.coordinator.review?.command) }
        }
    }
    @ViewBuilder private var claimContent: some View {
        let cc = claimModel.coordinator
        if cc.isCurrent, let snapshot = cc.snapshot {
            if let rows = MerchantCityClaimableProjection.rows(snapshot.value["rows"]) {
                if rows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
                        MerchantCityNodeCopy.text("merchantCityNode.claim.empty").font(.headline)
                    }.frame(maxWidth: .infinity).padding(.vertical, 32).accessibilityIdentifier("cityNodeHub.claim.empty")
                }
                ForEach(rows) { claimRow($0) }
            } else {
                claimLoadError(MerchantCityNodeCopy.string("merchantCityNode.claim.malformed"))
            }
        } else if cc.busy || cc.loadedScope != service.scope {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32).accessibilityIdentifier("cityNodeHub.claim.loading")
        } else {
            claimLoadError(MerchantCityNodeCopy.failure(cc, fallback: MerchantCityNodeCopy.string("merchantCityNode.claim.loadFailed")))
        }
    }
    private func claimLoadError(_ message: String) -> some View {
        VStack(spacing: 10) {
            MerchantCityNodeCopy.text("merchantCityNode.claim.loadFailed").font(.headline)
            Text(verbatim: message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { Task { await claimModel.load() } } label: { MerchantCityNodeCopy.text("merchantCityNode.action.retry") }
                .buttonStyle(.borderedProminent).disabled(claimModel.coordinator.busy).accessibilityIdentifier("cityNodeHub.claim.retry")
        }.frame(maxWidth: .infinity).padding(.vertical, 28).accessibilityElement(children: .contain).accessibilityIdentifier("cityNodeHub.claim.error")
    }
    @ViewBuilder private func claimRow(_ row: MerchantCityClaimableRow) -> some View {
        let cc = claimModel.coordinator
        let command = MerchantContentCommand.claim(poiID: row.id)
        let key = rowKey(command), working = claimTarget == key && (cc.busy || confirming)
        let failed = claimTarget == key && !cc.busy && cc.review == nil && cc.receipt == nil && cc.issue != nil && !confirming
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: row.name).font(.headline)
                    Text(verbatim: row.detail ?? MerchantCityNodeCopy.string("merchantCityNode.claim.platformNode")).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button { prepareClaim(command) } label: {
                    MerchantCityNodeCopy.text(working ? "merchantCityNode.claim.working" : "merchantCityNode.claim.action")
                }.buttonStyle(.bordered).disabled(cc.busy || cc.locked || cc.review != nil || confirming).accessibilityIdentifier("cityNodeHub.claim.apply.\(row.id)")
            }
            if failed {
                MerchantCityNodeInlineError(titleKey: "merchantCityNode.claim.failed", message: MerchantCityNodeCopy.failure(cc, fallback: MerchantCityNodeCopy.string("merchantCityNode.claim.fallback")),
                    actionKey: "merchantCityNode.action.retry", identifier: "cityNodeHub.claim.retry.\(row.id)") { prepareClaim(command) }
            }
        }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain).accessibilityIdentifier("cityNodeHub.claim.row.\(row.id)")
    }
    private func prepareClaim(_ command: MerchantContentCommand) {
        let cc = claimModel.coordinator
        guard !cc.busy, !cc.locked, cc.review == nil, !confirming else { return }
        guard writable(command) else { toast = MerchantCityNodeCopy.string("merchantCityNode.write.disabled"); return }
        claimTarget = rowKey(command); claimModel.prepare(command)
    }
    private func confirmClaim(_ review: MerchantContentReview) async {
        await claimModel.confirm(review); confirming = false
        guard claimModel.coordinator.receipt != nil else { return }
        claimTarget = nil; showsClaim = false; claimModel.invalidate()
        toast = MerchantCityNodeCopy.string("merchantCityNode.claim.success")
        await reload()
    }

    // MARK: Poster

    private func loadPoster(_ poiID: Int) {
        guard canVerify else { toast = MerchantCityNodeCopy.string("merchantCityNode.permission.verify"); return }
        guard let reader = service as? any MerchantCityNodePosterReading else { return }
        posterTicket += 1
        let ticket = posterTicket, scope = service.scope
        if poster?.poiID == poiID { poster?.phase = .loading } else { poster = Poster(poiID: poiID, phase: .loading) }
        Task {
            let phase: Poster.Phase
            do { phase = .ready(try MerchantCityNodePosterCode(try await reader.cityPosterCode(poiID: poiID))) }
            catch is URLError { phase = .failed(MerchantCityNodeCopy.string("merchantCityNode.poster.network")) }
            catch { phase = .failed(MerchantCityNodeCopy.string("merchantCityNode.poster.failedSub")) }
            guard ticket == posterTicket, scope == service.scope, poster?.poiID == poiID else { return }
            poster?.phase = phase
        }
    }
    private func posterSheet(_ shown: Poster) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    switch shown.phase {
                    case .loading:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 240).accessibilityIdentifier("cityNodeHub.poster.loading")
                    case .ready(let code):
                        AsyncImage(url: code.imageURL) { phase in
                            if let image = phase.image { image.resizable().scaledToFit() }
                            else if phase.error != nil { Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(.secondary).padding(40) }
                            else { ProgressView() }
                        }.frame(width: 240, height: 240).accessibilityLabel(MerchantCityNodeCopy.text("merchantCityNode.poster.title"))
                            .accessibilityIdentifier("cityNodeHub.poster.image")
                        if let name = code.nodeName { Text(verbatim: name).font(.headline).accessibilityIdentifier("cityNodeHub.poster.name") }
                        MerchantCityNodeCopy.text("merchantCityNode.poster.hintPrint").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        MerchantCityNodeCopy.text("merchantCityNode.poster.hintKeep").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    case .failed(let message):
                        VStack(spacing: 10) {
                            MerchantCityNodeCopy.text("merchantCityNode.poster.failedTitle").font(.headline)
                            Text(verbatim: message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button { loadPoster(shown.poiID) } label: { MerchantCityNodeCopy.text("merchantCityNode.poster.retry") }
                                .buttonStyle(.borderedProminent).accessibilityIdentifier("cityNodeHub.poster.retry")
                        }.padding(.vertical, 28).accessibilityElement(children: .contain).accessibilityIdentifier("cityNodeHub.poster.error")
                    }
                }.padding()
            }
            .navigationTitle(MerchantCityNodeCopy.string("merchantCityNode.poster.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button { posterTicket += 1; poster = nil } label: { MerchantCityNodeCopy.text("merchantCityNode.action.close") }.accessibilityIdentifier("cityNodeHub.poster.close")
            } }
        }
    }

    // MARK: Confirmation copy

    private func dialogTitle(_ command: MerchantContentCommand?) -> String {
        switch command {
        case .claim?: return MerchantCityNodeCopy.string("merchantCityNode.confirm.claimTitle")
        case .cancelClaim?: return MerchantCityNodeCopy.string("merchantCityNode.confirm.withdrawTitle")
        case .cityStatus(_, let online)?: return MerchantCityNodeCopy.string(online ? "merchantCityNode.confirm.onlineTitle" : "merchantCityNode.confirm.offlineTitle")
        default: return ""
        }
    }
    private func dialogMessage(_ command: MerchantContentCommand?) -> Text {
        switch command {
        case .claim?: return MerchantCityNodeCopy.text("merchantCityNode.confirm.claimBody")
        case .cancelClaim?: return MerchantCityNodeCopy.text("merchantCityNode.confirm.withdrawBody")
        case .cityStatus(_, let online)?: return MerchantCityNodeCopy.text(online ? "merchantCityNode.confirm.onlineBody" : "merchantCityNode.confirm.offlineBody")
        default: return Text(verbatim: "")
        }
    }
    private func confirmLabel(_ command: MerchantContentCommand) -> String {
        switch command {
        case .claim: return MerchantCityNodeCopy.string("merchantCityNode.claim.action")
        case .cancelClaim: return MerchantCityNodeCopy.string("merchantCityNode.withdraw.action")
        case .cityStatus(_, let online): return MerchantCityNodeCopy.string(online ? "merchantCityNode.node.putOnline" : "merchantCityNode.node.takeOffline")
        default: return MerchantCityNodeCopy.string("merchantCityNode.action.ok")
        }
    }
    private func isDestructive(_ command: MerchantContentCommand) -> Bool {
        switch command { case .cancelClaim: return true; case .cityStatus(_, let online): return !online; default: return false }
    }
}
