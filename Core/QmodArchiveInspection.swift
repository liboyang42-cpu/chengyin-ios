import CryptoKit
import Darwin
import Foundation
import zlib

/// U08 / W18 local qmod import. Reads one selected ZIP in this process, checks
/// archive safety, then checks `manifest.json` and per-file digests with
/// `QmodManifest`. The only result is a local report.
///
/// UploadModDraft and ValidateModPackage are not approved. This type has no
/// upload result and does not execute package bytes. `QmodLimitProfile` numbers
/// are a labelled proposal, not a business rule and not the pre-read stop.
/// `QmodLocalReadBudget` is the only byte cap used while opening a file.
public enum QmodArchiveIssueCode: Equatable, Sendable {
    case pathTraversal(String)
    case duplicatePath(String)
    case abnormalCompression(path: String, compressed: Int64, uncompressed: Int64)
    case symlink(String)
    case notARegularFile(String)
    case unsafeEntry(String)
    case corrupt(detail: String)
    case digestMismatch(path: String, actualSHA256: String, declaredSHA256: String, actualBytes: Int64, declaredBytes: Int64)
    case manifest(QmodManifestIssue)
    case proposalPresentedAsBusinessRule
    case limitProfileNotApproved(String)
    case archiveTooLarge(actual: Int64, limit: Int64)
    case fileTooLarge(path: String, actual: Int64, limit: Int64)
    case expandedTooLarge(path: String, actual: Int64, limit: Int64)
    case tooManyEntries(actual: Int, limit: Int)
    case unexpectedEntry(String)
    case missingEntry(String)
    case unsupportedMethod(path: String, method: Int)
    case unsupportedZip64(String)
    case encrypted(String)
    case localFileUnreadable(String)
    /// The read ceiling was labelled as a proposal or a business rule, so the file was not opened.
    case readBudgetPosedAsRule
    /// `maxBytes` cannot be probed without signed overflow. The file was not opened.
    case readBudgetUnsafe
    /// The opened file passed the process read ceiling. Bytes past the ceiling were not kept.
    case readBudgetExceeded(actual: Int64, limit: Int64)
    /// The background check was cancelled. Callers drop this report instead of showing it.
    case checkCancelled
}

public struct QmodArchiveIssue: Equatable, Sendable {
    public let code: QmodArchiveIssueCode
    public let entryIndex: Int?
    public let headerOffset: Int?
    public let path: String?
    public init(code: QmodArchiveIssueCode, entryIndex: Int?, headerOffset: Int?, path: String?) {
        self.code = code
        self.entryIndex = entryIndex
        self.headerOffset = headerOffset
        self.path = path
    }
}

public struct QmodFileDigestSummary: Equatable, Sendable {
    public enum Role: Equatable, Sendable { case manifest, content }
    public let path: String
    public let sha256: String
    public let bytes: Int64
    public let role: Role
    public let matchesManifest: Bool
    public init(path: String, sha256: String, bytes: Int64, role: Role, matchesManifest: Bool) {
        self.path = path
        self.sha256 = sha256
        self.bytes = bytes
        self.role = role
        self.matchesManifest = matchesManifest
    }
}

public enum QmodServerSubmission: Equatable, Sendable {
    /// The unapproved endpoints were not called. There is no server acceptance to report.
    case notAttempted
}

/// Foundation JSON objects keep the last duplicate key. This report does not claim to find them.
public enum QmodDuplicateJSONKeyPolicy: Equatable, Sendable { case notDetectedServerCheck }

public struct QmodExpansionGuard: Equatable, Sendable {
    public let numerator: Int64
    public let denominator: Int64
    /// When true, inspection refuses the package. A ratio must not be presented as a business rule.
    public let isBusinessRule: Bool
    public init(numerator: Int64, denominator: Int64, isBusinessRule: Bool) {
        self.numerator = numerator
        self.denominator = denominator
        self.isBusinessRule = isBusinessRule
    }
    /// Stop a hostile archive in this process. Not a Part C limit and not a server rule.
    public static let localProcessStop = QmodExpansionGuard(numerator: 100, denominator: 1, isBusinessRule: false)
}

/// Byte cap for opening one selected file. Independent of `QmodLimitProfile`.
/// `reviewProposalV1.maxArchiveBytes` (25 MiB) is not this ceiling.
public struct QmodLocalReadBudget: Equatable, Sendable {
    public let maxBytes: Int64
    public let isProposal: Bool
    public let isBusinessRule: Bool
    public init(maxBytes: Int64, isProposal: Bool, isBusinessRule: Bool) {
        self.maxBytes = maxBytes
        self.isProposal = isProposal
        self.isBusinessRule = isBusinessRule
    }
    /// 32 MiB process allocation stop. Not a proposal profile and not a business rule.
    public static let localProcessStop = QmodLocalReadBudget(maxBytes: 32 << 20, isProposal: false, isBusinessRule: false)
    /// Largest injectable byte count whose `+ 1` probe fits in both `Int64` and `Int`. Technical allocation ceiling, not a package quota.
    public static let memorySafetyCeiling: Int64 = Int64(Int.max) - 1

    public var isUsable: Bool { !isProposal && !isBusinessRule && Self.admits(maxBytes) }

    public static func admits(_ maxBytes: Int64) -> Bool {
        maxBytes > 0 && maxBytes <= memorySafetyCeiling
    }

