import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Local qmod import. The author picks a package, reads a local inspection
/// report, and can cancel, replace, or recheck. Nothing is uploaded.
@MainActor
final class QmodAuthorImportModel: ObservableObject {
    @Published private(set) var session = QmodArchiveInspectionSession()
    let limits: QmodLimitProfile
    let expansionGuard: QmodExpansionGuard
    /// Process read ceiling. Not `limits` and not a business rule.
    let readBudget: QmodLocalReadBudget
    private let work = QmodImportWork()
    /// False only after the real screen leaves. Presenting the system picker does not clear it.
    private var hostActive = true
    /// Lease for the picker that is allowed to call back. Cleared on cancel, leave, or a consumed success.
    private var pickerToken: UUID?

    init(limits: QmodLimitProfile = .reviewProposalV1, expansionGuard: QmodExpansionGuard = .localProcessStop, readBudget: QmodLocalReadBudget = .localProcessStop) {
        self.limits = limits
        self.expansionGuard = expansionGuard
        self.readBudget = readBudget
    }

    func importFile(at url: URL, presentation: UUID?) {
        guard let presentation, hostActive, presentation == pickerToken else { return }
        pickerToken = nil
        let generation = begin(url.lastPathComponent)
        let limits = self.limits
        let expansionGuard = self.expansionGuard
        let readBudget = self.readBudget
        let label = url.lastPathComponent
        work.start(Task.detached(priority: .utility) { [weak self] in
            let opened = QmodSecurityScopedPackage.open(url: url, budget: readBudget)
            if Task.isCancelled { return }
            let outcome = QmodAuthorImportCheck.inspect(opened: opened, generation: generation, label: label, limits: limits, expansionGuard: expansionGuard, readBudget: readBudget)
            if Task.isCancelled || outcome.report.issues.contains(where: { if case .checkCancelled = $0.code { return true }; return false }) { return }
            await self?.accept(generation: generation, report: outcome.report, retain: outcome.retain, limits: limits, expansionGuard: expansionGuard)
        })
    }

    func recheck() {
        guard let package = session.packageForRecheck() else { return }
        let generation = begin(package.label)
        let limits = package.limits
        let expansionGuard = package.expansionGuard
        let readBudget = self.readBudget
        let bytes = package.bytes
        let label = package.label
        work.start(Task.detached(priority: .utility) { [weak self] in
            if Task.isCancelled { return }
            let report = QmodArchiveInspection.inspect(package: bytes, limits: limits, expansionGuard: expansionGuard, generation: generation, packageLabel: label, readBudget: readBudget)
            if Task.isCancelled || report.issues.contains(where: { if case .checkCancelled = $0.code { return true }; return false }) { return }
            let retain = readBudget.isUsable && Int64(bytes.count) <= readBudget.maxBytes ? bytes : nil
            await self?.accept(generation: generation, report: report, retain: retain, limits: limits, expansionGuard: expansionGuard)
        })
    }

    func cancel() {
        pickerToken = nil
        work.cancel()
        var next = session
        next.cancel()
        session = next
    }

    /// Picker opened. The previous task is cancelled and its generation can no longer accept a result.
    func beginPicking() -> UUID {
        work.cancel()
        var next = session
        next.invalidateSelection()
        session = next
        let token = UUID()
        pickerToken = token
        return token
    }

    func pickerCancelled(presentation: UUID?) {
        guard let presentation, hostActive, presentation == pickerToken else { return }
        guard session.phase == .choosing else { return }
        cancel()
    }

    func hostLeft() {
        hostActive = false
        pickerToken = nil
        guard session.phase != .idle else { return }
        cancel()
    }

    private func begin(_ label: String) -> UInt64 {
        work.cancel()
        var next = session
        let generation = next.beginSelection(label: label)
        session = next
        return generation
    }

    private func accept(generation: UInt64, report: QmodLocalInspectionReport, retain: Data?, limits: QmodLimitProfile, expansionGuard: QmodExpansionGuard) {
        var next = session
        guard next.complete(generation: generation, report: report) else { return }
        if let retain { next.noteRetainedPackage(retain, limits: limits, expansionGuard: expansionGuard) }
        session = next
    }
}

private final class QmodImportWork {
    private var task: Task<Void, Never>?
    func cancel() { task?.cancel(); task = nil }
    func start(_ task: Task<Void, Never>) { cancel(); self.task = task }
    deinit { task?.cancel() }
}

