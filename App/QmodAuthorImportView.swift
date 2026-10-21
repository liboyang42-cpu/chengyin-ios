import SwiftUI
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

    init(limits: QmodLimitProfile = .reviewProposalV1, expansionGuard: QmodExpansionGuard = .localProcessStop, readBudget: QmodLocalReadBudget = .localProcessStop) {
        self.limits = limits
        self.expansionGuard = expansionGuard
        self.readBudget = readBudget
    }

    func importFile(at url: URL) {
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
        work.cancel()
        var next = session
        next.cancel()
        session = next
    }

    /// Picker opened. The previous task is cancelled and its generation can no longer accept a result.
    func beginPicking() {
        work.cancel()
        var next = session
        next.invalidateSelection()
        session = next
    }

    func pickerCancelled() {
        guard session.phase == .choosing else { return }
        cancel()
    }

    func hostLeft() {
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

@MainActor
struct QmodAuthorImportView: View {
    @StateObject private var model: QmodAuthorImportModel
    @State private var picking = false

    init(limits: QmodLimitProfile = .reviewProposalV1, expansionGuard: QmodExpansionGuard = .localProcessStop, readBudget: QmodLocalReadBudget = .localProcessStop) {
        _model = StateObject(wrappedValue: QmodAuthorImportModel(limits: limits, expansionGuard: expansionGuard, readBudget: readBudget))
    }

    var body: some View {
        List {
            Section(header: Text(verbatim: "本机边界")) {
                Text(verbatim: QmodLocalInspectionReport.fixedServerDenialText)
                    .accessibilityIdentifier("qmod.authorImport.serverStatus")
                Text(verbatim: "体积与条数上限来自调用方给出的限制档 \(model.limits.profileVersion)，不是正式业务规则，也不是打开文件前的读入停止线。")
                Text(verbatim: "读入停止线 \(model.readBudget.maxBytes) 字节只属于本进程，不是限制档 \(model.limits.profileVersion)，也不是正式业务规则。")
                    .accessibilityIdentifier("qmod.authorImport.readBudget")
                Text(verbatim: "压缩倍数止损 \(model.expansionGuard.numerator):\(model.expansionGuard.denominator) 只是本进程安全停止，不是正式业务规则。")
                Text(verbatim: QmodLocalInspectionReport.fixedExecutionDenialText)
            }
            Section {
                Button(action: { model.beginPicking(); picking = true }) { Text(verbatim: "选择包") }
                    .accessibilityIdentifier("qmod.authorImport.pick")
                Button(action: { model.beginPicking(); picking = true }) { Text(verbatim: "换包") }
                    .disabled(model.session.phase == .idle)
                    .accessibilityIdentifier("qmod.authorImport.replace")
                Button(action: { model.recheck() }) { Text(verbatim: "复检") }
                    .disabled(!model.session.canRecheck)
                    .accessibilityIdentifier("qmod.authorImport.recheck")
                Button(action: { model.cancel() }) { Text(verbatim: "取消") }
                    .disabled(model.session.phase == .idle || model.session.phase == .cancelled)
                    .accessibilityIdentifier("qmod.authorImport.cancel")
            }
            if model.session.phase == .choosing {
                Section {
                    Text(verbatim: "正在选择新的包。上一份检查已停止，它的结果不会当成这次选择。")
                        .accessibilityIdentifier("qmod.authorImport.choosing")
                }
            }
            if model.session.phase == .inspecting {
                Section {
                    Text(verbatim: "正在检查。取消或换包会丢弃这一次的结果。")
                        .accessibilityIdentifier("qmod.authorImport.inspecting")
                }
            }
            if model.session.phase == .cancelled {
                Section {
                    Text(verbatim: "已取消。上一份报告已丢弃，不会再套用。")
                        .accessibilityIdentifier("qmod.authorImport.cancelled")
                }
            }
            if let report = model.session.report {
                reportSections(report)
            }
        }
        .navigationTitle(Text(verbatim: "本机 qmod 检查"))
        .accessibilityIdentifier("qmod.authorImport.root")
        .privacySensitive()
        .fileImporter(isPresented: $picking, allowedContentTypes: packageTypes) { result in
            switch result {
            case .success(let url): model.importFile(at: url)
            case .failure: model.pickerCancelled()
            }
        }
        .onDisappear {
            if !picking { model.hostLeft() }
        }
    }

    private var packageTypes: [UTType] {
        [UTType(filenameExtension: "zip") ?? .data, .data]
    }

    @ViewBuilder
    private func reportSections(_ report: QmodLocalInspectionReport) -> some View {
        Section(header: Text(verbatim: "本机报告")) {
            Text(verbatim: report.outcomeText)
                .accessibilityIdentifier("qmod.authorImport.outcome")
            Text(verbatim: report.serverDenialText)
            Text(verbatim: report.proposalDenialText)
            Text(verbatim: report.readBudgetDenialText)
            Text(verbatim: report.expansionDenialText)
            Text(verbatim: "检查序号 \(report.generation) · \(report.packageLabel)")
                .font(.footnote.monospaced())
                .accessibilityIdentifier("qmod.authorImport.generation")
            if let packageId = report.manifestPackageId {
                Text(verbatim: "清单包名 \(packageId)")
                    .font(.footnote.monospaced())
            }
        }
        .accessibilityIdentifier("qmod.authorImport.report")
        if !report.issues.isEmpty {
            Section(header: Text(verbatim: "错误定位")) {
                ForEach(Array(report.issues.enumerated()), id: \.offset) { index, issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: qmodArchiveIssueTitle(issue))
                            .font(.subheadline.weight(.semibold))
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
            Section(header: Text(verbatim: "逐文件摘要")) {
                ForEach(report.fileSummaries, id: \.path) { file in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: file.path).font(.subheadline.monospaced())
                        Text(verbatim: file.sha256).font(.caption.monospaced())
                        Text(verbatim: "\(file.bytes) 字节 · \(file.matchesManifest ? "与清单一致" : "未与清单核对通过")")
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
    if let index = issue.entryIndex { parts.append("条目 \(index)") }
    if let offset = issue.headerOffset { parts.append("偏移 \(offset)") }
    if let path = issue.path { parts.append(path) }
    return parts.isEmpty ? "归档" : parts.joined(separator: " · ")
}

private func qmodArchiveIssueTitle(_ issue: QmodArchiveIssue) -> String {
    switch issue.code {
    case .pathTraversal: return "路径穿越"
    case .duplicatePath: return "路径重复"
    case .abnormalCompression: return "异常压缩"
    case .symlink: return "符号链接"
    case .notARegularFile: return "不是普通文件"
    case .unsafeEntry: return "不允许的路径"
    case .corrupt: return "归档损坏"
    case .digestMismatch: return "摘要不一致"
    case .manifest(let manifestIssue): return QmodManifestIssueNotice(issue: manifestIssue).titleText
    case .proposalPresentedAsBusinessRule: return "限额被当成正式规则"
    case .limitProfileNotApproved: return "限制档未经审定"
    case .archiveTooLarge: return "包体积超过本机上限"
    case .fileTooLarge: return "单文件超过本机上限"
    case .expandedTooLarge: return "展开体积超过本机上限"
    case .tooManyEntries: return "条目过多"
    case .unexpectedEntry: return "清单之外的文件"
    case .missingEntry: return "缺少清单中的文件"
    case .unsupportedMethod: return "不支持的压缩方法"
    case .unsupportedZip64: return "不支持 ZIP64"
    case .encrypted: return "加密条目"
    case .localFileUnreadable: return "无法读取本地文件"
    case .readBudgetPosedAsRule: return "读入停止线被当成提案或正式规则"
    case .readBudgetUnsafe: return "读入停止线超过内存安全上限"
    case .readBudgetExceeded: return "超过本进程读入停止线"
    case .checkCancelled: return "检查已取消"
    }
}

private func qmodArchiveIssueDetail(_ issue: QmodArchiveIssue) -> String {
    switch issue.code {
    case .pathTraversal(let path): return "条目 \(path) 跳出了包内相对路径。文件没有被展开。"
    case .duplicatePath(let path): return "路径 \(path) 与另一条目在大小写折叠后重复。"
    case .abnormalCompression(_, let compressed, let uncompressed): return "声明的展开大小 \(uncompressed) 字节相对压缩大小 \(compressed) 字节超过本进程止损。没有继续展开。"
    case .symlink(let path): return "\(path) 是符号链接。链接没有被跟随，目标没有被当作包内文件。"
    case .notARegularFile(let path): return "\(path) 不是普通文件。"
    case .unsafeEntry(let path): return "\(path) 不在本版允许的相对路径内。"
    case .corrupt(let detail): return "归档结构无法核验（\(detail)）。"
    case .digestMismatch(let path, let actual, let declared, let actualBytes, let declaredBytes):
        return "\(path) 实际摘要 \(actual)（\(actualBytes) 字节），清单声明 \(declared)（\(declaredBytes) 字节）。"
    case .manifest(let manifestIssue): return QmodManifestIssueNotice(issue: manifestIssue).bodyText
    case .proposalPresentedAsBusinessRule: return "调用方把压缩止损标成了正式业务规则。检查已拒绝，没有读取包。"
    case .limitProfileNotApproved(let version): return "限制档 \(version) 没有 isProposal 标记。数字只作为本机上限，不能当成已审定业务规则，因此本报告不算通过。"
    case .archiveTooLarge(let actual, let limit): return "包大小 \(actual) 字节，本机上限 \(limit) 字节。这不是正式业务规则。"
    case .fileTooLarge(_, let actual, let limit): return "单文件 \(actual) 字节，本机上限 \(limit) 字节。这不是正式业务规则。"
    case .expandedTooLarge(_, let actual, let limit): return "展开后将达到 \(actual) 字节，本机上限 \(limit) 字节。这不是正式业务规则。"
    case .tooManyEntries(let actual, let limit): return "内容条目 \(actual) 个，本机上限 \(limit) 个（不含单独的 manifest.json）。这不是正式业务规则。"
    case .unexpectedEntry(let path): return "\(path) 不在 manifest.json 的文件列表中。"
    case .missingEntry(let path): return "清单要求的 \(path) 没有通过归档核验。"
    case .unsupportedMethod(_, let method): return "压缩方法 \(method) 不能在本机安全展开。"
    case .unsupportedZip64: return "ZIP64 不在本机检查范围内。"
    case .encrypted(let path): return "\(path) 带加密标记。本机不解密。"
    case .localFileUnreadable(let path): return "没有读到完整的普通文件 \(path)。"
    case .readBudgetPosedAsRule: return "读入停止线被标成了提案档或正式业务规则。文件没有打开。"
    case .readBudgetUnsafe: return "这个读入停止线不能安全地加一而不溢出。文件没有打开。这是本进程的技术上限，不是业务包限额。"
    case .readBudgetExceeded(_, let limit): return "打开的文件超过本进程读入停止线 \(limit) 字节。超出的字节没有读入。这不是提案档，也不是正式业务规则。"
    case .checkCancelled: return "这次检查已取消。结果不会被采用。"
    }
}