    /// Room for one more byte past `collected`, so a growing file can be rejected without wrapping `cap + 1`.
    public static func probeRoom(cap: Int64, collected: Int) -> Int? {
        guard admits(cap), collected >= 0 else { return nil }
        let count = Int64(collected)
        guard count <= cap else { return nil }
        let (rest, restOverflow) = cap.subtractingReportingOverflow(count)
        if restOverflow { return nil }
        let (room, roomOverflow) = rest.addingReportingOverflow(1)
        if roomOverflow || room > Int64(Int.max) { return nil }
        return Int(room)
    }
}

public struct QmodLocalFileFacts: Equatable, Sendable {
    public let isSymbolicLink: Bool
    public let isRegularFile: Bool
    public let byteCount: Int64?
    public init(isSymbolicLink: Bool, isRegularFile: Bool, byteCount: Int64?) {
        self.isSymbolicLink = isSymbolicLink
        self.isRegularFile = isRegularFile
        self.byteCount = byteCount
    }
}

public struct QmodLocalInspectionReport: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable { case passedLocalChecks, failedLocalChecks }
    public let generation: UInt64
    public let packageLabel: String
    public let outcome: Outcome
    public let issues: [QmodArchiveIssue]
    public let fileSummaries: [QmodFileDigestSummary]
    public let manifestPackageId: String?
    public let limitProfileVersion: String
    public let limitProfileIsProposal: Bool
    public let expansionNumerator: Int64
    public let expansionDenominator: Int64
    public let duplicateJSONKeys: QmodDuplicateJSONKeyPolicy
    public let limitsAreBusinessRules: Bool
    public let localReadBudgetBytes: Int64
    public let localReadBudgetIsProposal: Bool
    public let localReadBudgetIsBusinessRule: Bool
    public let serverSubmission: QmodServerSubmission
    public let executedPackageCode: Bool
    public let acceptedH5: Bool
    public let uploaded: Bool

    public static let fixedServerDenialText = "本机检查报告，未提交服务器。UploadModDraft 与 ValidateModPackage 尚未审定，这里没有服务器受理结果。"
    public static let fixedExecutionDenialText = "本检查不执行包内代码，不接受 H5，不上传包。"
    public var serverDenialText: String { Self.fixedServerDenialText }
    public var proposalDenialText: String {
        "体积与条数上限来自调用方给出的限制档 \(limitProfileVersion)，不是正式业务规则，也不是打开文件前的读入停止线。"
    }
    public var expansionDenialText: String {
        "压缩倍数止损 \(expansionNumerator):\(expansionDenominator) 只是本进程安全停止，不是正式业务规则。"
    }
    public var readBudgetDenialText: String {
        "读入停止线 \(localReadBudgetBytes) 字节只属于本进程，不是限制档 \(limitProfileVersion)，也不是正式业务规则。"
    }
    public var executionDenialText: String { Self.fixedExecutionDenialText }
    public var outcomeText: String {
        switch outcome {
        case .passedLocalChecks: return "本机检查通过。这不是服务器提交成功。"
        case .failedLocalChecks: return "本机检查未通过。这不是服务器提交成功。"
        }
    }

    public init(generation: UInt64, packageLabel: String, issues: [QmodArchiveIssue], fileSummaries: [QmodFileDigestSummary], manifestPackageId: String?, limits: QmodLimitProfile, expansionGuard: QmodExpansionGuard, readBudget: QmodLocalReadBudget = .localProcessStop) {
        self.generation = generation
        self.packageLabel = packageLabel
        self.outcome = issues.isEmpty ? .passedLocalChecks : .failedLocalChecks
        self.issues = issues
        self.fileSummaries = fileSummaries
        self.manifestPackageId = manifestPackageId
        self.limitProfileVersion = limits.profileVersion
        self.limitProfileIsProposal = limits.isProposal
        self.expansionNumerator = expansionGuard.numerator
        self.expansionDenominator = expansionGuard.denominator
        self.duplicateJSONKeys = .notDetectedServerCheck
        self.limitsAreBusinessRules = false
        self.localReadBudgetBytes = readBudget.maxBytes
        self.localReadBudgetIsProposal = readBudget.isProposal
        self.localReadBudgetIsBusinessRule = readBudget.isBusinessRule
        self.serverSubmission = .notAttempted
        self.executedPackageCode = false
        self.acceptedH5 = false
        self.uploaded = false
    }
}

