import XCTest
@testable import QuestifyCore

final class PlayKitCameraContractTests: XCTestCase {
    func testFrameRequiresAnApprovedExactHTTPSHost() {
        XCTAssertNil(PlayKitPhotoFrame(source:"https://example.com/frame.png",opacityPercent:nil,approvedHosts:[]))
        XCTAssertNil(PlayKitPhotoFrame(source:"https://sub.example.com/frame.png",opacityPercent:nil,approvedHosts:["example.com"]))
        XCTAssertNil(PlayKitPhotoFrame(source:"http://example.com/frame.png",opacityPercent:nil,approvedHosts:["example.com"]))
        XCTAssertNil(PlayKitPhotoFrame(source:"https://user:secret@example.com/frame.png",opacityPercent:nil,approvedHosts:["example.com"]))
        XCTAssertNil(PlayKitPhotoFrame(source:"https://example.com:8443/frame.png",opacityPercent:nil,approvedHosts:["example.com"]))
        XCTAssertNotNil(PlayKitPhotoFrame(source:"https://example.com/frame.png",opacityPercent:nil,approvedHosts:["example.com"]))
    }
    func testFrameOpacityHonorsZeroAndClampsSourceRange() {
        func frame(_ value:Double?)->PlayKitPhotoFrame { PlayKitPhotoFrame(source:"https://example.com/f.png",opacityPercent:value,approvedHosts:["example.com"])! }
        XCTAssertEqual(frame(nil).opacity,0.4);XCTAssertEqual(frame(.nan).opacity,0.4)
        XCTAssertEqual(frame(0).opacity,0);XCTAssertEqual(frame(-1).opacity,0);XCTAssertEqual(frame(140).opacity,1)
    }
    func testOverlayNeedsAuthoritativeScanAcceptance() {
        let raw:PlayWireValue = .object(["overlayUrl":.string("https://example.com/a.png"),"scanned":.bool(false)])
        XCTAssertNil(PlayKitScanOverlay(segment:raw,approvedHosts:["example.com"]))
    }
    func testOverlaySizeUsesSourceBoundsWithoutAwardingOutcome() {
        func value(_ scale:Double)->PlayKitScanOverlay {
            PlayKitScanOverlay(segment:.object(["scanned":.bool(true),"overlayUrl":.string("https://example.com/a.png"),"overlayScale":.number(scale)]),approvedHosts:["example.com"])!
        }
        XCTAssertEqual(value(10).widthFraction,0.2);XCTAssertEqual(value(300).widthFraction,1)
        XCTAssertEqual(value(0).widthFraction,0.6);XCTAssertEqual(value(.nan).widthFraction,0.6)
        XCTAssertEqual(value(60).mode,"NONE")
    }
}

