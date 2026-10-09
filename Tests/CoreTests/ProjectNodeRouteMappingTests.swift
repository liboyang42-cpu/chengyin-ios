import XCTest
@testable import QuestifyCore

final class ProjectNodeRouteMappingTests: XCTestCase {
    private let graph = #"{ "schemaVersion":1,"startNodeId":1,"terminalNodeIds":[4],"variables":{"score":0},"edges":[{"id":"a","fromNodeId":1,"toNodeId" : 2,"trigger":{"type":"CHOICE","outcomeCode":"COMPLETED"},"conditions":[{"op":"HAS_TAG","value":"tag.start"}],"effects":[{"op":"INC","var":"score","value":1}],"priority":3,"weight":7,"once":false,"allowLoop":false,"maxVisits":1},{"id":"b","fromNodeId":2,"toNodeId":3,"trigger":{"type":"CHOICE","outcomeCode":"COMPLETED"}},{"id":"c","fromNodeId":3,"toNodeId":4,"trigger":{"type":"CHOICE","outcomeCode":"COMPLETED"}}],"fallbacks":[{"fromNodeId":1,"toNodeId":2}],"nodeRequirements":[] }"#
    private func draft(_ raw: String? = nil) -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.preserved["publishMode"] = .string("pro")
        draft.preserved["routeMode"] = .string("BRANCH_GRAPH"); draft.preserved["routeGraphJson"] = .string(raw ?? graph)
        draft.chapters[0].id = "chapter"
        draft.chapters[0].nodes = (1...4).map { id in
            var node = ProjectEditNode(); node.id = "node\(id)"; node.name = "Node \(id)"; node.templateID = 40 + id
            node.localMetadata = ["id": .number(Decimal(id)), "templateInfo": .object(["id": .number(Decimal(40 + id)), "validationMethod": .number(0)])]
            return node
        }
        return draft
    }
    private func mapping(_ draft: ProjectEditDraft, nodeID: String = "node1") -> ProjectNodeRouteMapping { .init(draft: draft, chapterID: "chapter", nodeID: nodeID) }
    private func rewrite(_ draft: ProjectEditDraft, _ edit: (inout [String: ProjectEditJSON]) -> Void) throws -> ProjectEditDraft {
        var root = try ApprovedTopicReleaseWire.envelope(Data(draft.preserved["routeGraphJson"]!.text!.utf8)); edit(&root)
        var next = draft; next.preserved["routeGraphJson"] = .string(String(data: ProjectEditPendingMaterials.exactData(root)!, encoding: .utf8)!); return next
    }
    func testReplacementChangesOneTokenAndPreservesEveryOtherByteAndField() throws {
        let original = draft(), projection = mapping(original)
        XCTAssertNil(projection.reason); XCTAssertEqual(projection.rows.map(\.id), ["a"])
        let next = try projection.applying(edgeID: "a", targetID: 3, to: original)
        var expected = original; expected.preserved["routeGraphJson"] = .string(graph.replacingOccurrences(of: #""toNodeId" : 2"#, with: #""toNodeId" : 3"#))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next.chapters), ProjectEditPendingMaterials.exactData(original.chapters))
    }
    func testNoOpKeepsRawWhitespaceNumericSpellingAndEscapedKeyExactly() throws {
        let raw = graph.replacingOccurrences(of: #""toNodeId" : 2"#, with: #""\u0074oNodeId" : "2""#)
        let original = draft(raw), projection = mapping(original)
        XCTAssertNil(projection.reason)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try projection.applying(edgeID: "a", targetID: 2, to: original)), ProjectEditPendingMaterials.exactData(original))
        let changed = try projection.applying(edgeID: "a", targetID: 3, to: original)
        XCTAssertEqual(changed.preserved["routeGraphJson"]?.text, raw.replacingOccurrences(of: #""\u0074oNodeId" : "2""#, with: #""\u0074oNodeId" : "3""#))
    }
    func testUnsavedDuplicateAndAmbiguousLocalOrServerIdentitiesAreReadOnly() {
        for mutation in ["unsaved", "server", "local", "chapter", "wrongChapter"] {
            var value = draft()
            switch mutation {
            case "unsaved": value.chapters[0].nodes[1].localMetadata["id"] = nil
            case "server": value.chapters[0].nodes[1].localMetadata["id"] = .number(1)
            case "local": value.chapters[0].nodes[1].id = "node1"
            case "chapter": value.chapters.append(value.chapters[0])
            default: value.chapters[0].id = "different"
            }
            XCTAssertEqual(mapping(value).reason, .identity, mutation)
        }
    }
    func testUnknownMixedClientKeyDuplicateKeyAndFutureGraphsStayUntouched() throws {
        for raw in [
            graph.replacingOccurrences(of: #""startNodeId":1"#, with: #""startNodeId":1,"startNodeKey":"local""#),
            graph.replacingOccurrences(of: #""toNodeId" : 2"#, with: #""toNodeKey":"local""#),
            graph.replacingOccurrences(of: #""toNodeId" : 2"#, with: #""toNodeId":2,"\u0074oNodeId":3"#),
            graph.replacingOccurrences(of: #""schemaVersion":1"#, with: #""schemaVersion":2"#),
            graph.replacingOccurrences(of: #""priority":3"#, with: #""priority":3,"future":true"#)
        ] {
            let value = draft(raw), projection = mapping(value), before = ProjectEditPendingMaterials.exactData(value)
            XCTAssertNotNil(projection.reason); XCTAssertThrowsError(try projection.applying(edgeID: "a", targetID: 3, to: value))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(value), before)
        }
    }
    func testLinearOtherProductsAndMissingProModeNeverCreateOrConvertGraph() {
        var value = draft(); value.preserved["routeMode"] = .string("LINEAR"); XCTAssertEqual(mapping(value).reason, .unsupported)
        value = draft(); value.product = .freeExplore; XCTAssertEqual(mapping(value).reason, .unsupported)
        value = draft(); value.preserved["publishMode"] = nil; XCTAssertEqual(mapping(value).reason, .unsupported)
    }
    func testMatchingTemplateSnapshotRequiredAndPrivateConfigurationNeverCopied() throws {
        var value = draft(); value.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(99), "validationMethod": .number(0)])
        XCTAssertEqual(mapping(value).reason, .outcomes)
        value = draft(); value.chapters[0].nodes[0].localMetadata["templateInfo"] = nil; XCTAssertEqual(mapping(value).reason, .outcomes)
        value = draft(); value.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41), "validationMethod": .number(6), "preferenceJson": .string(#"{"results":{"WIN":{"title":"Win"}}}"#)])
        value = try rewrite(value) { root in
            var edges = root["edges"]!.array!, first = edges[0].object!
            first["trigger"] = .object(["type": .string("PREFERENCE_RESULT"), "outcomeCode": .string("WIN")]); edges[0] = .object(first); root["edges"] = .array(edges)
        }
        let projection = mapping(value); XCTAssertNil(projection.reason); XCTAssertEqual(projection.rows.first?.label, "Win")
        let next = try projection.applying(edgeID: "a", targetID: 3, to: value)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next.chapters), ProjectEditPendingMaterials.exactData(value.chapters))
    }
    func testAdvancedAndD20DeclarationsAreSourceBackedAndInvalidCodesStayReadOnly() throws {
        for (config, code) in [(#"{"schemaVersion":1,"branch":{"enabled":true,"steps":[{"id":"end","terminal":true,"outcomeCode":"END","outcomeLabel":"End"}]}}"#, "END"), (#"{"schemaVersion":1,"diceRoll":{"enabled":true,"mode":"d20"}}"#, "D20_SUCCESS")] {
            var value = draft(); value.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41), "validationMethod": .number(7), "advancedConfigJson": .string(config)])
            value = try rewrite(value) { root in
                var edges = root["edges"]!.array!, first = edges[0].object!
                first["trigger"] = .object(["type": .string("ADVANCED_RESULT"), "outcomeCode": .string(code)]); edges[0] = .object(first); root["edges"] = .array(edges)
            }
            XCTAssertNil(mapping(value).reason)
            value.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41), "validationMethod": .number(7), "advancedConfigJson": .string(#"{"schemaVersion":1,"branch":{"enabled":true,"steps":[{"terminal":true,"outcomeCode":"END\n"}]}}"#)])
            XCTAssertEqual(mapping(value).reason, .outcomes)
        }
    }
    func testMultipleEdgesForOneOutcomeAndDuplicateEdgeIDsCannotBeRemapped() throws {
        let multiple = try rewrite(draft()) { root in
            var edges = root["edges"]!.array!, extra = edges[0].object!; extra["id"] = .string("other"); extra["toNodeId"] = .number(3)
            edges.append(.object(extra)); root["edges"] = .array(edges)
        }
        let projection = mapping(multiple); XCTAssertNil(projection.reason)
        XCTAssertTrue(projection.rows.allSatisfy { $0.reason == .ambiguous }); XCTAssertTrue(projection.targets(for: "a").isEmpty)
        XCTAssertThrowsError(try projection.applying(edgeID: "a", targetID: 4, to: multiple))
        let duplicate = try rewrite(multiple) { root in var edges = root["edges"]!.array!, last = edges[3].object!; last["id"] = .string("a"); edges[3] = .object(last); root["edges"] = .array(edges) }
        XCTAssertEqual(mapping(duplicate).reason, .ambiguous)
    }
    func testAffectedCycleAndLostReachabilityAreUnavailable() throws {
        let projection = mapping(draft())
        XCTAssertEqual(projection.targets(for: "a").first { $0.id == 1 }?.reason, .cycle)
        let noFallback = try rewrite(draft()) { $0["fallbacks"] = .array([]) }, without = mapping(noFallback)
        XCTAssertNil(without.reason); XCTAssertEqual(without.targets(for: "a").first { $0.id == 3 }?.reason, .reachability)
        XCTAssertThrowsError(try without.applying(edgeID: "a", targetID: 3, to: noFallback))
    }
    func testBoundedOrdinaryLoopMayRemainSafeButFallbackCyclesNeverAre() throws {
        let bounded = try rewrite(draft()) { root in
            var edges = root["edges"]!.array!, first = edges[0].object!; first["allowLoop"] = .bool(true); first["maxVisits"] = .number(2)
            edges[0] = .object(first); root["edges"] = .array(edges)
        }
        XCTAssertNil(try XCTUnwrap(mapping(bounded).targets(for: "a").first { $0.id == 1 }).reason)
        let fallbackCycle = try rewrite(draft()) { root in
            var edges = root["edges"]!.array!
            for index in edges.indices {
                var edge = edges[index].object!; edge["allowLoop"] = .bool(true); edge["maxVisits"] = .number(2); edges[index] = .object(edge)
            }
            root["edges"] = .array(edges)
            root["fallbacks"] = .array([.object(["fromNodeId": .number(3), "toNodeId": .number(1)])])
        }
        XCTAssertEqual(mapping(fallbackCycle).reason, .cycle)
    }
    func testTerminalOrdinaryAndFallbackOutgoingEdgesAreRejected() throws {
        let outgoing = try rewrite(draft()) { root in
            var edges = root["edges"]!.array!, edge = edges[0].object!
            edge["id"] = .string("terminal-outgoing"); edge["fromNodeId"] = .number(4); edge["toNodeId"] = .number(1)
            edges.append(.object(edge)); root["edges"] = .array(edges)
        }
        XCTAssertEqual(mapping(outgoing).reason, .unsupported)
        let fallback = try rewrite(draft()) { root in
            var rows = root["fallbacks"]!.array!; rows.append(.object(["fromNodeId": .number(4), "toNodeId": .number(1)])); root["fallbacks"] = .array(rows)
        }
        XCTAssertEqual(mapping(fallback).reason, .fallback)
    }
    func testTerminalWithoutAnExistingEdgeRemainsReadOnlyWithoutGuessingOutcomes() throws {
        var value = draft(); value.chapters[0].nodes[3].localMetadata["templateInfo"] = nil
        let projection = mapping(value, nodeID: "node4")
        XCTAssertEqual(projection.reason, .noEdges); XCTAssertTrue(projection.rows.isEmpty)
        XCTAssertTrue(projection.targets(for: "new-edge").isEmpty)
        XCTAssertThrowsError(try projection.applying(edgeID: "new-edge", targetID: 1, to: value))
    }
    func testAllNewCycleEdgesNeedTheirOwnBoundsAndTerminalReachabilityIsChecked() throws {
        let value = try rewrite(draft()) { root in
            var edges = root["edges"]!.array!
            for index in [1, 2] { var edge = edges[index].object!; edge["allowLoop"] = .bool(true); edge["maxVisits"] = .number(2); edges[index] = .object(edge) }
            var extra = edges[0].object!; extra["id"] = .string("direct"); extra["toNodeId"] = .number(4); edges.append(.object(extra)); root["edges"] = .array(edges)
        }
        XCTAssertEqual(mapping(value, nodeID: "node3").targets(for: "c").first { $0.id == 2 }?.reason, .reachability)
        let unbounded = try rewrite(value) { root in var edges = root["edges"]!.array!, edge = edges[1].object!; edge["allowLoop"] = .bool(false); edges[1] = .object(edge); root["edges"] = .array(edges) }
        XCTAssertEqual(mapping(unbounded, nodeID: "node3").targets(for: "c").first { $0.id == 2 }?.reason, .cycle)
    }
    func testActualRequirementRowsDemandAnUngatedFallbackEvenWhenFlagsAreFalse() throws {
        let gatedFallback = try rewrite(draft()) { $0["nodeRequirements"] = .array([.object(["nodeId": .number(2), "requireOpen": .bool(false)])]) }
        XCTAssertEqual(mapping(gatedFallback).reason, .fallback)
        let gated = try rewrite(draft()) { root in
            root["nodeRequirements"] = .array([.object(["nodeId": .number(3), "requireOpen": .bool(true)])])
            root["fallbacks"] = .array([.object(["fromNodeId": .number(2), "toNodeId": .number(4)])])
        }
        XCTAssertNil(mapping(gated).reason)
        XCTAssertEqual(mapping(gated).targets(for: "a").first { $0.id == 3 }?.reason, .fallback)
        let safe = try rewrite(gated) { root in var values = root["fallbacks"]!.array!; values.append(.object(["fromNodeId": .number(1), "toNodeId": .number(2)])); root["fallbacks"] = .array(values) }
        XCTAssertNil(try XCTUnwrap(mapping(safe).targets(for: "a").first { $0.id == 3 }).reason)
    }
    func testComposedAndDecomposedVariablesRequireExactSameFormAndPreserveRawBytes() throws {
        for name in ["é", "e\u{301}"] {
            let raw = graph.replacingOccurrences(of: #""score":0"#, with: "\"" + name + "\":0")
                .replacingOccurrences(of: #""op":"HAS_TAG","value":"tag.start""#, with: "\"op\":\"EQ\",\"var\":\"" + name + "\",\"value\":0")
                .replacingOccurrences(of: #""var":"score""#, with: "\"var\":\"" + name + "\"")
            let original = draft(raw), projection = mapping(original)
            XCTAssertNil(projection.reason)
            let next = try projection.applying(edgeID: "a", targetID: 3, to: original)
            XCTAssertEqual(next.preserved["routeGraphJson"]?.text?.utf8.map { $0 }, raw.replacingOccurrences(of: #""toNodeId" : 2"#, with: #""toNodeId" : 3"#).utf8.map { $0 })
        }
    }
    func testCanonicalEquivalentButByteDifferentConditionAndEffectVariableReferencesAreReadOnly() {
        for (declared, reference) in [("é", "e\u{301}"), ("e\u{301}", "é")] {
            for operation in ["EQ", "SET", "INC"] {
                var raw = graph.replacingOccurrences(of: #""score":0"#, with: "\"" + declared + "\":0")
                    .replacingOccurrences(of: #""var":"score""#, with: "\"var\":\"" + declared + "\"")
                if operation == "EQ" {
                    raw = raw.replacingOccurrences(of: #""op":"HAS_TAG","value":"tag.start""#, with: "\"op\":\"EQ\",\"var\":\"" + reference + "\",\"value\":0")
                } else {
                    raw = raw.replacingOccurrences(of: "\"op\":\"INC\",\"var\":\"" + declared + "\"", with: "\"op\":\"" + operation + "\",\"var\":\"" + reference + "\"")
                }
                let value = draft(raw), projection = mapping(value)
                XCTAssertEqual(projection.reason, .unsupported, operation)
                XCTAssertThrowsError(try projection.applying(edgeID: "a", targetID: 3, to: value))
                XCTAssertEqual(value.preserved["routeGraphJson"]?.text?.utf8.map { $0 }, raw.utf8.map { $0 })
            }
        }
    }
    func testCanonicalCollidingAndEscapedAliasVariableKeysFailClosedBeforeDictionaryCollapse() {
        for keys in [#""é":0,"e\u0301":1"#, #""e\u0301":0,"é":1"#, #""é":0,"\u00e9":1"#] {
            let raw = graph.replacingOccurrences(of: #""score":0"#, with: keys)
                .replacingOccurrences(of: #""var":"score""#, with: #""var":"é""#)
            let value = draft(raw), projection = mapping(value)
            XCTAssertEqual(projection.reason, .unsupported)
            XCTAssertThrowsError(try projection.applying(edgeID: "a", targetID: 3, to: value))
            XCTAssertEqual(value.preserved["routeGraphJson"]?.text?.utf8.map { $0 }, raw.utf8.map { $0 })
        }
    }
    func testASCIIOutcomeWorksButKelvinSignAliasStaysReadOnlyAndUnchanged() throws {
        var value = draft()
        value.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41), "validationMethod": .number(7), "advancedConfigJson": .string(#"{"schemaVersion":1,"branch":{"enabled":true,"steps":[{"terminal":true,"outcomeCode":"KEY","outcomeLabel":"Key"}]}}"#)])
        value = try rewrite(value) { root in
            var edges = root["edges"]!.array!, edge = edges[0].object!
            edge["trigger"] = .object(["type": .string("ADVANCED_RESULT"), "outcomeCode": .string("KEY")]); edges[0] = .object(edge); root["edges"] = .array(edges)
        }
        let valid = mapping(value); XCTAssertNil(valid.reason); XCTAssertEqual(valid.rows.first?.label, "Key")
        _ = try valid.applying(edgeID: "a", targetID: 3, to: value)
        for duplicate in [false, true] {
            let changed = try rewrite(value) { root in
                var edges = root["edges"]!.array!, edge = edges[0].object!
                edge["trigger"] = .object(["type": .string("ADVANCED_RESULT"), "outcomeCode": .string("KEY")])
                if duplicate { edge["id"] = .string("kelvin"); edges.append(.object(edge)) } else { edges[0] = .object(edge) }
                root["edges"] = .array(edges)
            }
            let raw = try XCTUnwrap(changed.preserved["routeGraphJson"]?.text), invalid = mapping(changed)
            XCTAssertEqual(invalid.reason, .outcomes); XCTAssertTrue(invalid.rows.isEmpty)
            XCTAssertThrowsError(try invalid.applying(edgeID: "a", targetID: 3, to: changed))
            XCTAssertEqual(changed.preserved["routeGraphJson"]?.text?.utf8.map { $0 }, raw.utf8.map { $0 })
        }
    }
    func testKelvinSignPropertyAliasIsUnknownAndDoesNotBecomeAGateField() throws {
        let valid = try rewrite(draft()) { root in
            root["nodeRequirements"] = .array([.object(["nodeId": .number(3), "allowedPurchaseKinds": .array([.number(1)])])])
            var fallback = root["fallbacks"]!.array!; fallback.append(.object(["fromNodeId": .number(2), "toNodeId": .number(4)])); root["fallbacks"] = .array(fallback)
        }
        XCTAssertNil(mapping(valid).reason)
        let raw = try XCTUnwrap(valid.preserved["routeGraphJson"]?.text).replacingOccurrences(of: "allowedPurchaseKinds", with: "allowedPurchaseKinds")
        var unknown = valid; unknown.preserved["routeGraphJson"] = .string(raw)
        let invalid = mapping(unknown); XCTAssertEqual(invalid.reason, .unsupported)
        XCTAssertThrowsError(try invalid.applying(edgeID: "a", targetID: 3, to: unknown))
        XCTAssertEqual(unknown.preserved["routeGraphJson"]?.text?.utf8.map { $0 }, raw.utf8.map { $0 })
    }
    func testExactDuplicateOutcomesAndCanonicalCollidingEdgeDisplayIdentitiesAreReadOnly() throws {
        var duplicate = draft()
        duplicate.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41), "validationMethod": .number(7), "advancedConfigJson": .string(#"{"schemaVersion":1,"branch":{"enabled":true,"steps":[{"terminal":true,"outcomeCode":"COMPLETED"},{"terminal":true,"outcomeCode":"COMPLETED"}]}}"#)])
        XCTAssertEqual(mapping(duplicate).reason, .outcomes)
        let collision = try rewrite(draft()) { root in
            var edges = root["edges"]!.array!, first = edges[0].object!, second = edges[1].object!
            first["id"] = .string("KEY"); second["id"] = .string("KEY"); edges[0] = .object(first); edges[1] = .object(second); root["edges"] = .array(edges)
        }
        XCTAssertEqual(mapping(collision).reason, .unsupported)
    }
    func testRawTemplateResultKeyCollisionAndUnverifiableObjectConfigurationStayReadOnly() throws {
        var value = draft()
        value = try rewrite(value) { root in
            var edges = root["edges"]!.array!, edge = edges[0].object!
            edge["trigger"] = .object(["type": .string("PREFERENCE_RESULT"), "outcomeCode": .string("KEY")]); edges[0] = .object(edge); root["edges"] = .array(edges)
        }
        value.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41), "validationMethod": .number(6), "preferenceJson": .string(#"{"results":{"KEY":{"title":"Key"},"KEY":{"title":"Alias"}}}"#)])
        let before = ProjectEditPendingMaterials.exactData(value), collision = mapping(value)
        XCTAssertEqual(collision.reason, .unsupported)
        XCTAssertThrowsError(try collision.applying(edgeID: "a", targetID: 3, to: value)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(value), before)
        value.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41), "validationMethod": .number(6), "preferenceJson": .object(["results": .object(["KEY": .object(["title": .string("Key")])])])])
        XCTAssertEqual(mapping(value).reason, .outcomes)
    }
    func testStaleTemplateNodeGraphAndDestinationChangesRejectApply() throws {
        let original = draft(), projection = mapping(original)
        for mutation in ["source", "node", "graph", "reorder"] {
            var changed = original
            switch mutation {
            case "source": changed.chapters[0].nodes[0].templateID = 99
            case "node": changed.chapters[0].nodes.removeLast()
            case "graph": changed.preserved["routeGraphJson"] = .string(graph + " ")
            default: changed.chapters[0].nodes.reverse()
            }
            XCTAssertThrowsError(try projection.applying(edgeID: "a", targetID: 3, to: changed), mutation)
        }
        XCTAssertThrowsError(try projection.applying(edgeID: "new", targetID: 3, to: original))
        XCTAssertThrowsError(try projection.applying(edgeID: "a", targetID: 999, to: original))
    }
}