public enum QmodArchiveInspection {
    public static func inspect(package: Data, limits: QmodLimitProfile, expansionGuard: QmodExpansionGuard, generation: UInt64 = 0, packageLabel: String, readBudget: QmodLocalReadBudget = .localProcessStop) -> QmodLocalInspectionReport {
        let label = QmodArchiveLabels.sanitize(packageLabel)
        func finish(_ issues: [QmodArchiveIssue], _ summaries: [QmodFileDigestSummary] = [], _ packageId: String? = nil) -> QmodLocalInspectionReport {
            QmodLocalInspectionReport(generation: generation, packageLabel: label, issues: issues, fileSummaries: summaries, manifestPackageId: packageId, limits: limits, expansionGuard: expansionGuard, readBudget: readBudget)
        }
        if expansionGuard.isBusinessRule || expansionGuard.numerator <= 0 || expansionGuard.denominator <= 0 {
            return finish([QmodArchiveIssue(code: .proposalPresentedAsBusinessRule, entryIndex: nil, headerOffset: nil, path: nil)])
        }
        if readBudget.isProposal || readBudget.isBusinessRule {
            return finish([QmodArchiveIssue(code: .readBudgetPosedAsRule, entryIndex: nil, headerOffset: nil, path: nil)])
        }
        if !QmodLocalReadBudget.admits(readBudget.maxBytes) {
            return finish([QmodArchiveIssue(code: .readBudgetUnsafe, entryIndex: nil, headerOffset: nil, path: nil)])
        }
        if Int64(package.count) > readBudget.maxBytes {
            return finish([QmodArchiveIssue(code: .readBudgetExceeded(actual: Int64(package.count), limit: readBudget.maxBytes), entryIndex: nil, headerOffset: nil, path: nil)])
        }
        if Task.isCancelled { return finish([QmodArchiveIssue(code: .checkCancelled, entryIndex: nil, headerOffset: nil, path: nil)]) }
        var issues: [QmodArchiveIssue] = []
        if !limits.isProposal {
            issues.append(QmodArchiveIssue(code: .limitProfileNotApproved(limits.profileVersion), entryIndex: nil, headerOffset: nil, path: nil))
        }
        let packageCount = Int64(package.count)
        if packageCount > limits.maxArchiveBytes {
            issues.append(QmodArchiveIssue(code: .archiveTooLarge(actual: packageCount, limit: limits.maxArchiveBytes), entryIndex: nil, headerOffset: nil, path: nil))
            return finish(issues)
        }
        let directory: QmodZipDirectory
        switch QmodZip.readDirectory(package) {
        case .ready(let value): directory = value
        case .failed(let issue):
            issues.append(issue)
            return finish(issues)
        }
        let manifestSlots = directory.records.filter { $0.name == "manifest.json" }.count
        let contentCount = directory.records.count - manifestSlots
        if contentCount > limits.maxFiles {
            issues.append(QmodArchiveIssue(code: .tooManyEntries(actual: contentCount, limit: limits.maxFiles), entryIndex: nil, headerOffset: directory.eocdOffset, path: nil))
            return finish(issues)
        }
        var seen: [String: String] = [:]
        var spans: [(start: Int, end: Int, index: Int)] = []
        var candidates: [QmodZipCandidate] = []
        for record in directory.records {
            if Task.isCancelled { return finish([QmodArchiveIssue(code: .checkCancelled, entryIndex: nil, headerOffset: nil, path: nil)]) }
            func add(_ code: QmodArchiveIssueCode, offset: Int? = nil) {
                issues.append(QmodArchiveIssue(code: code, entryIndex: record.index, headerOffset: offset ?? record.localOffset, path: record.name))
            }
            if record.zip64 {
                add(.unsupportedZip64(record.name), offset: record.centralOffset)
                continue
            }
            switch QmodZip.locatePayload(package, record: record, centralDirectoryOffset: directory.centralOffset) {
            case .failed(let detail):
                add(.corrupt(detail: detail), offset: record.centralOffset)
                continue
            case .found(let start, let encrypted):
                let end = start + Int(record.compressedSize)
                spans.append((start, end, record.index))
                if record.encrypted || encrypted {
                    add(.encrypted(record.name))
                    continue
                }
                if QmodZip.isTraversal(record.name) {
                    add(.pathTraversal(record.name))
                    continue
                }
                if QmodZip.isSymlink(record) {
                    add(.symlink(record.name))
                    continue
                }
                if QmodZip.isNonRegular(record) {
                    add(.notARegularFile(record.name))
                    continue
                }
                if (try? QmodManifest.checkPath(record.name, limits: limits)) == nil {
                    add(.unsafeEntry(record.name))
                    continue
                }
                let folded = record.name.lowercased()
                if seen[folded] != nil {
                    add(.duplicatePath(record.name))
                    continue
                }
                seen[folded] = record.name
                if record.uncompressedSize > limits.maxFileBytes {
                    add(.fileTooLarge(path: record.name, actual: record.uncompressedSize, limit: limits.maxFileBytes))
                    continue
                }
                if record.method != 0 && record.method != 8 {
                    add(.unsupportedMethod(path: record.name, method: Int(record.method)))
                    continue
                }
                if record.method == 0 && record.compressedSize != record.uncompressedSize {
                    add(.corrupt(detail: "size"))
                    continue
                }
                if record.method != 0 && QmodZip.expansionExceeds(compressed: record.compressedSize, uncompressed: record.uncompressedSize, expansionGuard: expansionGuard) {
                    add(.abnormalCompression(path: record.name, compressed: record.compressedSize, uncompressed: record.uncompressedSize))
                    continue
                }
                candidates.append(QmodZipCandidate(record: record, dataStart: start))
            }
        }
        let overlapped = QmodZip.overlappingIndexes(spans)
        if !overlapped.isEmpty {
            candidates.removeAll { overlapped.contains($0.record.index) }
            for index in overlapped.sorted() {
                let record = directory.records[index]
                issues.append(QmodArchiveIssue(code: .corrupt(detail: "overlap"), entryIndex: index, headerOffset: record.localOffset, path: record.name))
            }
        }
        let ordered = candidates.filter { $0.record.name == "manifest.json" } + candidates.filter { $0.record.name != "manifest.json" }
        var running: Int64 = 0
        var chosen: [QmodZipCandidate] = []
        for candidate in ordered {
            let size = candidate.record.uncompressedSize
            if size > limits.maxExpandedBytes || running > limits.maxExpandedBytes - size {
                issues.append(QmodArchiveIssue(code: .expandedTooLarge(path: candidate.record.name, actual: running + size, limit: limits.maxExpandedBytes), entryIndex: candidate.record.index, headerOffset: candidate.record.localOffset, path: candidate.record.name))
                continue
            }
            running += size
            chosen.append(candidate)
        }
        var manifestBytes: Data?
        var manifestIndex: Int?
        var manifestOffset: Int?
        var summaries: [QmodFileDigestSummary] = []
        for candidate in chosen {
            if Task.isCancelled { return finish([QmodArchiveIssue(code: .checkCancelled, entryIndex: nil, headerOffset: nil, path: nil)]) }
            let record = candidate.record
            let decoded: QmodZipBytes
            switch record.method {
            case 0:
                guard let bytes = QmodZip.slice(package, candidate.dataStart, Int(record.compressedSize)) else {
                    issues.append(QmodArchiveIssue(code: .corrupt(detail: "truncated"), entryIndex: record.index, headerOffset: record.localOffset, path: record.name))
                    continue
                }
                decoded = .exact(bytes)
            case 8:
                guard let compressed = QmodZip.slice(package, candidate.dataStart, Int(record.compressedSize)) else {
                    issues.append(QmodArchiveIssue(code: .corrupt(detail: "truncated"), entryIndex: record.index, headerOffset: record.localOffset, path: record.name))
                    continue
                }
                decoded = QmodRawDeflate.inflate(compressed, exact: Int(record.uncompressedSize))
            default:
                issues.append(QmodArchiveIssue(code: .unsupportedMethod(path: record.name, method: Int(record.method)), entryIndex: record.index, headerOffset: record.localOffset, path: record.name))
                continue
            }
            let payload: Data
            switch decoded {
            case .exact(let bytes): payload = bytes
            case .exceeded:
                issues.append(QmodArchiveIssue(code: .abnormalCompression(path: record.name, compressed: record.compressedSize, uncompressed: record.uncompressedSize), entryIndex: record.index, headerOffset: record.localOffset, path: record.name))
                continue
            case .cancelled:
                return finish([QmodArchiveIssue(code: .checkCancelled, entryIndex: nil, headerOffset: nil, path: nil)])
            case .corrupt:
                issues.append(QmodArchiveIssue(code: .corrupt(detail: "inflate"), entryIndex: record.index, headerOffset: record.localOffset, path: record.name))
                continue
            }
            guard Int64(payload.count) == record.uncompressedSize else {
                issues.append(QmodArchiveIssue(code: .corrupt(detail: "size"), entryIndex: record.index, headerOffset: record.localOffset, path: record.name))
                continue
            }
            guard let crc = QmodCRC32.checksum(payload) else {
                return finish([QmodArchiveIssue(code: .checkCancelled, entryIndex: nil, headerOffset: nil, path: nil)])
            }
            guard crc == record.crc else {
                issues.append(QmodArchiveIssue(code: .corrupt(detail: "crc32"), entryIndex: record.index, headerOffset: record.localOffset, path: record.name))
                continue
            }
            guard let digest = QmodZip.sha256Hex(payload) else {
                return finish([QmodArchiveIssue(code: .checkCancelled, entryIndex: nil, headerOffset: nil, path: nil)])
            }
            if record.name == "manifest.json" {
                manifestBytes = payload
                manifestIndex = record.index
                manifestOffset = record.localOffset
                summaries.append(QmodFileDigestSummary(path: record.name, sha256: digest, bytes: Int64(payload.count), role: .manifest, matchesManifest: false))
            } else {
                summaries.append(QmodFileDigestSummary(path: record.name, sha256: digest, bytes: Int64(payload.count), role: .content, matchesManifest: false))
            }
        }
        var packageId: String?
        if let manifestBytes {
            do {
                let manifest = try QmodManifest(data: manifestBytes, limits: limits)
                packageId = manifest.packageId
                if let index = summaries.firstIndex(where: { $0.role == .manifest }) {
                    let item = summaries[index]
                    summaries[index] = QmodFileDigestSummary(path: item.path, sha256: item.sha256, bytes: item.bytes, role: .manifest, matchesManifest: true)
                }
                for index in summaries.indices where summaries[index].role == .content {
                    let item = summaries[index]
                    if let file = manifest.files.first(where: { $0.path == item.path }) {
                        if file.sha256 == item.sha256 && file.bytes == item.bytes {
                            summaries[index] = QmodFileDigestSummary(path: item.path, sha256: item.sha256, bytes: item.bytes, role: .content, matchesManifest: true)
                        } else {
                            issues.append(QmodArchiveIssue(code: .digestMismatch(path: item.path, actualSHA256: item.sha256, declaredSHA256: file.sha256, actualBytes: item.bytes, declaredBytes: file.bytes), entryIndex: nil, headerOffset: nil, path: item.path))
                        }
                    } else {
                        issues.append(QmodArchiveIssue(code: .unexpectedEntry(item.path), entryIndex: nil, headerOffset: nil, path: item.path))
                    }
                }
                for file in manifest.files where !summaries.contains(where: { $0.path == file.path }) && !issues.contains(where: { $0.path == file.path }) {
                    issues.append(QmodArchiveIssue(code: .missingEntry(file.path), entryIndex: nil, headerOffset: nil, path: file.path))
                }
            } catch let issue as QmodManifestIssue {
                issues.append(QmodArchiveIssue(code: .manifest(issue), entryIndex: manifestIndex, headerOffset: manifestOffset, path: "manifest.json"))
            } catch {
                issues.append(QmodArchiveIssue(code: .corrupt(detail: "manifest"), entryIndex: manifestIndex, headerOffset: manifestOffset, path: "manifest.json"))
            }
        } else if !issues.contains(where: { $0.path == "manifest.json" }) {
            issues.append(QmodArchiveIssue(code: .missingEntry("manifest.json"), entryIndex: nil, headerOffset: nil, path: "manifest.json"))
        }
        return finish(issues, summaries, packageId)
    }
}

