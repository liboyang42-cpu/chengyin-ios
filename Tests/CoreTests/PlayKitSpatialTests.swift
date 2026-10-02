import XCTest
@testable import QuestifyCore

final class PlayKitSpatialTests: XCTestCase {
    private func segment(mode:String="PLANE",scanned:Bool=true,model:String="",marker:String="https://example.com/marker.png")->PlayWireValue {
        .object(["kind":.string("OVERLAY"),"scanned":.bool(scanned),"overlayUrl":.string("https://example.com/image.png"),"arMode":.string(mode),"markerUrl":.string(marker),"modelUrl":.string(model)])
    }
    private var planeApproval:PlayKitSpatialApproval { .init(modes:[.plane],artworkHosts:["example.com"]) }
    func testDefaultApprovalCannotStartAnyAR() {
        let approval=PlayKitSpatialApproval();XCTAssertTrue(approval.modes.isEmpty);XCTAssertTrue(approval.artworkHosts.isEmpty)
        XCTAssertThrowsError(try PlayKitSpatialRequest(segment:segment(),approval:approval))
    }
    func testPlaneRequiresAnAuthoritativelyAcceptedScan() {
        XCTAssertThrowsError(try PlayKitSpatialRequest(segment:segment(scanned:false),approval:planeApproval)) { XCTAssertEqual($0 as? PlayKitSpatialError,.unvalidatedScan) }
    }
    func testModeCannotEnableItselfFromServerData() {
        XCTAssertThrowsError(try PlayKitSpatialRequest(segment:segment(mode:"MARKER"),approval:planeApproval)) { XCTAssertEqual($0 as? PlayKitSpatialError,.disabled) }
        XCTAssertThrowsError(try PlayKitSpatialRequest(segment:segment(mode:"GEO"),approval:planeApproval)) { XCTAssertEqual($0 as? PlayKitSpatialError,.unsupportedMode) }
    }
    func testPlaneCardUsesSourceWidthAndPreservesImageAspectRatio() throws {
        let request=try PlayKitSpatialRequest(segment:segment(),approval:planeApproval)
        XCTAssertEqual(request.cardWidthMeters,0.4)
        XCTAssertEqual(try request.cardHeightMeters(imageWidth:800,imageHeight:400),0.2,accuracy:0.0001)
        XCTAssertEqual(try request.cardHeightMeters(imageWidth:400,imageHeight:800),0.8,accuracy:0.0001)
        XCTAssertThrowsError(try request.cardHeightMeters(imageWidth:0,imageHeight:400))
    }
    func testMarkerNeedsExplicitCalibrationRatherThanAGuessedMeter() {
        let approval=PlayKitSpatialApproval(modes:[.marker],artworkHosts:["example.com"])
        XCTAssertThrowsError(try PlayKitSpatialRequest(segment:segment(mode:"MARKER"),approval:approval)) { XCTAssertEqual($0 as? PlayKitSpatialError,.markerCalibrationRequired) }
    }
    func testMarkerCalibrationIsBoundToExactApprovedAsset() throws {
        let approval=PlayKitSpatialApproval(modes:[.marker],artworkHosts:["example.com"],markerWidthsMeters:["https://example.com/marker.png":0.23])
        let request=try PlayKitSpatialRequest(segment:segment(mode:"MARKER"),approval:approval)
        XCTAssertEqual(request.markerWidthMeters,0.23);XCTAssertEqual(request.cardWidthMeters,0.23)
        XCTAssertThrowsError(try PlayKitSpatialRequest(segment:segment(mode:"MARKER",marker:"https://example.com/other.png"),approval:approval))
    }
    func testInvalidMarkerDimensionsCannotStartRecognition() {
        for value in [0.0,-1,11,.infinity,.nan] {
            let approval=PlayKitSpatialApproval(modes:[.marker],artworkHosts:["example.com"],markerWidthsMeters:["https://example.com/marker.png":value])
            XCTAssertThrowsError(try PlayKitSpatialRequest(segment:segment(mode:"MARKER"),approval:approval))
        }
    }
    func testConfiguredGLBIsNotSilentlyPretendedToBeAnImageModel() {
        XCTAssertThrowsError(try PlayKitSpatialRequest(segment:segment(model:"https://example.com/model.glb"),approval:planeApproval)) { XCTAssertEqual($0 as? PlayKitSpatialError,.unsupportedModel) }
    }
    func testUnapprovedImageOriginNeverLoads() {
        let approval=PlayKitSpatialApproval(modes:[.plane],artworkHosts:["other.example.com"])
        XCTAssertThrowsError(try PlayKitSpatialRequest(segment:segment(),approval:approval)) { XCTAssertEqual($0 as? PlayKitSpatialError,.assetUnavailable) }
    }
    func testPlanePlacementNeedsAnActualRaycast() {
        var state=PlayKitSpatialPlacement();state.foundPlane()
        XCTAssertFalse(state.placeOnPlane(hasActualRaycast:false));XCTAssertEqual(state.placementCount,0)
        XCTAssertTrue(state.placeOnPlane(hasActualRaycast:true));XCTAssertEqual(state.phase,.placed)
    }
    func testMarkerLocksOnlyOnceAndDoesNotFollowLaterTracking() {
        var state=PlayKitSpatialPlacement()
        XCTAssertFalse(state.lockMarker(hasActualAnchor:false));XCTAssertTrue(state.lockMarker(hasActualAnchor:true))
        XCTAssertFalse(state.lockMarker(hasActualAnchor:true));XCTAssertEqual(state.placementCount,1)
    }
    func testFailedARCannotPlaceButLeavesBusinessCompletionUntouched() {
        var state=PlayKitSpatialPlacement();state.fail()
        XCTAssertFalse(state.placeOnPlane(hasActualRaycast:true));XCTAssertFalse(state.lockMarker(hasActualAnchor:true));XCTAssertEqual(state.phase,.fallback)
    }
}