@available(macOS 14.0, *)
@MainActor final class PlayKitCameraCoordinatorTests: XCTestCase {
    private func context(_ epoch:UInt64=1)throws->PlayDeviceContext {
        try .init(session:.init(accountID:1,epoch:epoch,namespace:"synthetic",token:"synthetic-token"),scope:.activity(1),nodeID:2)
    }
    private var frame:PlayKitPhotoFrame { .init(source:"https://example.com/f.png",opacityPercent:40,approvedHosts:["example.com"])! }
    func testFramedCaptureUsesTypedProviderAndReturnsActualBytes() async throws {
        let context=try context(), provider=PlayKitCameraTestProvider()
        let model=PlayDeviceCaptureCoordinator(provider:provider,current:{context})
        await model.capture(.photo,cameraFrame:frame)
        XCTAssertEqual(provider.framed,1);XCTAssertEqual(provider.ordinary,0)
        XCTAssertEqual(model.output,.photo(Data([1,2,3]),mimeType:"image/jpeg"))
        XCTAssertNil(model.uploadedPhoto)
    }
    func testFrameFallsBackToOrdinaryCaptureWhenProviderLacksFraming() async throws {
        let context=try context()
        let provider=PlaySyntheticDeviceProvider(supported:[.photo]) { _,_ in .photo(Data([7]),mimeType:"image/jpeg") }
        let model=PlayDeviceCaptureCoordinator(provider:provider,current:{context})
        await model.capture(.photo,cameraFrame:frame)
        XCTAssertEqual(provider.captured.count,1);XCTAssertEqual(model.output,.photo(Data([7]),mimeType:"image/jpeg"))
    }
    func testPhotoLibraryHasItsOwnTypedEntryAndNoCameraFallback() async throws {
        let context=try context(), provider=PlayKitCameraTestProvider()
        let model=PlayDeviceCaptureCoordinator(provider:provider,current:{context})
        XCTAssertTrue(model.supportsLibraryPhotos)
        await model.capture(.photo,usePhotoLibrary:true)
        XCTAssertEqual(provider.library,1);XCTAssertEqual(provider.ordinary,0);XCTAssertEqual(provider.framed,0)
    }
    func testUnavailableLibraryDoesNotOpenCameraInstead() async throws {
        let context=try context()
        let provider=PlaySyntheticDeviceProvider(supported:[.photo]) { _,_ in XCTFail("Must not substitute camera for requested library");return .unavailable }
        let model=PlayDeviceCaptureCoordinator(provider:provider,current:{context})
        XCTAssertFalse(model.supportsLibraryPhotos)
        await model.capture(.photo,usePhotoLibrary:true);XCTAssertTrue(provider.captured.isEmpty);XCTAssertNil(model.output)
    }
    func testPermissionReadbackIsObservationalAndNeverRequestsAccess() throws {
        let context=try context(), provider=PlayKitCameraTestProvider()
        let model=PlayDeviceCaptureCoordinator(provider:provider,current:{context})
        XCTAssertFalse(model.isAuthorizing);provider.authorizationInFlight=true;XCTAssertTrue(model.isAuthorizing)
        XCTAssertEqual(provider.ordinary+provider.library+provider.framed,0)
    }
    func testSessionReplacementDropsLateFramedPhoto() async throws {
        var current:PlayDeviceContext?=try context()
        let provider=PlayKitCameraTestProvider();provider.beforeReturn={current=nil}
        let model=PlayDeviceCaptureCoordinator(provider:provider,current:{current})
        await model.capture(.photo,cameraFrame:frame);XCTAssertNil(model.output);XCTAssertNil(model.uploadedPhoto)
    }
    func testCancellingSystemCaptureIsNotAnUnknownServerResult() async throws {
        let context=try context()
        let provider=PlaySyntheticDeviceProvider(supported:[.photo]) { _,_ in throw CancellationError() }
        let model=PlayDeviceCaptureCoordinator(provider:provider,current:{context})
        await model.capture(.photo);XCTAssertNil(model.output);XCTAssertNil(model.issue);XCTAssertFalse(model.busy)
    }
    func testDormantPhotoGrantNeverInvokesFrameOrLibrary() async throws {
        let context=try context(), provider=PlayKitCameraTestProvider(supported:[])
        let model=PlayDeviceCaptureCoordinator(provider:provider,current:{context})
        await model.capture(.photo,cameraFrame:frame);await model.capture(.photo,usePhotoLibrary:true)
        XCTAssertEqual(provider.framed+provider.library+provider.ordinary,0);XCTAssertNil(model.output)
    }
}

@MainActor private final class PlayKitCameraTestProvider: PlayKitFramedPhotoProviding, PlayKitPhotoLibraryProviding, PlayDevicePermissionStateProviding {
    var supported:Set<PlayDeviceKind>;var authorizationInFlight=false
    var ordinary=0,framed=0,library=0;var beforeReturn:(()->Void)?
    init(supported:Set<PlayDeviceKind>=[.photo]){self.supported=supported}
    func capture(_ kind:PlayDeviceKind,context:PlayDeviceContext) async throws->PlayDeviceOutput {ordinary+=1;beforeReturn?();return .photo(Data([1,2,3]),mimeType:"image/jpeg")}
    func capturePhoto(frame:PlayKitPhotoFrame,context:PlayDeviceContext) async throws->PlayDeviceOutput {framed+=1;beforeReturn?();return .photo(Data([1,2,3]),mimeType:"image/jpeg")}
    func captureLibraryPhoto(context:PlayDeviceContext) async throws->PlayDeviceOutput {library+=1;beforeReturn?();return .photo(Data([1,2,3]),mimeType:"image/jpeg")}
    func cancel(){}
}