public struct QmodArchiveInspectionSession: Equatable {
    public enum Phase: Equatable { case idle, choosing, inspecting, reported, cancelled }
    public private(set) var generation: UInt64
    public private(set) var phase: Phase
    public private(set) var packageLabel: String?
    public private(set) var report: QmodLocalInspectionReport?
    public var canRecheck: Bool { retained != nil }
    private var retained: Data?
    private var limits: QmodLimitProfile?
    private var expansionGuard: QmodExpansionGuard?

    public init() {
        generation = 0
        phase = .idle
        packageLabel = nil
        report = nil
        retained = nil
        limits = nil
        expansionGuard = nil
    }

    public static func == (lhs: QmodArchiveInspectionSession, rhs: QmodArchiveInspectionSession) -> Bool {
        lhs.generation == rhs.generation && lhs.phase == rhs.phase && lhs.packageLabel == rhs.packageLabel && lhs.report == rhs.report && lhs.retained == rhs.retained && lhs.limits == rhs.limits && lhs.expansionGuard == rhs.expansionGuard
    }

    public mutating func select(bytes: Data, label: String, limits: QmodLimitProfile, expansionGuard: QmodExpansionGuard, readBudget: QmodLocalReadBudget = .localProcessStop) {
        selectLocalFile(facts: QmodLocalFileFacts(isSymbolicLink: false, isRegularFile: true, byteCount: Int64(bytes.count)), bytes: bytes, label: label, limits: limits, expansionGuard: expansionGuard, readBudget: readBudget)
    }

