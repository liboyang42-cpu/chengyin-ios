import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Mini-program subpackageTools/exploration-export. Its own file, like RoamHistoryShareView: the only roam surface
/// that hands a complete, user-chosen file to the system share sheet or the Files exporter.
// MARK: 导出探索记录

@MainActor struct RoamExplorationExportView: View {
    let tools: (any RoamPrivateToolsServing)?
    var body: some View {
        Group {
            if let tools { RoamExportContent(tools: tools).id(tools.identity) }
            else { List { RoamPrivateIssueView(issue: .notConfigured) }.accessibilityIdentifier("roam.export.screen") }
        }.appNavigationTitle("roam.export.title")
    }
}

extension UTType {
    static var roamJSONL: UTType { UTType(filenameExtension: "jsonl", conformingTo: .text) ?? .plainText }
}

/// Complete JSONL handed to the system share sheet. The temporary copy is removed
/// when the share finishes, is cancelled, or the page goes away.
struct RoamExportShareItem: Transferable {
    let file: RoamExportFile
    let lease: RoamExportDeliveryLease
    let context: RoamExportDeliveryContext
    /// A unique folder per hand-off so two exports never share one temporary path.
    static func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("roam-export-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .roamJSONL) { item in
            guard let data = RoamExportHandoff.contents(file: item.file, lease: item.lease, context: item.context) else {
                throw CancellationError()
            }
            let url = temporaryURL(item.file.fileName)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            item.context.rememberTemporary(url)
            return SentTransferredFile(url)
        }
    }
}

struct RoamExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.roamJSONL] }
    let file: RoamExportFile
    let lease: RoamExportDeliveryLease
    let context: RoamExportDeliveryContext
    init(file: RoamExportFile, lease: RoamExportDeliveryLease, context: RoamExportDeliveryContext) {
        self.file = file; self.lease = lease; self.context = context
    }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = RoamExportHandoff.contents(file: file, lease: lease, context: context) else {
            throw CocoaError(.userCancelled)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

/// System share with a real completion. Cancel deletes the temp file and is not a save.
@MainActor private struct RoamExportActivityShare: UIViewControllerRepresentable {
    let file: RoamExportFile
    let lease: RoamExportDeliveryLease
    let token: UUID
    let context: RoamExportDeliveryContext
    let isCurrent: @MainActor () -> Bool
    let finish: @MainActor (Bool) -> Void
    func makeUIViewController(context controllerContext: Context) -> UIActivityViewController {
        let target = RoamExportShareItem.temporaryURL(file.fileName)
        var items: [URL] = []
        if isCurrent(), let data = RoamExportHandoff.contents(file: file, lease: lease, context: context) {
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? data.write(to: target, options: [.atomic, .completeFileProtection])) != nil {
                self.context.rememberTemporary(target, token: token)
                items = [target]
            }
        }
        let wrote = !items.isEmpty
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            let saved = wrote && RoamExportHandoff.recordsSave(completed: completed, errorIsSet: error != nil)
            Task { @MainActor in finish(saved) }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context controllerContext: Context) {
        if !isCurrent() { controller.dismiss(animated: false) }
    }
}

private struct RoamExportShareOffer: Identifiable {
    let id = UUID()
    let file: RoamExportFile
    let lease: RoamExportDeliveryLease
    let token: UUID
}

private struct RoamExportSaveTicket: Identifiable {
    let id = UUID()
    let file: RoamExportFile
    let lease: RoamExportDeliveryLease
}

/// One fileExporter per save. The callback closes over this ticket, not a queue of earlier taps.
private struct RoamExportFileSaveLink: View {
    let ticket: RoamExportSaveTicket
    let context: RoamExportDeliveryContext
    let finish: (UUID, RoamExportDeliveryLease, Result<URL, Error>) -> Void
    @State private var presented = true
    var body: some View {
        Color.clear.fileExporter(isPresented: $presented,
                                 document: RoamExportDocument(file: ticket.file, lease: ticket.lease, context: context),
                                 contentType: .roamJSONL, defaultFilename: ticket.file.fileName) { result in
            finish(ticket.id, ticket.lease, result)
        }
    }
}

