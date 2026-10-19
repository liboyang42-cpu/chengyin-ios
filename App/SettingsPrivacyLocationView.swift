import SwiftUI

/// Settings row 隐私与定位 (mini-program `pages/shezhi` privacy sheet), placed
/// after 我的收藏 as in the source. Nothing here writes: presence sharing has
/// no reviewed write path yet, and roam withdrawal reuses the existing flow.
@MainActor struct SettingsPrivacyLocationEntry: View {
    let session: AppSession
    var body: some View {
        if session.account != nil {
            Section {
                NavigationLink {
                    SettingsPrivacyLocationView(mediaReader: session.ownMediaReader,
                        compliance: session.accountComplianceCoordinator, market: session.operationalMarket)
                } label: {
                    Label { Text("member.privacy.title", tableName: "MemberProfile") } icon: { Image(systemName: "hand.raised") }
                }.accessibilityIdentifier("settings.privacyLocation")
            }
        }
    }
}

@MainActor struct SettingsPrivacyLocationView: View {
    let mediaReader: any OwnMediaReading
    var compliance: AccountComplianceCoordinator? = nil
    var market: RegionalMarket? = nil
    var legalReader: any SettingsLegalReading = SettingsBundledLegalReader()
    @State private var showsRoam = false

    var body: some View {
        Form {
            Section {
                NavigationLink { OwnMediaReviewView(reader: mediaReader) } label: {
                    Text("member.privacy.media.open", tableName: "MemberProfile")
                }.accessibilityIdentifier("member.privacy.media")
            } header: { Text("member.privacy.media.title", tableName: "MemberProfile") }
            Section {
                Text("member.privacy.presence.detail", tableName: "MemberProfile").font(.footnote).foregroundStyle(.secondary)
                Button {} label: { Text("member.privacy.presence.off", tableName: "MemberProfile") }
                    .disabled(true).accessibilityIdentifier("member.privacy.presence.off")
            } header: { Text("member.privacy.presence.title", tableName: "MemberProfile") } footer: { Text("member.privacy.presence.unavailable", tableName: "MemberProfile") }
            Section {
                Text("member.privacy.roam.detail", tableName: "MemberProfile").font(.footnote).foregroundStyle(.secondary)
                if compliance != nil {
                    Button { showsRoam = true } label: { Text("member.privacy.roam.withdraw", tableName: "MemberProfile") }
                        .accessibilityIdentifier("member.privacy.roam.withdraw")
                }
            } header: { Text("member.privacy.roam.title", tableName: "MemberProfile") }
        }
        .navigationTitle(Text("member.privacy.title", tableName: "MemberProfile"))
        .sheet(isPresented: $showsRoam) {
            if let compliance {
                NavigationStack {
                    AccountComplianceSheet(coordinator: compliance, destination: .roam, market: market, legalReader: legalReader)
                }
            }
        }
    }
}

/// 我的待审媒体: newest first, 50 per page, older pages by `beforeId`.
@MainActor struct OwnMediaReviewView: View {
    let reader: any OwnMediaReading
    enum Phase: Equatable { case loading, signedOut, unavailable, denied, failed, ready }
    @State private var phase: Phase = .loading
    @State private var rows: [OwnMediaAsset] = []
    @State private var cursor: Int64?
    @State private var loadingMore = false
    @State private var moreFailed = false