    public mutating func replace(bytes: Data, label: String, limits: QmodLimitProfile, expansionGuard: QmodExpansionGuard, readBudget: QmodLocalReadBudget = .localProcessStop) {
        select(bytes: bytes, label: label, limits: limits, expansionGuard: expansionGuard, readBudget: readBudget)
    }

    /// Bumps the generation and clears the visible report before a background check starts.
    public mutating func beginSelection(label: String) -> UInt64 { begin(label) }

    /// Retires the current selection before a new file picker opens. An in-flight result can no longer complete.
    /// A finished report is dropped here; keeping one would require an explicit stale mark, which this screen does not show.
    public mutating func invalidateSelection() {
        generation &+= 1
        phase = .choosing
        report = nil
        packageLabel = nil
        retained = nil
        limits = nil
        expansionGuard = nil
    }

    public func packageForRecheck() -> (bytes: Data, label: String, limits: QmodLimitProfile, expansionGuard: QmodExpansionGuard)? {
        guard let retained, let limits, let expansionGuard, let packageLabel else { return nil }
        return (retained, packageLabel, limits, expansionGuard)
    }

    /// Keeps bytes only after `complete` has accepted the matching generation.
    public mutating func noteRetainedPackage(_ bytes: Data, limits: QmodLimitProfile, expansionGuard: QmodExpansionGuard) {
        guard phase == .reported else { return }
        retained = bytes
        self.limits = limits
        self.expansionGuard = expansionGuard
    }

    public mutating func selectLocalFile(facts: QmodLocalFileFacts, bytes: Data?, label: String, limits: QmodLimitProfile, expansionGuard: QmodExpansionGuard, readBudget: QmodLocalReadBudget = .localProcessStop) {
        let generation = begin(label)
        let safeLabel = packageLabel ?? "package"
        let report: QmodLocalInspectionReport
        if facts.isSymbolicLink {
            report = QmodLocalInspectionReport(generation: generation, packageLabel: safeLabel, issues: [QmodArchiveIssue(code: .symlink(safeLabel), entryIndex: nil, headerOffset: nil, path: safeLabel)], fileSummaries: [], manifestPackageId: nil, limits: limits, expansionGuard: expansionGuard, readBudget: readBudget)
        } else if !facts.isRegularFile {
            report = QmodLocalInspectionReport(generation: generation, packageLabel: safeLabel, issues: [QmodArchiveIssue(code: .notARegularFile(safeLabel), entryIndex: nil, headerOffset: nil, path: safeLabel)], fileSummaries: [], manifestPackageId: nil, limits: limits, expansionGuard: expansionGuard, readBudget: readBudget)
        } else if let count = facts.byteCount, let bytes, Int64(bytes.count) == count {
            report = QmodArchiveInspection.inspect(package: bytes, limits: limits, expansionGuard: expansionGuard, generation: generation, packageLabel: safeLabel, readBudget: readBudget)
            if readBudget.isUsable, Int64(bytes.count) <= readBudget.maxBytes, !report.issues.contains(where: { if case .checkCancelled = $0.code { return true }; return false }) {
                retained = bytes
                self.limits = limits
                self.expansionGuard = expansionGuard
            }
        } else {
            report = QmodLocalInspectionReport(generation: generation, packageLabel: safeLabel, issues: [QmodArchiveIssue(code: .localFileUnreadable(safeLabel), entryIndex: nil, headerOffset: nil, path: safeLabel)], fileSummaries: [], manifestPackageId: nil, limits: limits, expansionGuard: expansionGuard, readBudget: readBudget)
        }
        _ = complete(generation: generation, report: report)
    }

    public mutating func recheck() {
        guard let retained, let limits, let expansionGuard, let packageLabel else { return }
        select(bytes: retained, label: packageLabel, limits: limits, expansionGuard: expansionGuard)
    }

    public mutating func cancel() {
        generation &+= 1
        phase = .cancelled
        report = nil
        packageLabel = nil
        retained = nil
        limits = nil
        expansionGuard = nil
    }

