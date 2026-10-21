import XCTest
@testable import QuestifyCore

final class QmodArchiveInspectionTests: XCTestCase {
    private let limits = QmodLimitProfile.reviewProposalV1
    private let expansion = QmodExpansionGuard.localProcessStop

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/QmodArchiveInspection")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    private func inspect(_ name: String, limits: QmodLimitProfile? = nil, expansion: QmodExpansionGuard? = nil) throws -> QmodLocalInspectionReport {
        try QmodArchiveInspection.inspect(package: fixture(name), limits: limits ?? self.limits, expansionGuard: expansion ?? self.expansion, packageLabel: name)
    }

    private func assertLocalOnly(_ report: QmodLocalInspectionReport, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(report.limitsAreBusinessRules, file: file, line: line)
        XCTAssertFalse(report.executedPackageCode, file: file, line: line)
        XCTAssertFalse(report.acceptedH5, file: file, line: line)
        XCTAssertFalse(report.uploaded, file: file, line: line)
        XCTAssertEqual(report.serverSubmission, .notAttempted, file: file, line: line)
        XCTAssertEqual(report.duplicateJSONKeys, .notDetectedServerCheck, file: file, line: line)
        XCTAssertTrue(report.serverDenialText.contains("未提交服务器"), file: file, line: line)
        XCTAssertTrue(report.serverDenialText.contains("UploadModDraft"), file: file, line: line)
        XCTAssertTrue(report.serverDenialText.contains("ValidateModPackage"), file: file, line: line)
        XCTAssertTrue(report.outcomeText.contains("不是服务器提交成功"), file: file, line: line)
        XCTAssertTrue(report.executionDenialText.contains("不执行"), file: file, line: line)
        XCTAssertTrue(report.proposalDenialText.contains("不是正式业务规则"), file: file, line: line)
        XCTAssertTrue(report.expansionDenialText.contains("不是正式业务规则"), file: file, line: line)
    }

    func testCRC32KnownVector() {
        XCTAssertEqual(QmodCRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    func testStoredPackageMatchesManifestDigests() throws {
        let report = try inspect("ok-stored.zip")
        assertLocalOnly(report)
        XCTAssertEqual(report.outcome, .passedLocalChecks)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(report.manifestPackageId, "bookshop.mystery")
        XCTAssertTrue(report.limitProfileIsProposal)
        XCTAssertTrue(report.fileSummaries.allSatisfy(\.matchesManifest))
        XCTAssertTrue(report.fileSummaries.contains { $0.path == "content.json" && $0.role == .content })
        XCTAssertTrue(report.fileSummaries.contains { $0.role == .manifest && $0.path == "manifest.json" })
    }

    func testDeflatePackageIsALocalPassOnly() throws {
        let report = try inspect("ok-deflate.zip")
        assertLocalOnly(report)
        XCTAssertEqual(report.outcome, .passedLocalChecks)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertTrue(report.fileSummaries.allSatisfy(\.matchesManifest))
        XCTAssertEqual(report.outcomeText, "本机检查通过。这不是服务器提交成功。")
    }

    func testPathTraversalIsLocatedAndNotExtracted() throws {
        let report = try inspect("traversal.zip")
        assertLocalOnly(report)
        XCTAssertEqual(report.outcome, .failedLocalChecks)
        for path in ["../evil.json", "/abs.json", "a\\b.json", "foo/../../x.json"] {
            XCTAssertTrue(report.issues.contains { issue in
                guard case .pathTraversal(let got) = issue.code else { return false }
                return got == path && issue.entryIndex != nil && issue.path == path
            }, path)
            XCTAssertFalse(report.fileSummaries.contains { $0.path == path }, path)
        }
    }

    func testDuplicateCaseFoldedPathsAreRejected() throws {
        let report = try inspect("duplicate.zip")
        assertLocalOnly(report)
        XCTAssertTrue(report.issues.contains { issue in
            guard case .duplicatePath("Content.json") = issue.code else { return false }
            return issue.entryIndex != nil
        })
        XCTAssertFalse(report.fileSummaries.contains { $0.path == "Content.json" })
        XCTAssertTrue(report.fileSummaries.contains { $0.path == "content.json" && $0.matchesManifest })
    }

    func testAbnormalCompressionStopsBeforeAPassingReport() throws {
        let report = try inspect("ratio.zip")
        assertLocalOnly(report)
        XCTAssertTrue(report.issues.contains { issue in
            guard case .abnormalCompression(let path, let compressed, let uncompressed) = issue.code else { return false }
            return path == "assets/pad.bin" && compressed > 0 && uncompressed > compressed * 100 && issue.entryIndex != nil
        })
        XCTAssertFalse(report.fileSummaries.contains { $0.path == "assets/pad.bin" })
        XCTAssertEqual(report.outcome, .failedLocalChecks)
    }

    func testSymlinkEntriesAreRejectedAndNotFollowed() throws {
        let report = try inspect("symlink.zip")
        assertLocalOnly(report)
        XCTAssertTrue(report.issues.contains { issue in
            guard case .symlink("assets/alias.json") = issue.code else { return false }
            return issue.path == "assets/alias.json"
        })
        XCTAssertFalse(report.fileSummaries.contains { $0.path == "assets/alias.json" })
        XCTAssertTrue(report.fileSummaries.contains { $0.path == "content.json" && $0.matchesManifest })
    }

    func testCorruptCrcIsNotAPassingReport() throws {
        let report = try inspect("corrupt-crc.zip")
        assertLocalOnly(report)
        XCTAssertEqual(report.outcome, .failedLocalChecks)
        XCTAssertTrue(report.issues.contains { issue in
            guard case .corrupt(let detail) = issue.code else { return false }
            return detail == "crc32" && issue.path == "content.json"
        })
        XCTAssertFalse(report.fileSummaries.contains { $0.path == "content.json" && $0.matchesManifest })
    }

    func testTruncatedArchiveIsCorrupt() throws {
        let report = try inspect("truncated.zip")
        assertLocalOnly(report)
        XCTAssertTrue(report.fileSummaries.isEmpty)
        XCTAssertTrue(report.issues.contains { if case .corrupt = $0.code { return true }; return false })
        XCTAssertEqual(report.outcome, .failedLocalChecks)
    }

    func testDigestMismatchIsLocated() throws {
        let report = try inspect("hash-mismatch.zip")
        assertLocalOnly(report)
        XCTAssertTrue(report.issues.contains { issue in
            guard case .digestMismatch(let path, let actual, let declared, _, _) = issue.code else { return false }
            return path == "content.json" && actual != declared && issue.path == path
        })
        XCTAssertTrue(report.fileSummaries.contains { $0.path == "content.json" && !$0.matchesManifest })
    }

    func testH5IsRejectedAndNotAccepted() throws {
        let report = try inspect("h5.zip")
        assertLocalOnly(report)
        XCTAssertEqual(report.issues.count, 1)
        XCTAssertTrue(report.issues.contains { if case .manifest(.h5DesignOnly) = $0.code { return true }; return false })
        XCTAssertEqual(report.outcome, .failedLocalChecks)
    }

    func testJavaScriptEntryIsUnsafeAndNotExecuted() throws {
        let report = try inspect("script.zip")
        assertLocalOnly(report)
        XCTAssertTrue(report.issues.contains { issue in
            guard case .unsafeEntry("run.js") = issue.code else { return false }
            return issue.path == "run.js"
        })
        XCTAssertFalse(report.fileSummaries.contains { $0.path == "run.js" })
    }

    func testEncryptedEntryIsNotRead() throws {
        let report = try inspect("encrypted.zip")
        assertLocalOnly(report)
        XCTAssertTrue(report.issues.contains { if case .encrypted("assets/secret.bin") = $0.code { return true }; return false })
        XCTAssertFalse(report.fileSummaries.contains { $0.path == "assets/secret.bin" })
    }

    func testProposalGuardIsNotABusinessRule() throws {
        let package = try fixture("ok-stored.zip")
        let report = QmodArchiveInspection.inspect(package: package, limits: limits, expansionGuard: QmodExpansionGuard(numerator: 100, denominator: 1, isBusinessRule: true), packageLabel: "ok-stored.zip")
        assertLocalOnly(report)
        XCTAssertEqual(report.issues.map(\.code), [.proposalPresentedAsBusinessRule])
        XCTAssertTrue(report.fileSummaries.isEmpty)
        XCTAssertEqual(report.outcome, .failedLocalChecks)
        let broken = QmodArchiveInspection.inspect(package: package, limits: limits, expansionGuard: QmodExpansionGuard(numerator: 100, denominator: 0, isBusinessRule: false), packageLabel: "ok-stored.zip")
        XCTAssertEqual(broken.issues.map(\.code), [.proposalPresentedAsBusinessRule])
        XCTAssertFalse(broken.limitsAreBusinessRules)
    }

    func testUnapprovedLimitProfileCannotPass() throws {
        let profile = QmodLimitProfile(profileVersion: "pretend-official", isProposal: false, maxArchiveBytes: limits.maxArchiveBytes, maxExpandedBytes: limits.maxExpandedBytes, maxFileBytes: limits.maxFileBytes, maxFiles: limits.maxFiles, maxPathLength: limits.maxPathLength, maxDepth: limits.maxDepth)
        let report = try inspect("ok-stored.zip", limits: profile)
        assertLocalOnly(report)
        XCTAssertEqual(report.outcome, .failedLocalChecks)
        XCTAssertTrue(report.issues.contains { if case .limitProfileNotApproved("pretend-official") = $0.code { return true }; return false })
        XCTAssertTrue(report.fileSummaries.contains { $0.path == "content.json" && $0.matchesManifest })
    }

    func testArchiveOverTheCallerCeilingIsNotParsed() throws {
        let tight = QmodLimitProfile(profileVersion: "synthetic", isProposal: true, maxArchiveBytes: 16, maxExpandedBytes: limits.maxExpandedBytes, maxFileBytes: limits.maxFileBytes, maxFiles: limits.maxFiles, maxPathLength: limits.maxPathLength, maxDepth: limits.maxDepth)
        let report = try inspect("ok-stored.zip", limits: tight)
        assertLocalOnly(report)
        XCTAssertTrue(report.fileSummaries.isEmpty)
        XCTAssertTrue(report.issues.contains { if case .archiveTooLarge = $0.code { return true }; return false })
    }

    func testCancelReplaceAndRecheckDropThePreviousReport() throws {
        let firstBytes = try fixture("swap-a.zip")
        let secondBytes = try fixture("swap-b.zip")
        var session = QmodArchiveInspectionSession()
        session.select(bytes: firstBytes, label: "swap-a.zip", limits: limits, expansionGuard: expansion)
        let first = try XCTUnwrap(session.report)
        let firstGeneration = session.generation
        XCTAssertTrue(first.fileSummaries.contains { $0.path == "assets/only-a.webp" })
        XCTAssertEqual(first.outcome, .passedLocalChecks)
        session.replace(bytes: secondBytes, label: "swap-b.zip", limits: limits, expansionGuard: expansion)
        let second = try XCTUnwrap(session.report)
        XCTAssertNotEqual(session.generation, firstGeneration)
        XCTAssertEqual(second.generation, session.generation)
        XCTAssertEqual(second.packageLabel, "swap-b.zip")
        XCTAssertTrue(second.fileSummaries.contains { $0.path == "assets/only-b.webp" })
        XCTAssertFalse(second.fileSummaries.contains { $0.path == "assets/only-a.webp" })
        XCTAssertFalse(session.complete(generation: firstGeneration, report: first))
        XCTAssertEqual(session.report?.packageLabel, "swap-b.zip")
        session.cancel()
        XCTAssertNil(session.report)
        XCTAssertEqual(session.phase, .cancelled)
        XCTAssertFalse(session.canRecheck)
        XCTAssertFalse(session.complete(generation: session.generation, report: second))
        session.select(bytes: firstBytes, label: "swap-a.zip\n", limits: limits, expansionGuard: expansion)
        XCTAssertEqual(session.packageLabel, "swap-a.zip")
        XCTAssertTrue(session.canRecheck)
        let generation = session.generation
        let current = try XCTUnwrap(session.report)
        session.recheck()
        XCTAssertNotEqual(session.generation, generation)
        XCTAssertEqual(session.report?.generation, session.generation)
        XCTAssertFalse(session.complete(generation: generation, report: current))
        XCTAssertFalse(session.report?.fileSummaries.contains { $0.path == "assets/only-b.webp" } ?? true)
    }

    func testSelectingASymbolicLinkDoesNotInspectItsBytes() throws {
        let bytes = try fixture("ok-stored.zip")
        var session = QmodArchiveInspectionSession()
        session.selectLocalFile(facts: QmodLocalFileFacts(isSymbolicLink: true, isRegularFile: false, byteCount: Int64(bytes.count)), bytes: bytes, label: "link.zip", limits: limits, expansionGuard: expansion)
        let report = try XCTUnwrap(session.report)
        assertLocalOnly(report)
        XCTAssertTrue(report.issues.contains { if case .symlink("link.zip") = $0.code { return true }; return false })
        XCTAssertTrue(report.fileSummaries.isEmpty)
        XCTAssertFalse(session.canRecheck)
        session.selectLocalFile(facts: QmodLocalFileFacts(isSymbolicLink: false, isRegularFile: false, byteCount: Int64(bytes.count)), bytes: bytes, label: "dir.zip", limits: limits, expansionGuard: expansion)
        XCTAssertTrue(session.report?.issues.contains { if case .notARegularFile("dir.zip") = $0.code { return true }; return false } ?? false)
        XCTAssertNil(session.report?.manifestPackageId)
        session.selectLocalFile(facts: QmodLocalFileFacts(isSymbolicLink: false, isRegularFile: true, byteCount: Int64(bytes.count)), bytes: Data(bytes.dropLast()), label: "short.zip", limits: limits, expansionGuard: expansion)
        XCTAssertTrue(session.report?.issues.contains { if case .localFileUnreadable("short.zip") = $0.code { return true }; return false } ?? false)
        XCTAssertTrue(session.report?.fileSummaries.isEmpty ?? false)
    }
}