private enum QmodAuthorImportCheck {
    static func inspect(opened: QmodOpenedPackage, generation: UInt64, label: String, limits: QmodLimitProfile, expansionGuard: QmodExpansionGuard, readBudget: QmodLocalReadBudget) -> (report: QmodLocalInspectionReport, retain: Data?) {
        let safe = QmodArchiveLabels.sanitize(label)
        func failed(_ code: QmodArchiveIssueCode) -> (report: QmodLocalInspectionReport, retain: Data?) {
            (QmodLocalInspectionReport(generation: generation, packageLabel: safe, issues: [QmodArchiveIssue(code: code, entryIndex: nil, headerOffset: nil, path: safe)], fileSummaries: [], manifestPackageId: nil, limits: limits, expansionGuard: expansionGuard, readBudget: readBudget), nil)
        }
        switch opened {
        case .bytes(let data):
            let report = QmodArchiveInspection.inspect(package: data, limits: limits, expansionGuard: expansionGuard, generation: generation, packageLabel: safe, readBudget: readBudget)
            let retain = readBudget.isUsable && Int64(data.count) <= readBudget.maxBytes ? data : nil
            return (report, retain)
        case .symlink:
            return failed(.symlink(safe))
        case .notRegularFile:
            return failed(.notARegularFile(safe))
        case .readBudgetExceeded(let actual, let limit):
            return failed(.readBudgetExceeded(actual: actual, limit: limit))
        case .readBudgetPosedAsRule:
            return failed(.readBudgetPosedAsRule)
        case .readBudgetUnsafe:
            return failed(.readBudgetUnsafe)
        case .unreadable:
            return failed(.localFileUnreadable(safe))
        case .cancelled:
            return failed(.checkCancelled)
        }
    }
}

/// One system picker. `token` stays the value passed at init; the callback captures this object.
final class QmodFileImporterBinding {
    let token: UUID
    init(token: UUID) { self.token = token }
}

private struct QmodFileImporterAdapter: View {
    let binding: QmodFileImporterBinding
    let types: [UTType]
    let model: QmodAuthorImportModel
    @State private var presented = false

    var body: some View {
        let binding = binding
        let model = model
        Color.clear
            .frame(width: 0, height: 0)
            .fileImporter(isPresented: $presented, allowedContentTypes: types) { [binding, model] result in
                switch result {
                case .success(let url): model.importFile(at: url, presentation: binding.token)
                case .failure: model.pickerCancelled(presentation: binding.token)
                }
            }
            .onAppear { presented = true }
    }
}

private struct QmodAuthorImportHostLifetime: UIViewControllerRepresentable {
    var onRealLeave: () -> Void
    func makeUIViewController(context: Context) -> QmodAuthorImportHostProbe {
        let probe = QmodAuthorImportHostProbe()
        probe.onRealLeave = onRealLeave
        return probe
    }
    func updateUIViewController(_ probe: QmodAuthorImportHostProbe, context: Context) {
        probe.onRealLeave = onRealLeave
    }
}

private final class QmodAuthorImportHostProbe: UIViewController {
    var onRealLeave: () -> Void = {}
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard Self.realHostRemoval(self) else { return }
        onRealLeave()
    }
    /// A system file picker covers this screen without removing it from its parent.
    static func realHostRemoval(_ controller: UIViewController) -> Bool {
        var cursor: UIViewController? = controller
        while let current = cursor {
            if current.isMovingFromParent || current.isBeingDismissed { return true }
            cursor = current.parent
        }
        return false
    }
}

@MainActor
struct QmodAuthorImportView: View {
    @StateObject private var model: QmodAuthorImportModel
    @State private var activePicker: QmodFileImporterBinding?

    init(limits: QmodLimitProfile = .reviewProposalV1, expansionGuard: QmodExpansionGuard = .localProcessStop, readBudget: QmodLocalReadBudget = .localProcessStop) {
        _model = StateObject(wrappedValue: QmodAuthorImportModel(limits: limits, expansionGuard: expansionGuard, readBudget: readBudget))
    }