    /// Applies a report only when it belongs to the inspection that is still current.
    @discardableResult
    public mutating func complete(generation: UInt64, report: QmodLocalInspectionReport) -> Bool {
        guard generation == self.generation, report.generation == generation, phase == .inspecting else { return false }
        self.report = report
        phase = .reported
        return true
    }

    private mutating func begin(_ label: String) -> UInt64 {
        generation &+= 1
        phase = .inspecting
        report = nil
        packageLabel = QmodArchiveLabels.sanitize(label)
        retained = nil
        limits = nil
        expansionGuard = nil
        return generation
    }
}

public enum QmodOpenedPackage: Equatable, Sendable {
    case bytes(Data)
    case symlink
    case notRegularFile
    case readBudgetExceeded(actual: Int64, limit: Int64)
    case readBudgetPosedAsRule
    case readBudgetUnsafe
    case unreadable
    case cancelled
}

/// Opens one security-scoped URL. The access lease is acquired before any stat, open, or read.
public enum QmodSecurityScopedPackage {
    public static func open(url: URL, budget: QmodLocalReadBudget) -> QmodOpenedPackage {
        let lease = url.startAccessingSecurityScopedResource()
        defer { if lease { url.stopAccessingSecurityScopedResource() } }
        if Task.isCancelled { return .cancelled }
        guard budget.isUsable else {
            return (budget.isProposal || budget.isBusinessRule) ? .readBudgetPosedAsRule : .readBudgetUnsafe
        }
        guard url.isFileURL else { return .unreadable }
        let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        }
        if fd < 0 {
            if pathIsSymlink(url) { return .symlink }
            return .unreadable
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0 else { return .unreadable }
        let kind = info.st_mode & mode_t(S_IFMT)
        if kind == mode_t(S_IFLNK) { return .symlink }
        if kind != mode_t(S_IFREG) { return .notRegularFile }
        let cap = budget.maxBytes
        if info.st_size < 0 { return .unreadable }
        if info.st_size > cap { return .readBudgetExceeded(actual: info.st_size, limit: cap) }
        var collected = Data()
        if info.st_size > 0 { collected.reserveCapacity(Int(info.st_size)) }
        let chunkSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while Int64(collected.count) <= cap {
            if Task.isCancelled { return .cancelled }
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(fd, base, chunkSize)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                return .unreadable
            }
            guard let room = QmodLocalReadBudget.probeRoom(cap: cap, collected: collected.count) else {
                return .readBudgetExceeded(actual: Int64(collected.count), limit: cap)
            }
            let take = min(Int64(count), Int64(room))
            if take > 0 { collected.append(contentsOf: buffer.prefix(Int(take))) }
            if Int64(collected.count) > cap { return .readBudgetExceeded(actual: Int64(collected.count), limit: cap) }
        }
        var after = stat()
        guard Darwin.fstat(fd, &after) == 0, (after.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { return .unreadable }
        let sameFile = after.st_dev == info.st_dev && after.st_ino == info.st_ino && after.st_size == info.st_size && after.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec && after.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec
        if !sameFile || Int64(collected.count) != info.st_size {
            if after.st_size > cap || Int64(collected.count) > cap {
                return .readBudgetExceeded(actual: max(after.st_size, Int64(collected.count)), limit: cap)
            }
            return .unreadable
        }
        return .bytes(collected)
    }

    private static func pathIsSymlink(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            var info = stat()
            return Darwin.lstat(path, &info) == 0 && (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
        }
    }
}

public enum QmodArchiveLabels {
    public static func sanitize(_ label: String) -> String {
        let scalars = label.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0.value != 0x7F }
        let text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "package" }
        return text.count <= 200 ? text : String(text.prefix(200))
    }
}

enum QmodCRC32 {
    static func checksum(_ data: Data) -> UInt32? {
        var crc: UInt32 = 0xFFFF_FFFF
        var steps = 0
        for byte in data {
            if steps & 0xFFFF == 0, Task.isCancelled { return nil }
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            steps += 1
        }
        if Task.isCancelled { return nil }
        return crc ^ 0xFFFF_FFFF
    }

    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1) }
        return value
    }
}

private enum QmodZipBytes { case exact(Data), exceeded, corrupt, cancelled }

private enum QmodRawDeflate {
    static func inflate(_ input: Data, exact: Int) -> QmodZipBytes {
        if Task.isCancelled { return .cancelled }
        guard exact >= 0, input.count <= Int(UInt32.max), exact <= Int(UInt32.max) else { return .corrupt }
        if input.isEmpty { return exact == 0 ? .exact(Data()) : .corrupt }
        var stream = z_stream()
        guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return .corrupt }
        defer { inflateEnd(&stream) }
        if exact == 0 {
            var probe: UInt8 = 0
            let status = input.withUnsafeBytes { raw -> Int32 in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return Z_DATA_ERROR }
                stream.next_in = UnsafeMutablePointer(mutating: base)
                stream.avail_in = UInt32(input.count)
                return withUnsafeMutablePointer(to: &probe) { pointer in
                    stream.next_out = pointer
                    stream.avail_out = 1
                    return inflate(&stream, Z_FINISH)
                }
            }
            if stream.avail_out == 0 { return .exceeded }
            return status == Z_STREAM_END ? .exact(Data()) : .corrupt
        }
        var output = [UInt8](repeating: 0, count: exact)
        var produced = 0
        var status: Int32 = Z_OK
        let cancelled: Bool = input.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { status = Z_DATA_ERROR; return false }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = UInt32(input.count)
            while produced < exact && status != Z_STREAM_END {
                if Task.isCancelled { return true }
                let want = min(65_536, exact - produced)
                status = output.withUnsafeMutableBytes { out -> Int32 in
                    guard let outBase = out.bindMemory(to: UInt8.self).baseAddress else { return Z_DATA_ERROR }
                    stream.next_out = outBase.advanced(by: produced)
                    stream.avail_out = UInt32(want)
                    return inflate(&stream, produced + want == exact ? Z_FINISH : Z_NO_FLUSH)
                }
                let wrote = want - Int(stream.avail_out)
                if wrote <= 0 { break }
                produced += wrote
            }
            return false
        }
        if cancelled { return .cancelled }
        if status == Z_STREAM_END && produced == exact && stream.avail_in == 0 { return .exact(Data(output)) }
        if produced == exact && status != Z_STREAM_END { return .exceeded }
        return .corrupt
    }
}

