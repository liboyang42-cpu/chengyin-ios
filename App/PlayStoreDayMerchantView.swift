import SwiftUI

/// Native counterpart of mini-program pages/play/merchant: arrival, photo proof, verification
/// hand-off and records only. Gameplay beyond the in-store quiz is handed back to the play host.
@MainActor struct PlayStoreDayMerchantView: View {
    @Bindable var model: PlayStoreDayCoordinator
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    var mediaScope: UUID = UUID()
    /// Hero artwork loads only from explicitly approved https hosts; otherwise a placeholder.
    var approvedImageHosts: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    @State private var pendingProof: PlayStoreDayPreparedProof?
    @State private var showingProof = false
    @State private var confirmRevoke = false

    private enum Sheet: String, Identifiable { case game, task; var id: String { rawValue } }
    private var sheet: Binding<Sheet?> {
        Binding(get: { model.game.show ? .game : model.taskVisible ? .task : nil },
                set: { if $0 == nil { model.closeSheets() } })
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loaded:
                if let node = model.node { content(node) } else { stateView("playStoreDay.state.notFound", id: "notFound") }
            case .loading: ProgressView { Text("playStoreDay.state.loading", tableName: "PlayStoreDay") }.accessibilityIdentifier("storeDayPage.state.loading")
            case .notFound: stateView("playStoreDay.state.notFound", id: "notFound")
            case .failed: stateView("playStoreDay.state.failed", id: "failed")
            case .signedOut: stateView("playStoreDay.state.signedOut", id: "signedOut")
            case .unavailable: stateView("playStoreDay.state.unavailable", id: "unavailable")
            }
        }
        .privacySensitive()
        .navigationTitle(Text("playStoreDay.title", tableName: "PlayStoreDay"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.nodeID) { await model.load() }
        .sheet(item: sheet) { item in
            switch item {
            case .game: gameSheet.presentationDetents([.medium, .large])
            case .task: taskSheet.presentationDetents([.medium])
            }
        }
        .confirmationDialog(Text("playStoreDay.proofConfirm.title", tableName: "PlayStoreDay"), isPresented: $showingProof, titleVisibility: .visible) {
            Button {
                guard let proof = pendingProof else { return }
                pendingProof = nil
                Task { await model.submitProof(proof) }
            } label: {
                if pendingProofIsPhoto { Text("playStoreDay.proofConfirm.photo", tableName: "PlayStoreDay") }
                else { Text("playStoreDay.proofConfirm.scan", tableName: "PlayStoreDay") }
            }
            Button(role: .cancel) { pendingProof = nil; model.cancelPreparedProof() } label: { Text("playStoreDay.cancel", tableName: "PlayStoreDay") }
        } message: { Text("playStoreDay.proofConfirm.notice", tableName: "PlayStoreDay") }
        .onChange(of: model.preparedProof) { _, proof in
            guard let proof else { return }
            pendingProof = proof
            // Let a closing task sheet finish before the confirmation is presented.
            Task { try? await Task.sleep(nanoseconds: 450_000_000); if pendingProof == proof, model.preparedProof == proof { showingProof = true } }
        }
        .onChange(of: showingProof) { _, visible in if !visible, pendingProof != nil { pendingProof = nil; model.cancelPreparedProof() } }
        .alert(Text("playStoreDay.modal.title", tableName: "PlayStoreDay"), isPresented: $model.consentPromptVisible) {
            Button { Task { await model.agreeConsent() } } label: { Text("playStoreDay.modal.confirm", tableName: "PlayStoreDay") }
                .accessibilityIdentifier("storeDayPage.modal.confirm")
            Button(role: .cancel) { model.declineConsent() } label: { Text("playStoreDay.cancel", tableName: "PlayStoreDay") }
        } message: { Text(verbatim: String(format: L("playStoreDay.modal.body"), storeName)) }
        .confirmationDialog(Text("playStoreDay.revokeConfirm.title", tableName: "PlayStoreDay"), isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button(role: .destructive) { Task { await model.revokeConsent() } } label: { Text("playStoreDay.consent.revoke", tableName: "PlayStoreDay") }
            Button(role: .cancel) {} label: { Text("playStoreDay.cancel", tableName: "PlayStoreDay") }
        }
        .onChange(of: model.dismissRequested) { _, requested in if requested { dismiss() } }
    }

    private var pendingProofIsPhoto: Bool { if case .photo = pendingProof { return true }; return false }
    private var storeName: String { model.node?.name ?? L("playStoreDay.consent.defaultStore") }
    private func L(_ key: String.LocalizationValue) -> String { String(localized: key, table: "PlayStoreDay") }

    private func stateView(_ key: String.LocalizationValue, id: String) -> some View {
        VStack(spacing: 16) {
            Text(L(key)).multilineTextAlignment(.center)
            Button { Task { await model.load() } } label: { Text("playStoreDay.refresh", tableName: "PlayStoreDay") }
                .disabled(model.phase == .loading).accessibilityIdentifier("storeDayPage.refresh")
        }.padding().frame(maxWidth: .infinity).accessibilityElement(children: .contain).accessibilityIdentifier("storeDayPage.state." + id)
    }

    // MARK: Page
    private func content(_ node: PlayStoreDayNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero(node)
                header(node)
                proofSection(node)
                referenceSection(node)
                if let notice = model.notice {
                    Text(verbatim: noticeText(notice)).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("storeDayPage.feedback")
                }
                if model.consent == .agree { consentSection }
                if let address = node.address { infoSection(node, address: address) }
            }.padding()
        }
        .safeAreaInset(edge: .bottom) { bottomBar(node) }
    }
    @ViewBuilder private func hero(_ node: PlayStoreDayNode) -> some View {
        let url = node.heroImage.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" && approvedImageHosts.contains($0.host?.lowercased() ?? "") ? $0 : nil }
        ZStack {
            Color.secondary.opacity(0.12)
            if let url {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "mappin.circle").font(.largeTitle) }
            } else { Image(systemName: "mappin.circle").font(.system(size: 44)).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
    }
    private func header(_ node: PlayStoreDayNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(tagKey(PlayStoreDayHeaderTag(node)))).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15), in: Capsule()).accessibilityIdentifier("storeDayPage.tag")
            Group {
                if let name = node.name { Text(verbatim: name) } else { Text("playStoreDay.name.untitled", tableName: "PlayStoreDay") }
            }.font(.title2.bold()).accessibilityIdentifier("storeDayPage.name")
            if let open = openText {
                LabeledContent { Text(verbatim: open) } label: { Text("playStoreDay.meta.open", tableName: "PlayStoreDay") }.accessibilityIdentifier("storeDayPage.meta.open")
            }
            LabeledContent { Text(L(crowdKey(PlayStoreDayCrowd(node)))) } label: { Text("playStoreDay.meta.onsite", tableName: "PlayStoreDay") }
                .accessibilityIdentifier("storeDayPage.meta.onsite")
        }
    }
    private var openText: String? {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        switch model.openText(nowMinutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0)) {
        case .server(let text): return text
        case .open: return L("playStoreDay.open.open")
        case .closed: return L("playStoreDay.open.closed")
        case nil: return nil
        }
    }
    private func proofSection(_ node: PlayStoreDayNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("playStoreDay.section.proof", tableName: "PlayStoreDay").font(.headline)
            step(1, done: node.arrived, title: L("playStoreDay.step.scan.title"), detail: L("playStoreDay.step.scan.detail"), id: "scan")
            step(2, done: node.selfReported, title: L("playStoreDay.step.photo.title"),
                 detail: node.arrived ? (node.photoDescription ?? L("playStoreDay.step.photo.default")) : L("playStoreDay.step.photo.locked"), id: "photo")
            step(3, done: node.done, title: L("playStoreDay.step.verify.title"), detail: L("playStoreDay.step.verify.detail"), id: "verify")
            if node.arrived, let rule = node.rule { Text(verbatim: rule).font(.footnote).accessibilityIdentifier("storeDayPage.rule") }
        }
    }
    private func step(_ index: Int, done: Bool, title: String, detail: String, id: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(index).circle").foregroundStyle(done ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) { Text(verbatim: title).font(.subheadline.bold()); Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier("storeDayPage.step." + id)
        .accessibilityValue(done ? Text("playStoreDay.step.done", tableName: "PlayStoreDay") : Text(verbatim: ""))
    }
    private func referenceSection(_ node: PlayStoreDayNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("playStoreDay.section.reference", tableName: "PlayStoreDay").font(.headline)
            HStack {
                stat(node.inStoreLoad.map(String.init) ?? "0", L("playStoreDay.stat.load"), id: "load")
                stat(node.servicePerHour.map(Self.number) ?? "0", L("playStoreDay.stat.perHour"), id: "perHour")
                stat(node.expectedWaitMinutes.map(String.init) ?? "0", L("playStoreDay.stat.wait"), id: "wait")
            }
        }
    }
    private static func number(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
    private func stat(_ value: String, _ label: String, id: String) -> some View {
        VStack(spacing: 4) { Text(verbatim: value).font(.title3.bold().monospacedDigit()); Text(verbatim: label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity).accessibilityElement(children: .combine).accessibilityIdentifier("storeDayPage.stat." + id)
    }
    private var consentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("playStoreDay.section.consent", tableName: "PlayStoreDay").font(.headline)
            Text(verbatim: String(format: L("playStoreDay.consent.scope"), storeName)).font(.footnote)
            Button { confirmRevoke = true } label: {
                Text(L(model.consentBusy ? "playStoreDay.consent.revoking" : "playStoreDay.consent.revoke"))
            }.disabled(model.consentBusy).accessibilityIdentifier("storeDayPage.consent.revoke")
        }
    }
    private func infoSection(_ node: PlayStoreDayNode, address: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("playStoreDay.section.info", tableName: "PlayStoreDay").font(.headline)
            Label { VStack(alignment: .leading) { Text(verbatim: address); if let open = openText { Text(verbatim: open).font(.caption) } } } icon: { Image(systemName: "mappin") }
            mapControl(node, label: L("playStoreDay.info.navigate"), id: "storeDayPage.info.navigate")
        }
    }
    /// Coordinates come only from the server row; the existing external-map host is reused.
    @ViewBuilder private func mapControl(_ node: PlayStoreDayNode, label: String, id: String) -> some View {
        if node.hasCoordinates, makeExternalMaps != nil {
            PlatformExternalMapHost(destination: .init(name: node.name ?? "", address: node.address, latitude: node.latitude, longitude: node.longitude),
                                    scope: mediaScope, makeModel: makeExternalMaps).accessibilityIdentifier(id)
        } else {
            Button { model.mapUnavailable() } label: { Label(label, systemImage: "mappin") }.accessibilityIdentifier(id)
        }
    }

    // MARK: Bottom bar
    private func bottomBar(_ node: PlayStoreDayNode) -> some View {
        VStack(spacing: 8) {
            if let degraded = model.degraded {
                Button { Task { await model.retryProofReadback() } } label: {
                    HStack(spacing: 8) { Circle().fill(model.receipt == .unknown ? Color.orange : Color.secondary).frame(width: 8, height: 8); Text(verbatim: degradedText(degraded)).font(.footnote) }
                }.buttonStyle(.plain).disabled(model.receipt != .unknown).accessibilityIdentifier("storeDayPage.degraded")
            }
            HStack(spacing: 12) {
                mapControl(node, label: L("playStoreDay.cta.address"), id: "storeDayPage.cta.address").fixedSize()
                primaryButton(node).frame(maxWidth: .infinity)
            }
        }
        .padding().background(.bar)
    }
    @ViewBuilder private func primaryButton(_ node: PlayStoreDayNode) -> some View {
        switch PlayStoreDayPrimaryAction.resolve(node, receipt: model.receipt) {
        case .confirmPending: primary(L("playStoreDay.cta.confirmPending"), disabled: false) { Task { await model.retryProofReadback() } }
        case .scan: primary(L(model.busy ? "playStoreDay.cta.scanBusy" : "playStoreDay.cta.scan"), disabled: model.busy) { model.prepareScan() }
        case .photo: primary(L(model.busy ? "playStoreDay.cta.photoBusy" : "playStoreDay.cta.photo"), disabled: model.busy) { model.preparePhoto() }
        case .verify: primary(L(model.consentBusy ? "playStoreDay.cta.verifyBusy" : "playStoreDay.cta.verify"), disabled: model.consentBusy) { model.openVerifyCode() }
        case .redeemed: primary(L("playStoreDay.cta.redeemed"), disabled: true) {}
        }
    }
    private func primary(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(verbatim: title).bold().frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(disabled).accessibilityIdentifier("storeDayPage.cta.primary")
    }

    // MARK: Sheets
    private var gameSheet: some View {
        NavigationStack {
            Form {
                if let node = model.node {
                    Section {
                        if let question = node.question { Text(verbatim: question).accessibilityIdentifier("storeDayPage.game.question") }
                    } header: {
                        if let title = node.gameTitle { Text(verbatim: title) } else { Text("playStoreDay.game.defaultTitle", tableName: "PlayStoreDay") }
                    }
                    if let result = model.game.result {
                        Section {
                            Text(verbatim: resultText(result)).accessibilityIdentifier("storeDayPage.game.result")
                            Button { model.closeGame() } label: { Text(L(node.selfReported ? "playStoreDay.game.finish" : "playStoreDay.game.next")) }
                                .accessibilityIdentifier("storeDayPage.game.close")
                        }
                    } else {
                        Section {
                            if let options = node.options {
                                ForEach(options) { option in
                                    Button { model.pick(option.key) } label: {
                                        HStack { Text(verbatim: option.key).bold(); Text(verbatim: option.text); Spacer(); if model.game.choice == option.key { Image(systemName: "checkmark") } }
                                    }
                                    .accessibilityLabel(Text(verbatim: String(format: L("playStoreDay.game.option"), option.key) + " " + option.text))
                                    .accessibilityAddTraits(model.game.choice == option.key ? .isSelected : [])
                                    .accessibilityIdentifier("storeDayPage.game.option." + option.key)
                                }
                            } else {
                                TextField(text: Binding(get: { model.game.answer }, set: { model.setAnswer($0) })) { Text("playStoreDay.game.placeholder", tableName: "PlayStoreDay") }
                                    .accessibilityLabel(Text("playStoreDay.game.answerLabel", tableName: "PlayStoreDay")).accessibilityIdentifier("storeDayPage.game.answer")
                            }
                            if let error = model.game.error {
                                Button { Task { await model.retryGameReadback() } } label: {
                                    Text(verbatim: gameErrorText(error) + (model.game.receipt == .unknown ? " · " + L("playStoreDay.game.recheck") : ""))
                                }.disabled(model.game.receipt != .unknown).accessibilityIdentifier("storeDayPage.game.error")
                            }
                            let locked = model.game.submitting || model.game.receipt == .unknown
                            Button { Task { await model.submitGame() } } label: {
                                Text(L(model.game.receipt == .unknown ? "playStoreDay.game.pending" : model.game.submitting ? "playStoreDay.game.submitting" : "playStoreDay.game.submit")).bold()
                            }.disabled(locked).accessibilityIdentifier("storeDayPage.game.submit")
                        }
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { model.closeSheets() } label: { Text("playStoreDay.mask.close", tableName: "PlayStoreDay") } } }
        }
    }
    private var taskSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: model.node?.photoDescription ?? L("playStoreDay.step.photo.default")).accessibilityIdentifier("storeDayPage.task.requirement")
                    if let rule = model.node?.rule { Text(verbatim: rule).font(.footnote) }
                } header: { Text("playStoreDay.task.title", tableName: "PlayStoreDay") }
                Section {
                    Button { model.taskGoPhoto() } label: { Text(L(model.busy ? "playStoreDay.task.busy" : "playStoreDay.task.photo")).bold() }
                        .disabled(model.busy).accessibilityIdentifier("storeDayPage.task.photo")
                    Button { model.closeTaskCard() } label: { Text("playStoreDay.task.later", tableName: "PlayStoreDay") }.accessibilityIdentifier("storeDayPage.task.later")
                }
            }
        }
    }

    // MARK: Copy
    private func tagKey(_ tag: PlayStoreDayHeaderTag) -> String.LocalizationValue {
        switch tag { case .redeemed: return "playStoreDay.tag.redeemed"; case .photoRecorded: return "playStoreDay.tag.photoRecorded"
        case .arrived: return "playStoreDay.tag.arrived"; case .pending: return "playStoreDay.tag.pending" }
    }
    private func crowdKey(_ crowd: PlayStoreDayCrowd) -> String.LocalizationValue {
        switch crowd { case .queue: return "playStoreDay.crowd.queue"; case .go: return "playStoreDay.crowd.go"; case .unknown: return "playStoreDay.crowd.unknown" }
    }
    private func degradedText(_ value: PlayStoreDayDegraded) -> String {
        switch value { case .quantityUnavailable: return L("playStoreDay.degraded.quantity")
        case .checking: return L("playStoreDay.degraded.checking"); case .stillUnknown: return L("playStoreDay.degraded.still") }
    }
    private func gameErrorText(_ error: PlayStoreDayGameError) -> String {
        switch error {
        case .chooseOption: return L("playStoreDay.game.error.choose")
        case .writeAnswer: return L("playStoreDay.game.error.write")
        case .wrong(let message): return message ?? L("playStoreDay.game.error.wrong")
        case .checking: return L("playStoreDay.game.error.checking")
        case .stillUnknown: return L("playStoreDay.game.error.still")
        case .notRecorded: return L("playStoreDay.game.error.notRecorded")
        }
    }
    private func resultText(_ result: PlayStoreDayAnswerResult) -> String {
        if result.confirmedByReadback { return L("playStoreDay.game.result.recorded") }
        let base = result.message ?? L(result.firstTime ? "playStoreDay.game.result.correct" : "playStoreDay.game.result.completed")
        return base + (result.experience.map { "  " + String(format: L("playStoreDay.game.result.xp"), $0) } ?? "")
    }
    private func noticeText(_ notice: PlayStoreDayNotice) -> String {
        switch notice {
        case .server(let text): return text
        case .arrivalRecorded: return L("playStoreDay.notice.arrivalRecorded")
        case .photoRecorded: return L("playStoreDay.notice.photoRecorded")
        case .proofFailed: return L("playStoreDay.notice.proofFailed")
        case .proofLanded: return L("playStoreDay.notice.proofLanded")
        case .proofNotLanded: return L("playStoreDay.notice.proofNotLanded")
        case .arriveFirst: return L("playStoreDay.notice.arriveFirst")
        case .preferenceUnreachable: return L("playStoreDay.notice.preferenceUnreachable")
        case .handoffFailed: return L("playStoreDay.notice.handoffFailed")
        case .noCoordinates: return L("playStoreDay.notice.noCoordinates")
        case .noCode: return L("playStoreDay.notice.noCode")
        case .noPhoto: return L("playStoreDay.notice.noPhoto")
        case .deviceUnavailable: return L("playStoreDay.notice.deviceUnavailable")
        case .writesUnavailable: return L("playStoreDay.notice.writesUnavailable")
        case .needTicket: return L("playStoreDay.notice.needTicket")
        case .merchantUnconfirmed: return L("playStoreDay.notice.merchantUnconfirmed")
        case .verifyOpenFailed: return L("playStoreDay.notice.verifyOpenFailed")
        case .consentRevoked: return L("playStoreDay.notice.consentRevoked")
        case .consentDeclined: return L("playStoreDay.notice.consentDeclined")
        case .consentWriteFailed: return L("playStoreDay.notice.consentWriteFailed")
        case .consentUnconfirmed: return L("playStoreDay.notice.consentUnconfirmed")
        case .consentWritesUnavailable: return L("playStoreDay.notice.consentWritesUnavailable")
        }
    }
}
