import XCTest
@testable import QuestifyCore

final class ProjectCityStoryNodeRemovalTests:XCTestCase {
    private func draft()->ProjectEditDraft {
        var d=ProjectEditDraft(product:.city),chapter=ProjectEditChapter();chapter.id="chapter"
        chapter.name=" é \n";chapter.description="  unchanged e\u{301}\n"
        chapter.nodes=["node-a","node-b","node-c"].map{id in var n=ProjectEditNode();n.id=id;n.name=id;n.description="  é\n";n.imgUrl="old,\u{301}same,old";n.localMetadata["futureText"] = .string(" e\u{301}\n");return n}
        var start=ProjectEditBlock(kind:.text,content:"Before\n");start.id="start"
        var middle=ProjectEditBlock(kind:.text,content:"  After A e\u{301}");middle.id="middle"
        var tail=ProjectEditBlock(kind:.text,content:"After C");tail.id="tail"
        let nodes=chapter.nodes.map{n -> ProjectEditBlock in var b=ProjectEditBlock(kind:.node,nodeID:n.id);b.id="block-"+n.id;return b}
        chapter.blocks=[start,nodes[0],middle,nodes[1],nodes[2],tail];d.chapters=[chapter]
        var pending=ProjectEditNode();pending.id="pending";pending.name="Keep";d.pendingMaterials=[.init(node:pending,kind:.place)]
        d.preserved["futureText"] = .string(" preserve é\n");return d
    }
    private func remove(_ d:ProjectEditDraft,id:String="node-a")throws->ProjectCityStoryNodeRemoval.Receipt { try ProjectCityStoryNodeRemoval.removing(nodeID:id,chapterID:"chapter",in:d) }
    func testRemovesOnlyExactNodeAndItsSingleBlockWithoutMergingOrPendingCopy()throws {
        let d=draft(),receipt=try remove(d);var expected=d;expected.chapters[0].nodes.remove(at:0);expected.chapters[0].blocks?.remove(at:1)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(receipt.after),ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(receipt.after.chapters[0].blocks?.map(\.id),["start","middle","block-node-b","block-node-c","tail"])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(receipt.after.pendingMaterials),ProjectEditPendingMaterials.exactData(d.pendingMaterials))
    }
    func testUndoRestoresEveryRawByteAndNilRepresentation()throws {
        var d=draft();d.pendingMaterials=nil;let r=try remove(d)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try ProjectCityStoryNodeRemoval.restoring(r,in:r.after)),ProjectEditPendingMaterials.exactData(d))
        XCTAssertThrowsError(try ProjectCityStoryNodeRemoval.restoring(r,in:d))
    }
    func testConsecutiveRemovalsCombineInSourceOrderAndRestoreOriginalPositions()throws {
        let d=draft(),first=try remove(d,id:"node-b"),second=try remove(first.after),combined=try ProjectCityStoryNodeRemoval.combining(first,with:second)
        XCTAssertEqual(combined.nodeIDs,["node-b","node-a"]);XCTAssertEqual(ProjectEditPendingMaterials.exactData(try ProjectCityStoryNodeRemoval.restoring(combined,in:second.after)),ProjectEditPendingMaterials.exactData(d))
        XCTAssertThrowsError(try ProjectCityStoryNodeRemoval.combining(second,with:first))
    }
    func testExactUndoRejectsCanonicalEquivalentAndOtherEditedBytes()throws {
        let r=try remove(draft());var changed=r.after;changed.chapters[0].description="  unchanged é\n"
        XCTAssertEqual(changed,r.after);XCTAssertThrowsError(try ProjectCityStoryNodeRemoval.restoring(r,in:changed))
        changed=r.after;changed.name="Later";XCTAssertThrowsError(try ProjectCityStoryNodeRemoval.restoring(r,in:changed))
    }
    func testFreeExploreMerchantOpeningEndingAndUnmaterializedShapesStayUnchanged()throws {
        let original=draft()
        for variant in 0..<6 { var d=original
            switch variant {case 0:d.product = .freeExplore;case 1:d.owner = .merchant;case 2:d.chapters[0].preserved["opening"] = .bool(true);case 3:d.chapters[0].preserved["ending"] = .object([:]);case 4:d.chapters[0].blocks=nil;default:d.chapters[0].schemaVersion=2}
            let before=ProjectEditPendingMaterials.exactData(d);XCTAssertThrowsError(try remove(d));XCTAssertEqual(ProjectEditPendingMaterials.exactData(d),before)
        }
    }
    func testBranchOpaqueWhitespaceAndUnknownRouteShapesFailClosed()throws {
        for raw in [ProjectEditJSON.string("BRANCH_GRAPH"),.string("linear"),.object([:])] { var d=draft();d.preserved["routeMode"]=raw;XCTAssertThrowsError(try remove(d)) }
        for raw in [ProjectEditJSON.string(" "),.string("{}"),.object([:]),.string("{\"edges\":[]}")] {var d=draft();d.preserved["routeGraphJson"]=raw;XCTAssertThrowsError(try remove(d))}
    }
    func testRelatedNarrativeAndRepeatedNodeBlocksCannotBeOrphaned()throws {
        var d=draft();var b=ProjectEditBlock(kind:.text,content:"Linked",nodeID:"node-a");b.id="narrative";b.selectBeat(.enter);d.chapters[0].blocks?.append(b);XCTAssertThrowsError(try remove(d))
        d=draft();b=ProjectEditBlock(kind:.node,nodeID:"node-a");b.id="second-node-block";d.chapters[0].blocks?.append(b);XCTAssertThrowsError(try remove(d))
    }
    func testGrantsQuestsAndNestedNodeConditionsFailClosed()throws {
        for metadata in ["grants":ProjectEditJSON.array([.object(["key":.string("item.key")])]),"quests":.object(["target":.string("node-a")]),"future":.object(["NODE_ID":.string("node-a")])] {
            var d=draft();d.chapters[0].nodes[0].localMetadata[metadata.key]=metadata.value;XCTAssertThrowsError(try remove(d))
        }
        var d=draft();d.chapters[0].nodes[0].localMetadata["id"] = .number(42);d.chapters[0].preserved["ending"] = .null
        d.preserved["journeyRules"] = .object(["condition":.object(["op":.string("NODE_COMPLETED"),"nodeId":.number(42)])]);XCTAssertThrowsError(try remove(d))
    }
    func testOpaqueSerializedDependencyDocumentsAreReadOnly()throws {
        for raw in ["{\"unknownLink\":\"node-a\"}"," {bad json", "[42]", "{\"é\":1,\"e\\u0301\":2}"] {var d=draft();d.preserved["journeyRules"] = .string(raw);XCTAssertThrowsError(try remove(d))}
        var d=draft();d.preserved["journeyRules"] = .string("{}");XCTAssertNoThrow(try remove(d))
    }
    func testExactLocalClientAndServerReferencesInOtherMetadataAreRejected()throws {
        for target in [ProjectEditJSON.string("node-a"),.string("client-a"),.number(42),.string("42"),.string(" 42 ")] {
            var d=draft();d.chapters[0].nodes[0].localMetadata["id"] = .number(42);d.chapters[0].nodes[0].localMetadata["clientNodeKey"] = .string("client-a")
            d.chapters[0].nodes[1].localMetadata["futureLink"] = target;XCTAssertThrowsError(try remove(d))
        }
    }
    func testAmbiguousRawIDsPendingAliasesAndBlockIdentityAreRejected()throws {
        var d=draft();d.chapters[0].nodes[0].id="é";d.chapters[0].blocks?[1].nodeID="é";d.chapters[0].nodes[1].id="e\u{301}";XCTAssertThrowsError(try remove(d,id:"é"))
        d=draft();d.pendingMaterials?.append(.init(node:d.chapters[0].nodes[0]));XCTAssertThrowsError(try remove(d))
        d=draft();d.chapters[0].blocks?[2].id=d.chapters[0].blocks![0].id;XCTAssertThrowsError(try remove(d))
        XCTAssertThrowsError(try remove(draft(),id:"missing"))
    }
    func testStoryOnlyNodeAndFalseLocationRequirementStayProtected()throws {
        var d=draft();d.chapters[0].nodes[0].localMetadata["_storyGame"] = .bool(true);XCTAssertThrowsError(try remove(d))
        d=draft();d.chapters[0].blocks?[1].sourceFields=["locationRequired":.bool(false)];XCTAssertThrowsError(try remove(d))
    }
    func testDuplicateOrMalformedRemoteAndClientIdentifiersFailClosed()throws {
        var d=draft();d.chapters[0].nodes[0].localMetadata["id"] = .number(42);d.chapters[0].nodes[1].localMetadata["id"] = .number(42);XCTAssertThrowsError(try remove(d))
        d=draft();d.chapters[0].nodes[0].localMetadata["id"] = .string("42");XCTAssertThrowsError(try remove(d))
        d=draft();d.chapters[0].nodes[0].localMetadata["clientNodeKey"] = .string("é");d.chapters[0].nodes[1].localMetadata["clientNodeKey"] = .string("e\u{301}");XCTAssertThrowsError(try remove(d))
    }
}