private struct QmodCentralRecord {
    let index: Int
    let centralOffset: Int
    let name: String
    let method: UInt16
    let flags: UInt16
    let crc: UInt32
    let compressedSize: Int64
    let uncompressedSize: Int64
    let localOffset: Int
    let externalAttributes: UInt32
    let encrypted: Bool
    let zip64: Bool
}

private struct QmodZipDirectory {
    let records: [QmodCentralRecord]
    let eocdOffset: Int
    let centralOffset: Int
}

private struct QmodZipCandidate {
    let record: QmodCentralRecord
    let dataStart: Int
}

private enum QmodZipLocate { case found(start: Int, encrypted: Bool), failed(String) }

private enum QmodZipRead { case ready(QmodZipDirectory), failed(QmodArchiveIssue) }

private enum QmodZip {
    static func readDirectory(_ data: Data) -> QmodZipRead {
        guard let eocd = findEOCD(data) else {
            return .failed(QmodArchiveIssue(code: .corrupt(detail: "eocd"), entryIndex: nil, headerOffset: nil, path: nil))
        }
        guard let disk = u16(data, eocd + 4), let diskWithCD = u16(data, eocd + 6), let entriesHere = u16(data, eocd + 8), let entriesTotal = u16(data, eocd + 10), let cdSizeRaw = u32(data, eocd + 12), let cdOffsetRaw = u32(data, eocd + 16) else {
            return .failed(QmodArchiveIssue(code: .corrupt(detail: "eocd"), entryIndex: nil, headerOffset: eocd, path: nil))
        }
        if disk != 0 || diskWithCD != 0 || entriesHere != entriesTotal {
            return .failed(QmodArchiveIssue(code: .corrupt(detail: "multidisk"), entryIndex: nil, headerOffset: eocd, path: nil))
        }
        if entriesTotal == 0xFFFF || cdSizeRaw == 0xFFFF_FFFF || cdOffsetRaw == 0xFFFF_FFFF {
            return .failed(QmodArchiveIssue(code: .unsupportedZip64(""), entryIndex: nil, headerOffset: eocd, path: nil))
        }
        let cdSize = Int(cdSizeRaw)
        let cdOffset = Int(cdOffsetRaw)
        guard cdOffset >= 0, cdSize >= 0, cdOffset <= data.count, cdSize <= data.count - cdOffset, cdOffset + cdSize <= eocd else {
            return .failed(QmodArchiveIssue(code: .corrupt(detail: "truncated"), entryIndex: nil, headerOffset: eocd, path: nil))
        }
        var cursor = cdOffset
        let cdEnd = cdOffset + cdSize
        var records: [QmodCentralRecord] = []
        while cursor < cdEnd {
            guard cursor + 46 <= cdEnd, u32(data, cursor) == 0x02014b50, let flags = u16(data, cursor + 8), let method = u16(data, cursor + 10), let crc = u32(data, cursor + 16), let compressed = u32(data, cursor + 20), let uncompressed = u32(data, cursor + 24), let nameLen16 = u16(data, cursor + 28), let extraLen16 = u16(data, cursor + 30), let commentLen16 = u16(data, cursor + 32), let external = u32(data, cursor + 38), let local = u32(data, cursor + 42) else {
                return .failed(QmodArchiveIssue(code: .corrupt(detail: "truncated"), entryIndex: nil, headerOffset: cursor, path: nil))
            }
            let nameLen = Int(nameLen16), extraLen = Int(extraLen16), commentLen = Int(commentLen16)
            guard cursor <= cdEnd - 46, nameLen <= cdEnd - 46 - cursor, extraLen <= cdEnd - 46 - nameLen - cursor, commentLen <= cdEnd - 46 - nameLen - extraLen - cursor else {
                return .failed(QmodArchiveIssue(code: .corrupt(detail: "truncated"), entryIndex: nil, headerOffset: cursor, path: nil))
            }
            guard let nameData = slice(data, cursor + 46, nameLen), let name = String(data: nameData, encoding: .utf8) else {
                return .failed(QmodArchiveIssue(code: .corrupt(detail: "name"), entryIndex: records.count, headerOffset: cursor, path: nil))
            }
            let extra = slice(data, cursor + 46 + nameLen, extraLen) ?? Data()
            let zip64 = compressed == 0xFFFF_FFFF || uncompressed == 0xFFFF_FFFF || local == 0xFFFF_FFFF || extraHasZip64(extra)
            records.append(QmodCentralRecord(index: records.count, centralOffset: cursor, name: name, method: method, flags: flags, crc: crc, compressedSize: Int64(compressed), uncompressedSize: Int64(uncompressed), localOffset: zip64 ? 0 : Int(local), externalAttributes: external, encrypted: flags & 0x1 != 0 || flags & 0x40 != 0, zip64: zip64))
            cursor += 46 + nameLen + extraLen + commentLen
        }
        guard cursor == cdEnd, records.count == Int(entriesTotal) else {
            return .failed(QmodArchiveIssue(code: .corrupt(detail: "truncated"), entryIndex: nil, headerOffset: eocd, path: nil))
        }
        return .ready(QmodZipDirectory(records: records, eocdOffset: eocd, centralOffset: cdOffset))
    }

