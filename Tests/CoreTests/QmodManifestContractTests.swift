import XCTest
@testable import QuestifyCore

final class QmodManifestContractTests: XCTestCase {
    private let h = String(repeating: "e", count: 64)
    private func manifest(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var root: [String: Any] = [
            "formatVersion": "1.0", "kind": "questify.mod", "packageId": "bookshop.mystery", "packageVersion": "1.2.0",
            "entrypoint": "content.json", "locales": ["zh-Hans", "en"],
            "runtime": ["minHostVersion": "1.0.0", "capabilities": ["choice", "geo.arrival"]],
            "dependencies": [["packageId": "common.npc", "version": "2.0.1", "contentHash": h]],
            "files": [["path": "content.json", "sha256": h, "bytes": 1200], ["path": "zh-Hans.json", "sha256": h, "bytes": 300],
                      ["path": "en.json", "sha256": h, "bytes": 300], ["path": "assets/cover.webp", "sha256": h, "bytes": 4000]],
            "rightsDeclaration": ["declared": true], "monetizationDeclaration": "NONE"
        ]
        edit(&root)
        return try JSONSerialization.data(withJSONObject: root)
    }
    private let limits = QmodLimitProfile.reviewProposalV1

    func testDuplicateManifestKeysAreRejectedBeforeFoundationSelectsAValue() throws {
        let valid = try XCTUnwrap(String(data: manifest(), encoding: .utf8))
        for inserted in [#""kind":"questify.h5","#,
                         #""ki\u006ed":"questify.h5","#,
                         #""approved":false,"approved":true,"#] {
            let bytes = Data(("{" + inserted + valid.dropFirst()).utf8)
            XCTAssertThrowsError(try QmodManifest(data: bytes, limits: limits)) {
                XCTAssertEqual($0 as? QmodManifestIssue, .malformed)
            }
        }
    }

    func testJSONDuplicateCheckDecodesKeysAndKeepsObjectScopesSeparate() throws {
        for text in [#"{"a":1,"\u0061":2}"#,
                     #"{"nested":[{"answer":1,"answer":2}]}"#,
                     #"{"😀":1,"\ud83d\ude00":2}"#] {
            XCTAssertThrowsError(try QmodJSONInspection.validate(Data(text.utf8))) {
                XCTAssertEqual($0 as? QmodJSONInspection.Failure, .duplicateKey)
            }
        }
        for text in [#"[{"same":1},{"same":2}]"#,
                     #"{"quoted":"\"key\":1,\"key\":2","n":-1.25e+3,"b":true,"a":[false,null]}"#,
                     #"{"a":{},"b":[],"c":"反斜杠\\与中文"}"#] {
            XCTAssertNoThrow(try QmodJSONInspection.validate(Data(text.utf8)))
        }
    }

    func testJSONSyntaxAndRecursionStopBeforeDecoding() {
        for text in [#"{"a":1,}"#, #"[1,]"#, #"{"a":01}"#, #"{"a":1e}"#,
                     #"{"a":+1}"#, #"{"a":"\q"}"#, #"{"a":"\ud800"}"#,
                     #"{"a":true false}"#, "{}{}", "", "[", "{\"a\":\"\n\"}"] {
            XCTAssertThrowsError(try QmodJSONInspection.validate(Data(text.utf8)), text)
        }
        XCTAssertThrowsError(try QmodJSONInspection.validate(Data([123, 34, 255, 34, 58, 48, 125])))
        let nested = String(repeating: "[", count: 66) + "0" + String(repeating: "]", count: 66)
        XCTAssertThrowsError(try QmodJSONInspection.validate(Data(nested.utf8))) {
            XCTAssertEqual($0 as? QmodJSONInspection.Failure, .depthExceeded)
        }
    }

    func testValidManifestParsesAndProposalProfileIsLabelled() throws {
        let value = try QmodManifest(data: manifest(), limits: limits)
        XCTAssertEqual(value.packageId, "bookshop.mystery"); XCTAssertEqual(value.dependencies.count, 1); XCTAssertEqual(value.files.count, 4)
        XCTAssertTrue(limits.isProposal)
        XCTAssertNoThrow(try value.verify(path: "en.json", sha256: h, bytes: 300))
        XCTAssertThrowsError(try value.verify(path: "en.json", sha256: h, bytes: 301)) { XCTAssertEqual($0 as? QmodManifestIssue, .digestMismatch("en.json")) }
        XCTAssertThrowsError(try value.verify(path: "extra.json", sha256: h, bytes: 1))
    }

