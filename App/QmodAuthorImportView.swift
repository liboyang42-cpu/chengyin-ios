import SwiftUI
import UniformTypeIdentifiers

/// Local qmod import. The author picks a package, reads a local inspection
/// report, and can cancel, replace, or recheck. Nothing is uploaded.
@MainActor
final class QmodAuthorImportModel: ObservableObject {
    @Published private(set) var session = QmodArchiveInspectionSession()
    let limits: QmodLimitProfile
    let expansionGuard: QmodExpansionGuard

    init(limits: QmodLimitProfile = .reviewProposalV1, expansionGuard: QmodExpansionGuard = .localProcessStop) {
        self.limits = limits
        self.expansionGuard = expansionGuard
    }

    func importLocal(facts: QmodLocalFileFacts, bytes: Data?, label: String) {
        var next = session
        next.selectLocalFile(facts: facts, bytes: bytes, label: label, limits: limits, expansionGuard: expansionGuard)
        session = next
    }

    func recheck() {
        var next = session
        next.recheck()
        session = next
    }

    func cancel() {
        var next = session
        next.cancel()
        session = next
    }
}

@MainActor
struct QmodAuthorImportView: View {
    @StateObject private var model: QmodAuthorImportModel
    @State private var picking = false

    init(limits: QmodLimitProfile = .reviewProposalV1, expansionGuard: QmodExpansionGuard = .localProcessStop) {
        _model = StateObject(wrappedValue: QmodAuthorImportModel(limits: limits, expansionGuard: expansionGuard))
    }

    var body: some View {
        List {
            Section(header: Text(verbatim: "本机边界")) {
                Text(verbatim: QmodLocalInspectionReport.fixedServerDenialText)
                    .accessibilityIdentifier("qmod.authorImport.serverStatus")
                Text(verbatim: "体积与条数上限来自调用方给出的限制档 \(model.limits.profileVersion)，不是正式业务规则。")
                Text(verbatim: "压缩倍数止损 \(model.expansionGuard.numerator):\(model.expansionGuard.denominator) 只是本进程安全停止，不是正式业务规则。")
                Text(verbatim: QmodLocalInspectionReport.fixedExecutionDenialText)
            }
            Section {
                Button(action: { picking = true }) { Text(verbatim: "选择包") }
                    .accessibilityIdentifier("qmod.authorImport.pick")
                Button(action: { picking = true }) { Text(verbatim: "换包") }
                    .disabled(model.session.phase == .idle)
                    .accessibilityIdentifier("qmod.authorImport.replace")
                Button(action: { model.recheck() }) { Text(verbatim: "复检") }
                    .disabled(!model.session.canRecheck)
                    .accessibilityIdentifier("qmod.authorImport.recheck")
                Button(action: { model.cancel() }) { Text(verbatim: "取消") }
                    .disabled(model.session.phase == .idle || model.session.phase == .cancelled)
                    .accessibilityIdentifier("qmod.authorImport.cancel")
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
            if case .success(let url) = result { importPackage(at: url) }
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

    private func importPackage(at url: URL) {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        let facts = QmodLocalFileFacts(
            isSymbolicLink: values?.isSymbolicLink == true,
            isRegularFile: values?.isRegularFile == true,
            byteCount: values?.fileSize.map(Int64.init)
        )
        var bytes: Data?
        if facts.isRegularFile, !facts.isSymbolicLink, let count = facts.byteCount, count >= 0, count <= model.limits.maxArchiveBytes {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            bytes = try? Data(contentsOf: url)
        }
        model.importLocal(facts: facts, bytes: bytes, label: url.lastPathComponent)
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
    }
}