    static func locatePayload(_ data: Data, record: QmodCentralRecord, centralDirectoryOffset: Int) -> QmodZipLocate {
        let local = record.localOffset
        guard local >= 0, data.count - local >= 30, u32(data, local) == 0x04034b50, let flags = u16(data, local + 6), let method = u16(data, local + 8), let nameLen16 = u16(data, local + 26), let extraLen16 = u16(data, local + 28) else {
            return .failed("local-header")
        }
        let nameLen = Int(nameLen16), extraLen = Int(extraLen16)
        guard local <= data.count - 30, nameLen <= data.count - 30 - local, extraLen <= data.count - 30 - nameLen - local else { return .failed("truncated") }
        guard let nameData = slice(data, local + 30, nameLen), String(data: nameData, encoding: .utf8) == record.name else { return .failed("local-header") }
        let start = local + 30 + nameLen + extraLen
        guard record.compressedSize >= 0, record.compressedSize <= Int64(Int.max), Int64(start) <= Int64(centralDirectoryOffset) - record.compressedSize, start <= data.count else {
            return .failed("truncated")
        }
        let descriptor = flags & 0x8 != 0
        if !descriptor {
            guard u32(data, local + 14) == record.crc, u32(data, local + 18).map(Int64.init) == record.compressedSize, u32(data, local + 22).map(Int64.init) == record.uncompressedSize, method == record.method else {
                return .failed("local-header")
            }
        } else if method != record.method {
            return .failed("local-header")
        }
        if let extra = slice(data, local + 30 + nameLen, extraLen), extraHasZip64(extra) { return .failed("zip64") }
        return .found(start: start, encrypted: flags & 0x1 != 0 || flags & 0x40 != 0)
    }

    static func isTraversal(_ path: String) -> Bool {
        if path.unicodeScalars.contains(where: { $0.value == 0 }) || path.hasPrefix("/") || path.contains("\\") { return true }
        return path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    static func isSymlink(_ record: QmodCentralRecord) -> Bool { unixType(record.externalAttributes) == 0o120000 }

    static func isNonRegular(_ record: QmodCentralRecord) -> Bool {
        if record.name.hasSuffix("/") { return true }
        let kind = unixType(record.externalAttributes)
        return kind != 0 && kind != 0o100000
    }

    static func expansionExceeds(compressed: Int64, uncompressed: Int64, expansionGuard: QmodExpansionGuard) -> Bool {
        if uncompressed < 0 || compressed < 0 { return true }
        if uncompressed == 0 { return false }
        if compressed == 0 { return true }
        let left = uncompressed.multipliedReportingOverflow(by: expansionGuard.denominator)
        let right = compressed.multipliedReportingOverflow(by: expansionGuard.numerator)
        if left.overflow { return true }
        if right.overflow { return false }
        return left.partialValue > right.partialValue
    }

    static func overlappingIndexes(_ spans: [(start: Int, end: Int, index: Int)]) -> Set<Int> {
        let ordered = spans.sorted { $0.start < $1.start || ($0.start == $1.start && $0.index < $1.index) }
        guard var maxEnd = ordered.first?.end, var maxIndex = ordered.first?.index else { return [] }
        var overlapped: Set<Int> = []
        for span in ordered.dropFirst() {
            if span.start < maxEnd {
                overlapped.insert(span.index)
                overlapped.insert(maxIndex)
            }
            if span.end > maxEnd {
                maxEnd = span.end
                maxIndex = span.index
            }
        }
        return overlapped
    }

    static func sha256Hex(_ data: Data) -> String? {
        var hasher = SHA256()
        var offset = 0
        while offset < data.count {
            if Task.isCancelled { return nil }
            let end = min(offset + 65_536, data.count)
            data.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: base.advanced(by: offset), count: end - offset))
            }
            offset = end
        }
        if Task.isCancelled { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func slice(_ data: Data, _ start: Int, _ count: Int) -> Data? {
        guard start >= 0, count >= 0, start <= data.count, count <= data.count - start else { return nil }
        return data.subdata(in: start..<(start + count))
    }

    private static func unixType(_ external: UInt32) -> UInt32 { (external >> 16) & 0o170000 }

    private static func extraHasZip64(_ extra: Data) -> Bool {
        var cursor = 0
        while cursor + 4 <= extra.count {
            guard let ident = u16(extra, cursor), let size = u16(extra, cursor + 2) else { return true }
            if ident == 0x0001 { return true }
            guard Int(size) <= extra.count - cursor - 4 else { return true }
            cursor += 4 + Int(size)
        }
        return cursor != extra.count && !extra.isEmpty
    }

    private static func findEOCD(_ data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let lower = max(0, data.count - 22 - 65_535)
        var offset = data.count - 22
        while offset >= lower {
            if u32(data, offset) == 0x06054b50, let comment = u16(data, offset + 20), offset + 22 + Int(comment) == data.count { return offset }
            if offset == 0 { break }
            offset -= 1
        }
        return nil
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset >= 0, offset <= data.count - 2 else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}
