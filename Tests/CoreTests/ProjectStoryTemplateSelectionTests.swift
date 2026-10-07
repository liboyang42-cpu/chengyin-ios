import Foundation
import XCTest
@testable import QuestifyCore

/// These fixtures deliberately do not depend on DEBUG-only synthetic production helpers.
@MainActor final class ProjectStoryTemplateSelectionTests: XCTestCase {
    private let session = try! ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "story-template-core")
    private let identity = try! ProjectEditDraftIdentity(topicID: 101)
    private let templateID = MemberPlayTemplateID(rawValue: 41)!
    private final class Storage: ProjectEditDataStorage {
        var values: [String: Data] = [:]
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { values[key] = data }
        func remove(_ key: String) throws { values[key] = nil }
    }
    private func draft() -> ProjectEditDraft {
        var value = ProjectEditDraft(); value.baseRevision = "r1"
        value.name = "Harbor"; value.description = "Story"; value.imgUrl = "https://example.com/cover.jpg"
        value.categoryIDs = [7]; value.startDate = "2030-05-01"; value.endDate = "2030-05-30"
        var chapter = ProjectEditChapter(); chapter.name = "Chapter"; chapter.description = "Opening text"
        var node = ProjectEditNode(); node.name = "Existing place"; node.templateID = 11; node.longitude = "121.5"; node.latitude = "31.2"
        node.localMetadata = ["keep": .string("e\u{301}")]
        chapter.nodes = [node]
        chapter.blocks = [.init(kind: .text, content: "Opening text"), .init(kind: .node, nodeID: node.id), .init(kind: .text, content: "Tail")]
        value.chapters = [chapter]
        var pending = ProjectEditNode(); pending.name = "Pending"; pending.templateID = 77
        pending.localMetadata = ["secret": .string("local-only")]; value.pendingMaterials = [.init(node: pending)]
        value.preserved["futureLocalField"] = .object(["keep": .null])
        return value
    }
    private func fields() -> [String: ProjectEditJSON] {
        ["id": .number(41), "memberId": .number(7), "draftStatus": .number(0), "delFlag": .number(0),
         "title": .string("My saved game"), "validationMethod": .number(0), "answer": .string("never copy this"), "revision": .string("r1")]
    }
    private func image(_ url: String = "https://example.com/e%CC%81.jpg?order=1", line: ProjectEditJSON? = .string("e\u{301}")) -> ProjectEditJSON {
        var value: [String: ProjectEditJSON] = ["url": .string(url)]; value["line"] = line; return .object(value)
    }
    private func albumFields(title: String = "Album", images: [ProjectEditJSON]? = nil,
                             extra: [String: ProjectEditJSON] = [:]) throws -> [String: ProjectEditJSON] {
        var value = fields(), config = extra
        config["schemaVersion"] = .number(1); config["album"] = .object(["enabled": .bool(true), "images": .array(images ?? [image()])])
        value["title"] = .string(title); value["advancedConfigJson"] = .string(String(decoding: try JSONEncoder().encode(config), as: UTF8.self))
        return value
    }
    private func selected(_ value: [String: ProjectEditJSON]? = nil) throws -> ProjectStoryTemplateDraft {
        try .decode(.object(value ?? fields()), accountID: 7, requestedID: templateID)
    }
    private func target(_ value: ProjectEditDraft, before: String? = nil) throws -> ProjectStoryTemplateTarget {
        try .init(draft: value, identity: identity, session: session, chapterID: value.chapters[0].id, before: before)
    }
    private func apply(_ selected: ProjectStoryTemplateDraft, to value: ProjectEditDraft, before: String? = nil) throws -> ProjectEditDraft {
        try target(value, before: before).applying(selected, to: value, identity: identity, session: session)
    }
    func testOrdinaryAndAlbumInsertAtFirstMiddleAndEndWithoutChangingExistingBytes() throws {
        for album in [false, true] {
            let selection = try selected(album ? albumFields() : fields())
            for index in [0, 1, 3] {
                let original = draft(), old = try XCTUnwrap(original.chapters[0].blocks)
                let exact = ProjectEditPendingMaterials.exactData(original)
                let next = try apply(selection, to: original, before: index < old.count ? old[index].id : nil)
                let blocks = try XCTUnwrap(next.chapters[0].blocks), inserted = blocks[index]
                XCTAssertEqual(blocks.count, old.count + 1)
                XCTAssertEqual(blocks.filter { $0.id != inserted.id }, old)
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(original), exact, "Preview must be immutable")
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(next.pendingMaterials), ProjectEditPendingMaterials.exactData(original.pendingMaterials))
                var restored = next; restored.chapters[0].blocks?.remove(at: index)
                if album {
                    XCTAssertEqual(inserted.kind, .dream); XCTAssertTrue(inserted.nodeID.isEmpty)
                    XCTAssertEqual(inserted.sourceFields, ["title": .string("Album"), "images": .array([image()])])
                    XCTAssertEqual(next.chapters[0].nodes, original.chapters[0].nodes)
                } else {
                    XCTAssertEqual(inserted.kind, .node); XCTAssertEqual(inserted.sourceFields, ["locationRequired": .bool(false)])
                    let node = try XCTUnwrap(next.chapters[0].nodes.first { $0.id == inserted.nodeID })
                    XCTAssertEqual(node.templateID, 41); XCTAssertEqual(node.name, selection.row.title)
                    XCTAssertTrue(node.longitude.isEmpty && node.latitude.isEmpty && node.description.isEmpty && node.address.isEmpty && node.imgUrl.isEmpty)
                    XCTAssertTrue(node.localMetadata.isEmpty); XCTAssertEqual(next.chapters[0].nodes.count, original.chapters[0].nodes.count + 1)
                    restored.chapters[0].nodes.removeAll { $0.id == inserted.nodeID }
                }
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(restored), exact)
            }
        }
    }
    func testLocalSaveAndColdReadPreserveExactProjectionAndPendingMaterials() throws {
        for album in [false, true] {
            let original = draft(), next = try apply(selected(album ? albumFields() : fields()), to: original, before: original.chapters[0].blocks?[1].id)
            let storage = Storage(); try ProjectEditLocalStore(storage: storage).save(next, session: session, identity: identity)
            guard case .ready(let restored) = ProjectEditLocalStore(storage: storage).load(session: session, identity: identity, baseline: original) else { return XCTFail("Expected a cold local restore") }
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(restored.draft), ProjectEditPendingMaterials.exactData(next))
            XCTAssertEqual(restored.draft.pendingMaterials, original.pendingMaterials)
        }
    }
    func testStaleDeletedMovedReplacedAndForeignGapCannotFallBackToAppend() throws {
        let original = draft(), anchor = try XCTUnwrap(original.chapters[0].blocks?[1].id), captured = try target(original, before: anchor), choice = try selected()
        for mutation in 0..<6 {
            var changed = original
            switch mutation {
            case 0: changed.chapters[0].blocks?.remove(at: 1)
            case 1: changed.chapters[0].blocks?.swapAt(0, 1)
            case 2: changed.chapters[0].blocks?[1].content = "same ID, new content"
            case 3: changed.name = "Unrelated draft edit also retires review"
            case 4: changed.pendingMaterials?[0].node.name = "Pending edit"
            default: changed.chapters.removeAll()
            }
            XCTAssertThrowsError(try captured.applying(choice, to: changed, identity: identity, session: session))
        }
        XCTAssertThrowsError(try target(original, before: "missing"))
        XCTAssertThrowsError(try captured.applying(choice, to: original, identity: .init(topicID: 102), session: session))
        let foreign = try ProjectEditSession(accountID: 8, epoch: 1, storageNamespace: session.storageNamespace)
        XCTAssertThrowsError(try captured.applying(choice, to: original, identity: identity, session: foreign))
        let applied = try captured.applying(choice, to: original, identity: identity, session: session)
        XCTAssertThrowsError(try captured.applying(choice, to: applied, identity: identity, session: session), "Applying the captured gap twice cannot duplicate it")
    }
    func testCapacityAllows199To200AndRefusesFullChapter() throws {
        for album in [false, true] {
            var original = draft(); original.chapters[0].nodes = []
            original.chapters[0].blocks = (0..<199).map { .init(kind: .text, content: "Block \($0)") }
            let full = try apply(selected(album ? albumFields() : fields()), to: original)
            XCTAssertEqual(full.chapters[0].blocks?.count, 200)
            XCTAssertThrowsError(try target(full))
        }
    }
    func testDuplicateChapterNodeBlockIDsAndUnresolvedReferencesFailClosed() throws {
        for mutation in 0..<7 {
            var value = draft()
            switch mutation {
            case 0: value.chapters.append(value.chapters[0])
            case 1: value.chapters[0].nodes.append(value.chapters[0].nodes[0])
            case 2: value.chapters[0].blocks?.append(try XCTUnwrap(value.chapters[0].blocks?.first))
            case 3: value.chapters[0].blocks?.append(.init(kind: .node, nodeID: value.chapters[0].nodes[0].id))
            case 4: value.chapters[0].blocks?[1].nodeID = "missing"
            case 5: value.chapters[0].nodes[0].id = ""
            default:
                var other = ProjectEditChapter(); other.blocks = [try XCTUnwrap(value.chapters[0].blocks?.first)]
                value.chapters.append(other)
            }
            XCTAssertThrowsError(try target(value), "Mutation \(mutation)")
        }
    }
    func testOnlyPersonalCitySupportedSchemaAndRequiredChapterAreEligible() throws {
        for mutation in 0..<5 {
            var value = draft()
            switch mutation {
            case 0: value.owner = .merchant
            case 1: value.product = .freeExplore
            case 2: value.chapters[0].schemaVersion = 2
            case 3: value.chapters[0].required = 0
            default: value.chapters[0].blocks = nil
            }
            XCTAssertThrowsError(try target(value))
        }
    }
    func testDraftRowsRejectForeignPublishedDeletedPublicAndMalformedIdentities() throws {
        let valid = fields()
        XCTAssertNoThrow(try selected(valid))
        for (key, invalid) in [("memberId", ProjectEditJSON.number(8)), ("draftStatus", .number(1)), ("delFlag", .number(1)),
                               ("id", .number(0)), ("id", .number(42)), ("id", .string("41")), ("memberId", .null), ("draftStatus", .null), ("title", .string("  "))] {
            var value = valid; value[key] = invalid; XCTAssertThrowsError(try selected(value), key)
        }
        var publicOnly = valid; publicOnly["memberId"] = nil; publicOnly["publicTemplateId"] = .number(41)
        XCTAssertThrowsError(try selected(publicOnly))
        var missingDeletion = valid; missingDeletion["delFlag"] = nil
        XCTAssertNoThrow(try ProjectStoryTemplateRow.decode(.object(missingDeletion), accountID: 7))
        XCTAssertThrowsError(try selected(missingDeletion), "List omission is not detail ownership/deletion evidence")
    }
    func testOrdinaryMethodsRequireExplicitSupportedNonArrivalMethod() throws {
        for method in [0, 1, 2, 3, 6, 7] {
            var value = fields(); value["validationMethod"] = .number(Decimal(method))
            XCTAssertEqual(try selected(value).content, .gameplay)
        }
        for method in [ProjectEditJSON.number(4), .number(5), .number(8), .number(-1), .string("0"), .null, .bool(false)] {
            var value = fields(); value["validationMethod"] = method; XCTAssertThrowsError(try selected(value))
        }
        var missing = fields(); missing["validationMethod"] = nil; XCTAssertThrowsError(try selected(missing))
        var album = try albumFields(); album["validationMethod"] = .number(4)
        if case .album = try selected(album).content {} else { XCTFail("Album display does not create an arrival node") }
    }
    func testAdvancedMissingNullAndEmptyRemainSafeButExactSourceComparisonDistinguishesThem() throws {
        let absent = try selected(); var value = fields(); value["advancedConfigJson"] = .null
        let null = try selected(value); value["advancedConfigJson"] = .string(""); let empty = try selected(value)
        XCTAssertEqual(absent.content, .gameplay); XCTAssertEqual(null.content, .gameplay); XCTAssertEqual(empty.content, .gameplay)
        XCTAssertNotEqual(absent, null); XCTAssertNotEqual(null, empty)
        for invalid in [ProjectEditJSON.object([:]), .number(1), .string("not JSON"), .string("{}"), .string(#"{"schemaVersion":2}"#), .string(#"{"schemaVersion":1,"future":{}}"#), .string(#"{"schemaVersion":1,"album":null}"#)] {
            value["advancedConfigJson"] = invalid; XCTAssertThrowsError(try selected(value))
        }
    }
    func testAlbumRejectsMixedActiveConfigurationAndUnknownImageFields() throws {
        XCTAssertThrowsError(try selected(albumFields(extra: ["timer": .object(["enabled": .bool(true), "durationSeconds": .number(300)])])))
        XCTAssertNoThrow(try selected(albumFields(extra: ["timer": .object(["enabled": .bool(false)])])))
        var badImage = try XCTUnwrap(image().object); badImage["future"] = .bool(true)
        XCTAssertThrowsError(try selected(albumFields(images: [.object(badImage)])))
        for invalid in [ProjectEditJSON.null, .object([:]), .object(["url": .null]), .object(["url": .string("http://example.com/x")]), .object(["url": .string("https://example.com/x"), "line": .number(1)])] {
            XCTAssertThrowsError(try selected(albumFields(images: [invalid])))
        }
    }
    func testAlbumRejectsRootBehaviorAndMalformedEnabledFlagsRatherThanDroppingThem() throws {
        let mixed: [[String: ProjectEditJSON]] = [
            ["mistakeTier": .string("easy")], ["variants": .array([])],
            ["roleViews": .object(["enabled": .bool(false)])],
            ["timer": .object(["enabled": .string("true")])],
            ["timer": .object(["enabled": .number(1)])],
            ["timer": .object(["durationSeconds": .number(300)])]
        ]
        for extra in mixed {
            XCTAssertThrowsError(try selected(albumFields(extra: extra)))
        }
        for flag in [ProjectEditJSON.null, .number(1), .string("true")] {
            var value = fields()
            let config: [String: ProjectEditJSON] = ["schemaVersion": .number(1), "album": .object(["enabled": flag, "images": .array([image()])])]
            value["advancedConfigJson"] = .string(String(decoding: try JSONEncoder().encode(config), as: UTF8.self))
            XCTAssertThrowsError(try selected(value))
        }
    }
    func testAlbumImageCountAndUTF16TitleURLAndCaptionBoundaries() throws {
        for count in 1...6 { XCTAssertNoThrow(try selected(albumFields(images: Array(repeating: image(), count: count)))) }
        for count in [0, 7] { XCTAssertThrowsError(try selected(albumFields(images: Array(repeating: image(), count: count)))) }
        XCTAssertNoThrow(try selected(albumFields(title: String(repeating: "🧭", count: 10))))
        XCTAssertThrowsError(try selected(albumFields(title: String(repeating: "🧭", count: 10) + "x")))
        let prefix = "https://example.com/"
        let atLimit = prefix + String(repeating: "x", count: 500 - prefix.utf16.count)
        XCTAssertNoThrow(try selected(albumFields(images: [image(atLimit)])))
        XCTAssertThrowsError(try selected(albumFields(images: [image(atLimit + "x")])))
        XCTAssertNoThrow(try selected(albumFields(images: [image(line: .string(String(repeating: "🧭", count: 20)))])))
        XCTAssertThrowsError(try selected(albumFields(images: [image(line: .string(String(repeating: "🧭", count: 20) + "x"))])))
        XCTAssertNoThrow(try selected(albumFields(images: [image(line: nil)])))
        // Safe missing/null captions stay distinct in the adopted source fields.
        let nullImage = image(line: .null), nullAlbum = try selected(albumFields(images: [nullImage]))
        let applied = try apply(nullAlbum, to: draft())
        XCTAssertEqual(applied.chapters[0].blocks?.last?.sourceFields?["images"], .array([nullImage]))
    }
    func testInnerAdvancedJSONRejectsDuplicateKeysBeforeBothTypedDecoders() throws {
        let album = #"{"enabled":true,"images":[{"url":"https://example.com/x"}]}"#
        let rawValues = [
            #"{"schemaVersion":1,"schemaVersion":2}"#,
            #"{"schemaVersion":1,"album":ALBUM,"album":{"enabled":false}}"#.replacingOccurrences(of: "ALBUM", with: album),
            #"{"schemaVersion":1,"album":{"enabled":true,"enabled":false,"images":[{"url":"https://example.com/x"}]}}"#,
            #"{"schemaVersion":1,"album":{"enabled":false,"enabled":true,"images":[{"url":"https://example.com/x"}]}}"#,
            #"{"schemaVersion":1,"album":ALBUM,"timer":{"enabled":false,"enabled":true,"durationSeconds":300}}"#.replacingOccurrences(of: "ALBUM", with: album),
            #"{"schemaVersion":1,"album":ALBUM,"timer":{"enabled":true,"enabled":false,"durationSeconds":300}}"#.replacingOccurrences(of: "ALBUM", with: album),
            #"{"schemaVersion":1,"album":{"enabled":true,"images":[{"url":"https://example.com/x","url":"https://example.com/y"}]}}"#,
            #"{"schemaVersion":1,"album":{"enabled":true,"images":[{"url":"https://example.com/x","line":"a","line":"b"}]}}"#
        ]
        for raw in rawValues {
            var value = fields(); value["advancedConfigJson"] = .string(raw)
            XCTAssertThrowsError(try selected(value), raw) { XCTAssertEqual($0 as? ProjectStoryTemplateError, .unsupported) }
        }
    }
    func testInnerAdvancedJSONRejectsEscapedAliasesButAcceptsOneEscapedKey() throws {
        let invalid = [
            #"{"schemaVersion":1,"album":{"enabled":true,"enabl\u0065d":false,"images":[{"url":"https://example.com/x"}]}}"#,
            #"{"schemaVersion":1,"album":{"enabled":true,"images":[{"url":"https://example.com/x","u\u0072l":"https://example.com/y"}]}}"#,
            #"{"schemaVersion":1,"album":{"enabled":true,"images":[{"url":"https://example.com/x"}]},"alb\u0075m":{"enabled":false}}"#,
            #"{"schemaVersion":1,"album":{"enabled":true,"images":[{"url":"https://example.com/x"}]},"timer":{"enabled":false,"enabl\u0065d":true,"durationSeconds":300}}"#
        ]
        for raw in invalid {
            var value = fields(); value["advancedConfigJson"] = .string(raw)
            XCTAssertThrowsError(try selected(value)) { XCTAssertEqual($0 as? ProjectStoryTemplateError, .unsupported) }
        }
        var valid = fields(); valid["advancedConfigJson"] = .string(#"{"schemaVersion":1,"alb\u0075m":{"enabl\u0065d":true,"images":[{"u\u0072l":"https://example.com/x"}]}}"#)
        if case .album(let images) = try selected(valid).content { XCTAssertEqual(images, [.object(["url": .string("https://example.com/x")])]) }
        else { XCTFail("One escaped spelling is a valid JSON key, not a duplicate") }
    }
    func testInnerAdvancedJSONHasBoundedSizeDepthStringAndAtomPreflight() throws {
        let excessiveDepth = String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33)
        let rawValues = [
            String(repeating: " ", count: 262_145),
            #"{"schemaVersion":1,"future":VALUE}"#.replacingOccurrences(of: "VALUE", with: excessiveDepth),
            #"{"schemaVersion":1,"future":"VALUE"}"#.replacingOccurrences(of: "VALUE", with: String(repeating: "x", count: 96 * 1024 + 1)),
            #"{"schemaVersion":1,"future":VALUE}"#.replacingOccurrences(of: "VALUE", with: String(repeating: "1", count: 129)),
            #"{"schemaVersion":1} trailing"#
        ]
        for raw in rawValues {
            var value = fields(); value["advancedConfigJson"] = .string(raw)
            XCTAssertThrowsError(try selected(value)) { XCTAssertEqual($0 as? ProjectStoryTemplateError, .unsupported) }
        }
        // The shared parser is tested directly as well, independent of unknown-field rejection.
        XCTAssertThrowsError(try ApprovedTopicReleaseWire.envelope(Data(rawValues[1].utf8)))
        XCTAssertThrowsError(try ApprovedTopicReleaseWire.envelope(Data(rawValues[2].utf8)))
        XCTAssertThrowsError(try ApprovedTopicReleaseWire.envelope(Data(rawValues[3].utf8)))
    }
    func testSourceSnapshotComparisonDetectsInvisibleChangesAndCanonicalUnicodeDifferences() throws {
        let original = try selected(); var value = fields(); value["answer"] = .string("changed private answer")
        XCTAssertEqual(try selected(value).row, original.row); XCTAssertNotEqual(try selected(value), original)
        value = fields(); value["revision"] = .null; XCTAssertNotEqual(try selected(value), original)
        var a = fields(), b = fields(); a["title"] = .string("é"); b["title"] = .string("e\u{301}")
        XCTAssertNotEqual(try selected(a).row, try selected(b).row)
        XCTAssertNotEqual(try selected(a), try selected(b))
    }
    func testPageRejectsDuplicateIDsForeignRowsAndInconsistentPagination() throws {
        let row = ProjectEditJSON.object(fields())
        func decode(_ rows: [ProjectEditJSON], total: Int, page: Int = 1) throws -> ProjectStoryTemplatePage {
            try .decode(.object(["rows": .array(rows), "total": .number(Decimal(total))]), accountID: 7, page: page)
        }
        XCTAssertEqual(try decode([row], total: 1).rows.count, 1); XCTAssertNil(try decode([], total: 0).nextPage)
        XCTAssertThrowsError(try decode([row, row], total: 2))
        XCTAssertThrowsError(try decode([row], total: 2)); XCTAssertThrowsError(try decode([row], total: 0))
        XCTAssertThrowsError(try decode([], total: 0, page: 0)); XCTAssertThrowsError(try decode([], total: 0, page: 51))
        let rows: [ProjectEditJSON] = (1...20).map { id in var value = fields(); value["id"] = .number(Decimal(id)); return .object(value) }
        XCTAssertEqual(try decode(rows, total: 21).nextPage, 2)
        XCTAssertNil(try decode([row], total: 21, page: 2).nextPage)
        XCTAssertThrowsError(try decode(rows + [row], total: 21))
        var foreign = fields(); foreign["memberId"] = .number(8); XCTAssertThrowsError(try decode([.object(foreign)], total: 1))
    }
    func testOpeningMustBeFirstWithoutRecruitmentAndAllGamesMustBeLocationFree() throws {
        var opening = draft(); opening.chapters[0].preserved["opening"] = .bool(true)
        opening.chapters[0].nodes = []; opening.chapters[0].blocks = [.init(kind: .text, content: "Welcome")]
        let applied = try apply(selected(), to: opening)
        XCTAssertEqual(applied.chapters[0].blocks?.last?.sourceFields?["locationRequired"], .bool(false))
        XCTAssertTrue(try XCTUnwrap(applied.chapters[0].nodes.first).longitude.isEmpty)
        XCTAssertNoThrow(try target(applied))
        var misplaced = opening; misplaced.chapters.insert(ProjectEditChapter(), at: 0)
        XCTAssertThrowsError(try ProjectStoryTemplateTarget(draft: misplaced, identity: identity, session: session, chapterID: opening.chapters[0].id, before: nil))
        var recruit = opening; recruit.chapters[0].preserved["recruitEnabled"] = .number(1); XCTAssertThrowsError(try target(recruit))
        var located = applied; located.chapters[0].nodes[0].longitude = "121"; XCTAssertThrowsError(try target(located))
        var missingFlag = applied; missingFlag.chapters[0].blocks?[1].sourceFields = nil; XCTAssertThrowsError(try target(missingFlag))
    }
    func testEndingAllowsAlbumOnlyAndNeverAddsNodesOrRecruitment() throws {
        var ending = draft(); ending.chapters[0].preserved["ending"] = .object(["fallback": .bool(true)])
        ending.chapters[0].nodes = []; ending.chapters[0].blocks = [.init(kind: .text, content: "Goodbye")]
        XCTAssertThrowsError(try apply(selected(), to: ending))
        let applied = try apply(selected(albumFields()), to: ending)
        XCTAssertTrue(applied.chapters[0].nodes.isEmpty); XCTAssertEqual(applied.chapters[0].blocks?.last?.kind, .dream)
        var invalid = ending; invalid.chapters[0].preserved["recruitEnabled"] = .number(1); XCTAssertThrowsError(try target(invalid))
        invalid = ending; invalid.chapters[0].nodes = draft().chapters[0].nodes; XCTAssertThrowsError(try target(invalid))
        invalid = ending; invalid.chapters[0].preserved["ending"] = .object(["fallback": .bool(false), "when": .array([])])
        XCTAssertThrowsError(try target(invalid))
    }
    func testExistingPlaceCoordinateValidationRemainsIndependentOfInsertedStoryGame() throws {
        let original = draft(), next = try apply(selected(), to: original), existingID = original.chapters[0].nodes[0].id
        let inserted = try XCTUnwrap(next.chapters[0].nodes.last)
        XCTAssertFalse(ProjectEditValidation.issues(next).contains { $0.id == "coordinate" + inserted.id })
        var invalid = next; invalid.chapters[0].nodes[0].longitude = ""; invalid.chapters[0].nodes[0].latitude = ""
        XCTAssertTrue(ProjectEditValidation.issues(invalid).contains { $0.id == "coordinate" + existingID })
        XCTAssertFalse(ProjectEditValidation.issues(invalid).contains { $0.id == "coordinate" + inserted.id })
        XCTAssertNil(invalid.chapters[0].blocks?[1].sourceFields?["locationRequired"])
    }
}