@MainActor private struct RoamExportContent: View {
    let tools: any RoamPrivateToolsServing
    @State private var model: RoamExportCoordinator
    @State private var preset: RoamExportRangePreset.Kind = .last30Days
    @State private var startDate = ""
    @State private var endDate = ""
    @State private var saveResult: LocalizedStringKey?
    @State private var deliveryContext = RoamExportDeliveryContext()
    @State private var shareOffer: RoamExportShareOffer?
    /// The save currently presented. Its own view owns the callback; a later save does not inherit it.
    @State private var saveTicket: RoamExportSaveTicket?
    @Environment(\.scenePhase) private var scenePhase
    init(tools: any RoamPrivateToolsServing) {
        self.tools = tools
        // Offline the fixture echoes a two-row page size so chunked reading stays visible; live reads use 100.
        _model = State(initialValue: RoamExportCoordinator(tools: tools, pageSize: tools.isOfflineExample ? RoamPrivateToolsFixture.fixturePageSize : RoamExportContract.defaultPageSize))
    }
    private func presetKey(_ kind: RoamExportRangePreset.Kind) -> LocalizedStringKey {
        switch kind { case .last30Days: return "roam.export.range.30"; case .thisYear: return "roam.export.range.year"; case .lastYear: return "roam.export.range.365" }
    }
    private var prepared: Bool { model.checkpoint != nil }
    /// Readers stay live. A later account, permission, clock, or scene change is visible
    /// at the write without another call here.
    private func bindDeliveryFacts() {
        deliveryContext.bind(clock: { [tools] in tools.now },
                             identity: { [tools] in tools.isConfigured ? tools.identity : nil },
                             foreground: { UIApplication.shared.applicationState == .active })
    }
    var body: some View {
        List {
            if tools.isOfflineExample { Section { RoamExperienceNotice(offline: true) } }
            Section { Text("roam.export.explain").font(.footnote).foregroundStyle(.secondary) }
            if let issue = model.issue {
                Section { RoamPrivateIssueView(issue: issue, retry: { Task { if prepared { await model.readNext() } else { await model.prepare(startDate: startDate, endDateExclusive: endDate) } } }) }
            }
            if model.sourceChanged {
                Section { Text("roam.export.sourceChanged").accessibilityIdentifier("roam.export.sourceChanged") }
            }
            if let saveResult { Section { Text(saveResult).accessibilityIdentifier("roam.export.saveResult") } }
            if prepared { progress } else { chooser }
        }
        .task { if startDate.isEmpty { use(.last30Days) } }
        .onAppear { bindDeliveryFacts() }
        .onDisappear { model.revokeDelivery(); deliveryContext.cleanupTemporary(); model.restart() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Foreground return rechecks identity and expiry. It does not make a revoked file deliverable.
                model.renewDelivery()
            } else {
                model.revokeDelivery(); deliveryContext.cleanupTemporary(); saveTicket = nil; shareOffer = nil
            }
        }
        .background {
            if let ticket = saveTicket {
                RoamExportFileSaveLink(ticket: ticket, context: deliveryContext) { id, lease, result in
                    guard saveTicket?.id == id else { return }
                    guard RoamExportHandoff.callbackMatches(lease, current: model.deliveryLease) else { return }
                    saveTicket = nil
                    switch result {
                    case .success: saveResult = "roam.export.saved"
                    case .failure(let error):
                        let cancelled = (error as? CocoaError)?.code == .userCancelled
                        saveResult = cancelled ? "roam.export.cancelled" : "roam.export.saveFailed"
                        if cancelled { model.revokeDelivery() }
                    }
                }.id(ticket.id)
            }
        }
        .sheet(item: $shareOffer) { offer in
            RoamExportActivityShare(file: offer.file, lease: offer.lease, token: offer.token, context: deliveryContext,
                                    isCurrent: { model.deliveryLease === offer.lease && model.fileForDelivery(foreground: scenePhase == .active) != nil },
                                    finish: { saved in
                                        deliveryContext.releaseTemporary(token: offer.token)
                                        guard shareOffer?.id == offer.id else { return }
                                        if RoamExportHandoff.callbackMatches(offer.lease, current: model.deliveryLease) {
                                            if saved { saveResult = "roam.export.saved" }
                                            else { model.revokeDelivery() }
                                        }
                                        shareOffer = nil
                                    })
        }
        .accessibilityIdentifier("roam.export.screen")
    }
    private func use(_ kind: RoamExportRangePreset.Kind) {
        guard let value = model.presets.first(where: { $0.kind == kind }) else { return }
        preset = kind; startDate = value.startDate; endDate = value.endDateExclusive
    }
    @ViewBuilder private var chooser: some View {
        Section {
            Picker("roam.export.range", selection: Binding(get: { preset }, set: { use($0) })) {
                ForEach(RoamExportRangePreset.Kind.allCases, id: \.self) { Text(presetKey($0)).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("roam.export.rangePicker")
            DatePicker("roam.export.start", selection: Binding(get: { RoamShanghaiPicker.date(startDate) }, set: { startDate = RoamShanghaiPicker.text($0) }), displayedComponents: .date)
                .environment(\.timeZone, RoamShanghaiPicker.timeZone).accessibilityIdentifier("roam.export.startDate")
            DatePicker("roam.export.end", selection: Binding(get: { RoamShanghaiPicker.date(endDate) }, set: { endDate = RoamShanghaiPicker.text($0) }),
                       in: RoamShanghaiPicker.date(startDate)..., displayedComponents: .date)
                .environment(\.timeZone, RoamShanghaiPicker.timeZone).accessibilityIdentifier("roam.export.endDate")
            if !RoamExportContract.isValidRange(start: startDate, end: endDate) {
                Text("roam.export.rangeLimit").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("roam.export.rangeLimit")
            }
        }.disabled(model.isBusy)
        Section {
            Button("roam.export.prepare") { saveResult = nil; Task { await model.prepare(startDate: startDate, endDateExclusive: endDate) } }
                .disabled(model.isBusy || !RoamExportContract.isValidRange(start: startDate, end: endDate)).accessibilityIdentifier("roam.export.prepare")
            if model.phase == .preparing { ProgressView() }
        }
    }
    @ViewBuilder private var progress: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(model.percent)%").font(.largeTitle.bold()).monospacedDigit()
                Spacer()
                Text("roam.export.readCount \(model.read) \(model.expected)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }.accessibilityElement(children: .combine).accessibilityIdentifier("roam.export.progress")
            ProgressView(value: Double(model.percent), total: 100)
        }
        if model.phase == .complete && model.expected == 0 {
            Section { Text("roam.export.noRecords").accessibilityIdentifier("roam.export.noRecords") }
        }
        if let file = model.fileForDelivery(foreground: scenePhase == .active) {
            Section {
                LabeledContent { Text("roam.export.rows \(file.rows)") } label: {
                    Label { Text(verbatim: file.fileName) } icon: { Text(verbatim: "JSONL").font(.caption2.bold()) }
                }.accessibilityIdentifier("roam.export.file")
                Button("roam.export.share") {
                    if let lease = model.deliveryLease, model.fileForDelivery(foreground: scenePhase == .active) != nil {
                        shareOffer = RoamExportShareOffer(file: file, lease: lease, token: UUID())
                    } else if model.isFileExpired { model.discardExpired() }
                }.accessibilityIdentifier("roam.export.share")
                Button("roam.export.save") {
                    saveResult = nil
                    // The exporter asks for bytes later. That write reads the clock again.
                    if let lease = model.deliveryLease, model.fileForDelivery(foreground: scenePhase == .active) != nil {
                        saveTicket = RoamExportSaveTicket(file: file, lease: lease)
                    } else if model.isFileExpired { model.discardExpired() }
                }.accessibilityIdentifier("roam.export.save")
            }
        } else if model.phase == .complete && model.isFileExpired {
            Section { Button("roam.export.expired") { model.discardExpired() } }
        }
        Section {
            if model.phase == .reading {
                ProgressView("roam.export.reading").accessibilityIdentifier("roam.export.reading")
            } else if model.phase != .complete {
                Button(LocalizedStringKey(model.read > 0 ? "roam.export.readNext" : "roam.export.startReading")) { Task { await model.readNext() } }
                    .accessibilityIdentifier("roam.export.readNext")
            }
            Button("roam.export.restart") { deliveryContext.cleanupTemporary(); saveResult = nil; model.restart() }
                .disabled(model.isBusy).accessibilityIdentifier("roam.export.restart")
        }
    }
}