    func testH5StaysDesignOnlyAndAuthorityFieldsAreRejected() throws {
        XCTAssertThrowsError(try QmodManifest(data: manifest { $0["kind"] = "questify.h5" }, limits: limits)) { XCTAssertEqual($0 as? QmodManifestIssue, .h5DesignOnly) }
        XCTAssertThrowsError(try QmodManifest(data: manifest { $0["approved"] = true }, limits: limits)) { XCTAssertEqual($0 as? QmodManifestIssue, .authorityField("approved")) }
        XCTAssertThrowsError(try QmodManifest(data: manifest { $0["rewardBudget"] = 1 }, limits: limits)) { XCTAssertEqual($0 as? QmodManifestIssue, .authorityField("rewardBudget")) }
        XCTAssertThrowsError(try QmodManifest(data: manifest { $0["script"] = "x" }, limits: limits)) { XCTAssertEqual($0 as? QmodManifestIssue, .malformed) }
    }

    func testUnsafePathsAreRejected() throws {
        for path in ["../x.json", "/abs.json", "a\\b.json", "a//b.json", ".hidden", "ui/index.html", "logo.svg", "run.js", "nested.zip", "a/b/c/d/e/f/g/h/i.json"] {
            XCTAssertThrowsError(try QmodManifest(data: manifest { root in
                var files = root["files"] as! [[String: Any]]; files.append(["path": path, "sha256": self.h, "bytes": 1]); root["files"] = files
            }, limits: limits), path)
        }
    }

    func testDuplicateCaseFoldedPathsAndBooleanSizesAreRejected() throws {
        XCTAssertThrowsError(try QmodManifest(data: manifest { root in
            var files = root["files"] as! [[String: Any]]; files.append(["path": "Content.json", "sha256": self.h, "bytes": 1]); root["files"] = files
        }, limits: limits)) { XCTAssertEqual($0 as? QmodManifestIssue, .duplicatePath("Content.json")) }
        XCTAssertThrowsError(try QmodManifest(data: manifest { root in
            var files = root["files"] as! [[String: Any]]; files.append(["path": "flag.json", "sha256": self.h, "bytes": true]); root["files"] = files
        }, limits: limits))
    }

    func testVersionsLocalesDependenciesAndSizeLimits() throws {
        XCTAssertThrowsError(try QmodManifest(data: manifest { $0["packageVersion"] = "1.2" }, limits: limits)) { XCTAssertEqual($0 as? QmodManifestIssue, .invalidVersion) }
        XCTAssertThrowsError(try QmodManifest(data: manifest { $0["packageVersion"] = "01.2.0" }, limits: limits))
        XCTAssertThrowsError(try QmodManifest(data: manifest { $0["locales"] = ["fr"] }, limits: limits)) { XCTAssertEqual($0 as? QmodManifestIssue, .invalidLocale) }
        XCTAssertThrowsError(try QmodManifest(data: manifest { $0["dependencies"] = [["packageId": "common.npc", "version": "latest", "contentHash": self.h]] }, limits: limits)) { XCTAssertEqual($0 as? QmodManifestIssue, .invalidDependency) }
        XCTAssertThrowsError(try QmodManifest(data: manifest { $0["dependencies"] = [["packageId": "bookshop.mystery", "version": "1.0.0", "contentHash": self.h]] }, limits: limits))
        XCTAssertThrowsError(try QmodManifest(data: manifest { $0["entrypoint"] = "https://example.invalid/x.json" }, limits: limits)) { XCTAssertEqual($0 as? QmodManifestIssue, .invalidEntrypoint) }
        let tight = QmodLimitProfile(profileVersion: "synthetic", isProposal: true, maxArchiveBytes: 10_000, maxExpandedBytes: 5_000, maxFileBytes: 3_000, maxFiles: 10, maxPathLength: 200, maxDepth: 8)
        XCTAssertThrowsError(try QmodManifest(data: manifest(), limits: tight)) { XCTAssertEqual($0 as? QmodManifestIssue, .fileTooLarge("assets/cover.webp", actual: 4000, limit: 3000)) }
        XCTAssertThrowsError(try QmodManifest(data: manifest { root in
            var files = root["files"] as! [[String: Any]]; files.removeAll { ($0["path"] as? String) == "en.json" }; root["files"] = files
        }, limits: limits)) { XCTAssertEqual($0 as? QmodManifestIssue, .missingFile("en.json")) }
    }
}