    var body: some View {
        List {
            switch phase {
            case .loading: ProgressView().accessibilityIdentifier("member.media.loading")
            case .signedOut: Text("member.media.signedOut", tableName: "MemberProfile").accessibilityIdentifier("member.media.signedOut")
            case .unavailable: Text("member.media.unavailable", tableName: "MemberProfile").foregroundStyle(.secondary)
                    .accessibilityIdentifier("member.media.unavailable")
            case .denied: Text("member.media.denied", tableName: "MemberProfile").accessibilityIdentifier("member.media.denied")
            case .failed:
                VStack(alignment: .leading, spacing: 6) {
                    Text("member.media.failed", tableName: "MemberProfile")
                    Button { Task { await reload() } } label: { Text("member.media.refresh", tableName: "MemberProfile") }
                        .accessibilityIdentifier("member.media.retry")
                }.accessibilityIdentifier("member.media.failed")
            case .ready:
                if rows.isEmpty {
                    Text("member.media.empty", tableName: "MemberProfile").foregroundStyle(.secondary)
                        .accessibilityIdentifier("member.media.empty")
                }
                ForEach(rows) { row in OwnMediaRow(asset: row).accessibilityIdentifier("member.media.row.\(row.id)") }
                if cursor != nil {
                    Button { Task { await loadMore() } } label: {
                        if loadingMore { ProgressView() } else { Text("member.media.older", tableName: "MemberProfile") }
                    }.disabled(loadingMore).accessibilityIdentifier("member.media.older")
                }
                if moreFailed { Text("member.media.failed", tableName: "MemberProfile").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(Text("member.privacy.media.title", tableName: "MemberProfile"))
        .toolbar {
            if phase == .ready || phase == .failed {
                Button { Task { await reload() } } label: { Text("member.media.refresh", tableName: "MemberProfile") }
                    .accessibilityIdentifier("member.media.refresh")
            }
        }
        .task(id: reader.scope) { await reload() }
    }

    private func reload() async {
        let scope = reader.scope
        rows = []; cursor = nil; moreFailed = false
        guard reader.isSignedIn else { phase = .signedOut; return }
        guard reader.isAvailable else { phase = .unavailable; return }
        phase = .loading
        do {
            let page = try await reader.page(before: nil)
            guard scope == reader.scope else { return }
            rows = page.rows; cursor = page.nextCursor; phase = .ready
        } catch is CancellationError {
        } catch { if scope == reader.scope { phase = Self.phase(for: error) } }
    }
    private func loadMore() async {
        guard let before = cursor, !loadingMore else { return }
        let scope = reader.scope
        loadingMore = true; moreFailed = false
        defer { loadingMore = false }
        do {
            let page = try await reader.page(before: before)
            guard scope == reader.scope, cursor == before else { return }
            rows += page.rows; cursor = page.nextCursor
        } catch is CancellationError {
        } catch {
            guard scope == reader.scope else { return }
            if case .failed = Self.phase(for: error) { moreFailed = true } else { rows = []; cursor = nil; phase = Self.phase(for: error) }
        }
    }
    static func phase(for error: Error) -> Phase {
        if error as? APIError == .unauthorized { return .signedOut }
        if error as? APIError == .notConfigured { return .unavailable }
        if error as? OwnMediaReadFailure == .rejected(code: 403) { return .denied }
        return .failed
    }
}

struct OwnMediaRow: View {
    let asset: OwnMediaAsset
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                type
                Text(verbatim: "#\(asset.id)").foregroundStyle(.secondary).font(.footnote.monospacedDigit())
                Spacer()
                state.font(.subheadline.weight(.semibold))
            }
            if !asset.reviewReason.isEmpty { Text(verbatim: asset.reviewReason).font(.footnote).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private var type: some View {
        switch asset.mediaType {
        case .image: Text("member.media.type.image", tableName: "MemberProfile")
        case .audio: Text("member.media.type.audio", tableName: "MemberProfile")
        case .model3D: Text("member.media.type.model", tableName: "MemberProfile")
        case .other: Text("member.media.type.other", tableName: "MemberProfile")
        }
    }
    @ViewBuilder private var state: some View {
        switch asset.reviewState {
        case .hold: Text("member.media.state.hold", tableName: "MemberProfile").foregroundStyle(.orange)
        case .approved: Text("member.media.state.approved", tableName: "MemberProfile").foregroundStyle(.green)
        case .rejected: Text("member.media.state.rejected", tableName: "MemberProfile").foregroundStyle(.red)
        case .unavailable: Text("member.media.state.unavailable", tableName: "MemberProfile").foregroundStyle(.secondary)
        }
    }
}
