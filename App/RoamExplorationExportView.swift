import SwiftUI
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

/// Complete JSONL handed to the system share sheet; the temporary copy is removed when the page goes away.
struct RoamExportShareItem: Transferable {
    let file: RoamExportFile
    let lease: RoamExportDeliveryLease?
    static func temporaryURL(_ name: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(name) }
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .roamJSONL) { item in
            // Revalidated at the actual hand-off, not at render: an expired or revoked
            // lease (backgrounded, page gone, identity moved on) delivers nothing.
            guard let lease = item.lease,
                  lease.validatedFile(item.file, now: Date(), currentIdentity: lease.identity, foreground: true) != nil else {
                throw CancellationError()
            }
            let url = temporaryURL(item.file.fileName)
            try Data(item.file.content.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            return SentTransferredFile(url)
        }
    }
}

struct RoamExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.roamJSONL] }
    let content: String
    init(content: String) { self.content = content }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(content.utf8)) }
}

@MainActor private struct RoamExportContent: View {
    let tools: any RoamPrivateToolsServing
    @State private var model: RoamExportCoordinator
    @State private var preset: RoamExportRangePreset.Kind = .last30Days
    @State private var startDate = ""
    @State private var endDate = ""
    @State private var saving = false
    @State private var saveResult: LocalizedStringKey?
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
        .onDisappear { model.revokeDelivery(); removeTemporaryFile(); model.restart() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Return is not a revival: the coordinator revalidates identity and
                // expiry before any fresh delivery lease exists.
                model.renewDelivery()
            } else {
                model.revokeDelivery(); removeTemporaryFile(); saving = false
            }
        }
        .fileExporter(isPresented: $saving, document: model.fileForDelivery(foreground: scenePhase == .active).map { RoamExportDocument(content: $0.content) },
                      contentType: .roamJSONL, defaultFilename: model.fileForDelivery(foreground: scenePhase == .active)?.fileName) { result in
            switch result {
            case .success: saveResult = "roam.export.saved"
            case .failure(let error): saveResult = (error as? CocoaError)?.code == .userCancelled ? "roam.export.cancelled" : "roam.export.saveFailed"
            }
        }
        .accessibilityIdentifier("roam.export.screen")
    }
    private func use(_ kind: RoamExportRangePreset.Kind) {
        guard let value = model.presets.first(where: { $0.kind == kind }) else { return }
        preset = kind; startDate = value.startDate; endDate = value.endDateExclusive
    }
    private func removeTemporaryFile() {
        if let name = model.file?.fileName { try? FileManager.default.removeItem(at: RoamExportShareItem.temporaryURL(name)) }
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
                ShareLink(item: RoamExportShareItem(file: file, lease: model.deliveryLease), preview: SharePreview(file.fileName)) { Text("roam.export.share") }
                    .accessibilityIdentifier("roam.export.share")
                Button("roam.export.save") {
                    saveResult = nil
                    // Revalidated at tap time; an expired or revoked file opens no exporter.
                    if model.fileForDelivery(foreground: scenePhase == .active) != nil { saving = true }
                    else if model.isFileExpired { model.discardExpired() }
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
            Button("roam.export.restart") { removeTemporaryFile(); saveResult = nil; model.restart() }
                .disabled(model.isBusy).accessibilityIdentifier("roam.export.restart")
        }
    }
}