    var body: some View {
        List {
            Section {
                Text("qmodImport.intro")
                    .accessibilityIdentifier("qmod.authorImport.serverStatus")
            }
            Section {
                Button(action: { activePicker = QmodFileImporterBinding(token: model.beginPicking()) }) { Label("qmodImport.pick", systemImage: "doc.badge.plus") }
                    .accessibilityIdentifier("qmod.authorImport.pick")
                Button(action: { activePicker = QmodFileImporterBinding(token: model.beginPicking()) }) { Text("qmodImport.replace") }
                    .disabled(model.session.phase == .idle)
                    .accessibilityIdentifier("qmod.authorImport.replace")
                Button(action: { model.recheck() }) { Text("qmodImport.recheck") }
                    .disabled(!model.session.canRecheck)
                    .accessibilityIdentifier("qmod.authorImport.recheck")
                Button(action: { model.cancel() }) { Text("qmodImport.cancel") }
                    .disabled(model.session.phase == .idle || model.session.phase == .cancelled)
                    .accessibilityIdentifier("qmod.authorImport.cancel")
            }
            if model.session.phase == .choosing {
                Section {
                    Text("qmodImport.choosing")
                        .accessibilityIdentifier("qmod.authorImport.choosing")
                }
            }
            if model.session.phase == .inspecting {
                Section {
                    Text("qmodImport.inspecting")
                        .accessibilityIdentifier("qmod.authorImport.inspecting")
                }
            }
            if model.session.phase == .cancelled {
                Section {
                    Text("qmodImport.cancelled")
                        .accessibilityIdentifier("qmod.authorImport.cancelled")
                }
            }
            if let report = model.session.report {
                reportSections(report)
            }
        }
        .navigationTitle(Text("qmodImport.title"))
        .accessibilityIdentifier("qmod.authorImport.root")
        .privacySensitive()
        .background {
            if let activePicker {
                QmodFileImporterAdapter(binding: activePicker, types: packageTypes, model: model)
                    .id(activePicker.token)
            }
        }
        .background(QmodAuthorImportHostLifetime(onRealLeave: { model.hostLeft() }))
    }

    private var packageTypes: [UTType] {
        [UTType(filenameExtension: "zip") ?? .data, .data]
    }

    @ViewBuilder
    private func reportSections(_ report: QmodLocalInspectionReport) -> some View {
        Section(header: Text("qmodImport.report")) {
            Text(verbatim: report.outcomeText)
                .accessibilityIdentifier("qmod.authorImport.outcome")
            LabeledContent("qmodImport.file", value: report.packageLabel)
                .accessibilityIdentifier("qmod.authorImport.generation")
            if let packageId = report.manifestPackageId {
                LabeledContent("qmodImport.packageName", value: packageId)
            }
        }
        .accessibilityIdentifier("qmod.authorImport.report")
        if !report.issues.isEmpty {
            Section(header: Text("qmodImport.problems")) {
                ForEach(Array(report.issues.enumerated()), id: \.offset) { index, issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: qmodArchiveIssueTitle(issue))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                        Text(verbatim: qmodArchiveIssueDetail(issue))
                            .font(.footnote)
                        Text(verbatim: qmodArchiveIssueLocation(issue))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("qmod.authorImport.issue.\(index)")
                }
            }
        }
        if !report.fileSummaries.isEmpty {
            Section(header: Text("qmodImport.files")) {
                ForEach(report.fileSummaries, id: \.path) { file in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: file.path).font(.subheadline.monospaced())
                        Text(file.matchesManifest ? "qmodImport.fileMatches \(file.bytes)" : "qmodImport.fileMismatch \(file.bytes)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("qmod.authorImport.file.\(file.path)")
                }
            }
        }
    }

}

private func qmodArchiveIssueLocation(_ issue: QmodArchiveIssue) -> String {
    var parts: [String] = []
    if let index = issue.entryIndex { parts.append(String(localized: "qmodImport.entry \(index)")) }
    if let path = issue.path { parts.append(path) }
    return parts.isEmpty ? String(localized: "qmodImport.archive") : parts.joined(separator: " · ")
}

