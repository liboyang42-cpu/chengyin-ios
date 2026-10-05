import XCTest
@testable import QuestifyCore

final class PlayKitGLBPolicyTests: XCTestCase {
    private func fixture(indexCount: Int = 0, edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var json: [String: Any] = ["asset": ["version": "2.0"], "scene": 0, "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0]], "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
            "buffers": [["byteLength": 36]], "bufferViews": [["buffer": 0, "byteLength": 36]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0,0,0], "max": [1,1,0]]]]
        let binaryLength = 36 + indexCount * 2
        let paddedLength = (binaryLength + 3) / 4 * 4
        if indexCount > 0 {
            json["buffers"] = [["byteLength":binaryLength]]
            json["bufferViews"] = [["buffer":0,"byteLength":36], ["buffer":0,"byteOffset":36,"byteLength":indexCount * 2]]
            var accessors = json["accessors"] as! [[String:Any]]
            accessors.append(["bufferView":1,"componentType":5123,"count":indexCount,"type":"SCALAR"])
            json["accessors"] = accessors
            json["meshes"] = [["primitives":[["attributes":["POSITION":0],"indices":1]]]]
        }
        edit(&json)
        var chunk = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        while chunk.count % 4 != 0 { chunk.append(0x20) }
        var output = Data()
        func append(_ number: UInt32) { for shift in [0,8,16,24] { output.append(UInt8((number >> shift) & 255)) } }
        append(0x46546C67); append(2); append(UInt32(28 + chunk.count + paddedLength)); append(UInt32(chunk.count)); append(0x4E4F534A)
        output.append(chunk); append(UInt32(paddedLength)); append(0x004E4942)
        for value: Float in [0,0,0, 1,0,0, 0,1,0] { append(value.bitPattern) }
        for i in 0..<indexCount { output.append(UInt8(i % 3)); output.append(0) }
        while output.count % 4 != 0 { output.append(0) }
        return output
    }
    func testSelfContainedTrianglePassesWithoutAnyExternalResource() throws {
        let bytes = try fixture(), result = try PlayKitGLBPolicy.validate(bytes)
        XCTAssertEqual(result.nodeCount, 1); XCTAssertTrue(result.imageRanges.isEmpty)
        XCTAssertEqual(result.binaryRange.count, 36)
    }
    func testMalformedHeaderLengthTrailingChunkAndTruncationFailClosed() throws {
        let good = try fixture()
        for offset in [0,4,8,12,16] {
            var bad = good; bad[offset] = 0xff
            XCTAssertThrowsError(try PlayKitGLBPolicy.validate(bad))
        }
        XCTAssertThrowsError(try PlayKitGLBPolicy.validate(good.dropLast()))
        var trailing = good; trailing.append(0)
        XCTAssertThrowsError(try PlayKitGLBPolicy.validate(trailing))
    }
    func testEveryURIIncludingNestedExtrasIsRejectedBeforeDecode() throws {
        for uri in ["file:///etc/passwd", "../secrets", "https://attacker.example/a", "data:application/octet-stream;base64,AAAA", "//attacker.example/a"] {
            XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0["buffers"] = [["byteLength":36,"uri":uri]] }))
            XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0["extras"] = ["nested":["uri":uri]] }))
        }
    }
    func testCompressedAndUnknownExtensionsFallBackEvenIfOptional() throws {
        for name in ["KHR_draco_mesh_compression", "KHR_texture_basisu", "EXT_meshopt_compression", "UNKNOWN"] {
            XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0["extensionsUsed"] = [name] }))
            XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0["extensionsRequired"] = [name] }))
            XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0["extensions"] = [name:[:]] }))
        }
    }
    func testOutOfRangeAccessorStrideIndexAndSparseFail() throws {
        for accessor: [String: Any] in [
            ["bufferView":1,"componentType":5126,"count":3,"type":"VEC3"],
            ["bufferView":0,"componentType":5126,"count":4,"type":"VEC3"],
            ["bufferView":0,"componentType":5126,"count":3,"type":"VEC3","sparse":[:]],
            ["bufferView":0,"componentType":5126,"count":true,"type":"VEC3"]] {
            XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0["accessors"] = [accessor] }))
        }
        XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0["bufferViews"] = [["buffer":0,"byteLength":36,"byteStride":8]] }))
        XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0["bufferViews"] = [["buffer":0,"byteLength":37]] }))
    }
    func testCyclesMultiParentAndUnboundedNodesFail() throws {
        XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0["nodes"] = [["mesh":0,"children":[0]]] }))
        XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0["nodes"] = [["mesh":0,"children":[1,1]],[:]] }))
        XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0["nodes"] = Array(repeating: ["mesh":0], count:513) }))
    }
    func testRepeatedMeshesCannotMultiplyTheDrawBudgetWithoutLimit() throws {
        // Four cheap triangles in one mesh, instanced 300 times, exceed 1,024 draws
        // even though the source buffers and unique mesh are tiny.
        XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture {
            $0["meshes"] = [["primitives": Array(repeating: ["attributes":["POSITION":0]], count:4)]]
            $0["nodes"] = Array(repeating: ["mesh":0], count:300)
            $0["scenes"] = [["nodes":Array(0..<300)]]
        }))
    }
    func testIndexedInstancesCannotAmplifySmallVertexBuffersPastTheBudget() throws {
        XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture(indexCount:30_000) {
            $0["nodes"] = Array(repeating:["mesh":0],count:34)
            $0["scenes"] = [["nodes":Array(0..<34)]]
        }))
        XCTAssertNoThrow(try PlayKitGLBPolicy.validate(fixture(indexCount:30_000)))
    }
    func testUnsupportedAnimationSkinMorphAndImageTypesFallBack() throws {
        for key in ["animations", "skins", "cameras"] {
            XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0[key] = [[:]] }))
        }
        XCTAssertThrowsError(try PlayKitGLBPolicy.validate(fixture { $0["images"] = [["bufferView":0,"mimeType":"image/ktx2"]] }))
    }
    func testApprovedModelRequiresHTTPSExactHostGLBAndNoFragmentOrCredentials() {
        XCTAssertNotNil(PlayKitGLBPolicy.approvedURL("https://cdn.example/model.glb?version=1", hosts:["cdn.example"]))
        for url in ["http://cdn.example/model.glb", "https://other.example/model.glb", "file:///model.glb", "https://cdn.example/model.gltf", "https://cdn.example/model.glb#x", "https://user:pass@cdn.example/model.glb"] {
            XCTAssertNil(PlayKitGLBPolicy.approvedURL(url, hosts:["cdn.example"]))
        }
    }
    func testModelFitPreservesAspectCentersAndRestsOnGround() throws {
        let fit = try PlayKitModelFit(min:(2,-4,6),max:(4,0,8),targetMeters:0.4)
        XCTAssertEqual(fit.scale,0.1,accuracy:0.0001);XCTAssertEqual(fit.x,-0.3,accuracy:0.0001)
        XCTAssertEqual(fit.y,0.4,accuracy:0.0001);XCTAssertEqual(fit.z,-0.7,accuracy:0.0001)
        XCTAssertThrowsError(try PlayKitModelFit(min:(0,0,0),max:(0,0,0),targetMeters:0.4))
    }
    func testGLBRequiresIndependentModelOriginApprovalAndMarkerCalibration() throws {
        var segment: PlayWireValue = .object(["kind":.string("OVERLAY"),"scanned":.bool(true),"overlayUrl":.string("https://example.com/image.png"),"modelUrl":.string("https://models.example/model.glb"),"arMode":.string("PLANE")])
        let approval = PlayKitSpatialApproval(modes:[.plane],artworkHosts:["example.com"],modelHosts:["models.example"])
        let plane = try PlayKitSpatialRequest(segment:segment,approval:approval)
        XCTAssertNotNil(plane.modelURL);XCTAssertEqual(plane.modelLongestSideMeters,0.4)
        segment = .object(["kind":.string("OVERLAY"),"scanned":.bool(true),"overlayUrl":.string("https://example.com/image.png"),"modelUrl":.string("https://models.example/model.glb"),"arMode":.string("MARKER"),"markerUrl":.string("https://example.com/marker.png")])
        XCTAssertThrowsError(try PlayKitSpatialRequest(segment:segment,approval:.init(modes:[.marker],artworkHosts:["example.com"],modelHosts:["models.example"])))
        let marker = try PlayKitSpatialRequest(segment:segment,approval:.init(modes:[.marker],artworkHosts:["example.com"],modelHosts:["models.example"],markerWidthsMeters:["https://example.com/marker.png":0.25]))
        XCTAssertEqual(marker.modelLongestSideMeters,0.2,accuracy:0.0001)
    }
}
