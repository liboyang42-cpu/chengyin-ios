import Foundation
import SceneKit
import XCTest
@testable import Questify

/// Uses only embedded, synthetic bytes. No URLSession, camera, ARSession,
/// private model, backend, permission request or device-provider activation.
@MainActor final class PlayKitGLBDecoderTests: XCTestCase {
    private func triangle() throws -> Data {
        let json: [String: Any] = ["asset": ["version": "2.0"], "scene": 0, "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0]], "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
            "buffers": [["byteLength": 36]], "bufferViews": [["buffer": 0, "byteLength": 36]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0,0,0], "max": [1,1,0]]]]
        var chunk = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        while chunk.count % 4 != 0 { chunk.append(0x20) }
        var output = Data()
        func append(_ value: UInt32) { for shift in [0,8,16,24] { output.append(UInt8((value >> shift) & 255)) } }
        append(0x46546C67); append(2); append(UInt32(28 + chunk.count + 36)); append(UInt32(chunk.count)); append(0x4E4F534A)
        output.append(chunk); append(36); append(0x004E4942)
        for value: Float in [0,0,0, 1,0,0, 0,1,0] { append(value.bitPattern) }
        return output
    }
    func testPinnedFrameworkActuallyDecodesSyntheticGLBToSceneKitGeometry() async throws {
        let scene = try await PlayKitGLBDecoder().scene(from: triangle())
        var geometries: [SCNGeometry] = []
        scene.rootNode.enumerateChildNodes { node, _ in if let geometry = node.geometry { geometries.append(geometry) } }
        XCTAssertEqual(geometries.count,1)
        XCTAssertEqual(geometries.first?.sources(for:.vertex).first?.vectorCount,3)
        XCTAssertEqual(geometries.first?.elements.first?.primitiveCount,1)
    }
    func testUnapprovedOriginDoesNotInvokeEitherProvider() async throws {
        let loader = Loader(bytes: try triangle()), decoder = Decoder()
        do {
            _ = try await PlayKitGLBPreparation.load(URL(string:"https://unapproved.invalid/model.glb")!,approvedHosts:["approved.invalid"],downloader:loader,decoder:decoder)
            XCTFail("origin must be approved")
        } catch { XCTAssertEqual(error as? PlayKitSpatialError,.assetUnavailable) }
        XCTAssertEqual(loader.calls,0);XCTAssertEqual(decoder.calls,0)
    }
    func testInvalidBytesNeverReachDecoderAndLeaveFallbackAvailable() async throws {
        let loader = Loader(bytes:Data("not a GLB".utf8)), decoder = Decoder()
        do {
            _ = try await PlayKitGLBPreparation.load(URL(string:"https://approved.invalid/model.glb")!,approvedHosts:["approved.invalid"],downloader:loader,decoder:decoder)
            XCTFail("invalid model should fall back")
        } catch { XCTAssertEqual(error as? PlayKitSpatialError,.unsupportedModel) }
        XCTAssertEqual(loader.calls,1);XCTAssertEqual(decoder.calls,0)
    }
    func testValidBytesUseInjectedProvidersWithoutNetwork() async throws {
        let loader = Loader(bytes:try triangle()), decoder = Decoder()
        _ = try await PlayKitGLBPreparation.load(URL(string:"https://approved.invalid/model.glb")!,approvedHosts:["approved.invalid"],downloader:loader,decoder:decoder)
        XCTAssertEqual(loader.calls,1);XCTAssertEqual(decoder.calls,1)
    }
    func testCancellationBeforePreparationCannotReachProvider() async throws {
        let loader = Loader(bytes:try triangle()), decoder = Decoder()
        let task = Task { @MainActor in
            try await PlayKitGLBPreparation.load(URL(string:"https://approved.invalid/model.glb")!,approvedHosts:["approved.invalid"],downloader:loader,decoder:decoder)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(loader.calls,0);XCTAssertEqual(decoder.calls,0)
    }
    func testDefaultRuntimeHasNoARModeOrModelOriginApproval() {
        let approval = PlayKitSpatialApproval()
        XCTAssertTrue(approval.modes.isEmpty);XCTAssertTrue(approval.modelHosts.isEmpty)
    }
    private final class Loader: PlayKitGLBDataLoading {
        var calls = 0;let bytes:Data
        init(bytes:Data) { self.bytes = bytes }
        func load(_ url:URL,approvedHosts:Set<String>) async throws -> Data { calls += 1;return bytes }
    }
    private final class Decoder: PlayKitGLBSceneDecoding {
        var calls = 0
        func scene(from data:Data) async throws -> SCNScene { calls += 1;return SCNScene() }
    }
}