private func qmodArchiveIssueTitle(_ issue: QmodArchiveIssue) -> String {
    switch issue.code {
    case .pathTraversal: return String(localized: "qmodImport.issue.pathTraversal")
    case .duplicatePath: return String(localized: "qmodImport.issue.duplicatePath")
    case .abnormalCompression: return String(localized: "qmodImport.issue.abnormalCompression")
    case .symlink: return String(localized: "qmodImport.issue.symlink")
    case .notARegularFile: return String(localized: "qmodImport.issue.notARegularFile")
    case .unsafeEntry: return String(localized: "qmodImport.issue.unsafeEntry")
    case .corrupt: return String(localized: "qmodImport.issue.corrupt")
    case .digestMismatch: return String(localized: "qmodImport.issue.digestMismatch")
    case .manifest(let manifestIssue): return QmodManifestIssueNotice(issue: manifestIssue).titleText
    case .proposalPresentedAsBusinessRule: return String(localized: "qmodImport.issue.proposalPresentedAsBusinessRule")
    case .limitProfileNotApproved: return String(localized: "qmodImport.issue.limitProfileNotApproved")
    case .archiveTooLarge: return String(localized: "qmodImport.issue.archiveTooLarge")
    case .fileTooLarge: return String(localized: "qmodImport.issue.fileTooLarge")
    case .expandedTooLarge: return String(localized: "qmodImport.issue.expandedTooLarge")
    case .tooManyEntries: return String(localized: "qmodImport.issue.tooManyEntries")
    case .unexpectedEntry: return String(localized: "qmodImport.issue.unexpectedEntry")
    case .missingEntry: return String(localized: "qmodImport.issue.missingEntry")
    case .unsupportedMethod: return String(localized: "qmodImport.issue.unsupportedMethod")
    case .unsupportedZip64: return String(localized: "qmodImport.issue.unsupportedZip64")
    case .encrypted: return String(localized: "qmodImport.issue.encrypted")
    case .localFileUnreadable: return String(localized: "qmodImport.issue.localFileUnreadable")
    case .readBudgetPosedAsRule: return String(localized: "qmodImport.issue.readBudgetPosedAsRule")
    case .readBudgetUnsafe: return String(localized: "qmodImport.issue.readBudgetUnsafe")
    case .readBudgetExceeded: return String(localized: "qmodImport.issue.readBudgetExceeded")
    case .checkCancelled: return String(localized: "qmodImport.issue.checkCancelled")
    }
}

private func qmodArchiveIssueDetail(_ issue: QmodArchiveIssue) -> String {
    switch issue.code {
    case .pathTraversal(let path): return String(localized: "qmodImport.detail.pathTraversal \(path)")
    case .duplicatePath(let path): return String(localized: "qmodImport.detail.duplicatePath \(path)")
    case .abnormalCompression: return String(localized: "qmodImport.detail.abnormalCompression")
    case .symlink(let path): return String(localized: "qmodImport.detail.symlink \(path)")
    case .notARegularFile(let path): return String(localized: "qmodImport.detail.notARegularFile \(path)")
    case .unsafeEntry(let path): return String(localized: "qmodImport.detail.unsafeEntry \(path)")
    case .corrupt: return String(localized: "qmodImport.detail.corrupt")
    case .digestMismatch(let path, _, _, _, _): return String(localized: "qmodImport.detail.digestMismatch \(path)")
    case .manifest(let manifestIssue): return QmodManifestIssueNotice(issue: manifestIssue).bodyText
    case .proposalPresentedAsBusinessRule, .limitProfileNotApproved, .readBudgetPosedAsRule, .readBudgetUnsafe:
        return String(localized: "qmodImport.detail.settings")
    case .archiveTooLarge(let actual, let limit): return String(localized: "qmodImport.detail.tooLarge \(actual) \(limit)")
    case .fileTooLarge(_, let actual, let limit): return String(localized: "qmodImport.detail.tooLarge \(actual) \(limit)")
    case .expandedTooLarge(_, let actual, let limit): return String(localized: "qmodImport.detail.tooLarge \(actual) \(limit)")
    case .tooManyEntries(let actual, let limit): return String(localized: "qmodImport.detail.tooManyEntries \(actual) \(limit)")
    case .unexpectedEntry(let path): return String(localized: "qmodImport.detail.unexpectedEntry \(path)")
    case .missingEntry(let path): return String(localized: "qmodImport.detail.missingEntry \(path)")
    case .unsupportedMethod: return String(localized: "qmodImport.detail.unsupportedMethod")
    case .unsupportedZip64: return String(localized: "qmodImport.detail.unsupportedZip64")
    case .encrypted(let path): return String(localized: "qmodImport.detail.encrypted \(path)")
    case .localFileUnreadable(let path): return String(localized: "qmodImport.detail.localFileUnreadable \(path)")
    case .readBudgetExceeded: return String(localized: "qmodImport.detail.readBudgetExceeded")
    case .checkCancelled: return String(localized: "qmodImport.detail.checkCancelled")
    }
}
