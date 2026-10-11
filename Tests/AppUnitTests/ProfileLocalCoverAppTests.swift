import XCTest
import UIKit
@testable import Questify

@MainActor final class ProfileLocalCoverAppTests: XCTestCase {
    private func make(_ store: ProfileLocalCoverFixtureStore, reader: ProfileAuthorPostsRefreshFixtureReader) throws -> ProfileLocalCoverModel {
        let owner=try ProfileLocalCoverOwner(accountID:81,namespace:"synthetic-local-cover"), context=ProfileLocalCoverContext(owner:owner,reader:reader)
        let model=ProfileLocalCoverModel(context:context,store:store,current:{ .init(owner:owner,reader:reader) })
        model.controller.load(); return model
    }
    func testSyntheticBitmapHasExactRatioAndCanDecode() throws {
        let image=try ProfileLocalCoverSyntheticImage.make(); try ProfileLocalCoverController.validate(image)
        let pixels=try XCTUnwrap(UIImage(data:image.jpeg)?.cgImage)
        XCTAssertEqual(pixels.width * 9,pixels.height * 16)
    }
    func testCropPreviewDoesNotPersistUntilExplicitConfirm() throws {
        let r=ProfileAuthorPostsRefreshFixtureReader(), s=ProfileLocalCoverFixtureStore(), m=try make(s,reader:r)
        m.open(); let source=try ProfileLocalCoverSyntheticImage.make(), crop=MerchantImageCropDraft(source:source,aspect:.gallery)
        m.crop=crop; let rect=try MerchantImageCropRect(sourceWidth:source.width,sourceHeight:source.height,aspect:.gallery,zoom:2)
        m.acceptCrop(id:crop.id,rect:rect); XCTAssertEqual(s.writes,0)
        let review=try XCTUnwrap(m.controller.review); XCTAssertEqual(review.image?.width,160); XCTAssertEqual(review.image?.height,90)
        m.confirm(review); XCTAssertEqual(s.writes,1); XCTAssertFalse(m.isPresented); XCTAssertNotNil(m.controller.saved)
    }
    func testCropCancelAndSheetCloseNeverPersist() throws {
        let r=ProfileAuthorPostsRefreshFixtureReader(), s=ProfileLocalCoverFixtureStore(), m=try make(s,reader:r)
        m.open(); m.crop = .init(source:try ProfileLocalCoverSyntheticImage.make(),aspect:.gallery); m.cancelCrop()
        XCTAssertNil(m.crop); m.controller.prepare(try ProfileLocalCoverSyntheticImage.make()); m.close()
        XCTAssertNil(m.controller.review); XCTAssertEqual(s.writes,0)
    }
    func testStaleCropIDCannotCreateReview() throws {
        let r=ProfileAuthorPostsRefreshFixtureReader(), s=ProfileLocalCoverFixtureStore(), m=try make(s,reader:r)
        m.open(); let image=try ProfileLocalCoverSyntheticImage.make(); m.crop = .init(source:image,aspect:.gallery)
        m.acceptCrop(id:UUID(),rect:try .init(sourceWidth:image.width,sourceHeight:image.height,aspect:.gallery))
        XCTAssertNil(m.controller.review); XCTAssertEqual(s.writes,0)
    }
    func testAccountSwitchRejectsPreparedCropAndReview() throws {
        let r=ProfileAuthorPostsRefreshFixtureReader(), s=ProfileLocalCoverFixtureStore(), m=try make(s,reader:r)
        m.open(); m.controller.prepare(try ProfileLocalCoverSyntheticImage.make()); let review=try XCTUnwrap(m.controller.review)
        r.switchAccount(); m.confirm(review); XCTAssertEqual(s.writes,0); XCTAssertFalse(m.controller.ownsContext)
    }
    func testRetirementCancelsUnsavedPhotoAndReview() throws {
        let r=ProfileAuthorPostsRefreshFixtureReader(), s=ProfileLocalCoverFixtureStore(), m=try make(s,reader:r)
        m.open(); m.controller.prepare(try ProfileLocalCoverSyntheticImage.make()); m.retire()
        XCTAssertFalse(m.isPresented); XCTAssertNil(m.crop); XCTAssertNil(m.controller.review); XCTAssertNil(m.controller.saved); XCTAssertEqual(s.writes,0)
    }
    func testLocalSaveFailureKeepsSheetAndNeverReportsSuccess() throws {
        let r=ProfileAuthorPostsRefreshFixtureReader(), s=ProfileLocalCoverFixtureStore(), m=try make(s,reader:r)
        m.open(); m.controller.prepare(try ProfileLocalCoverSyntheticImage.make()); s.fails=true; m.confirm(try XCTUnwrap(m.controller.review))
        XCTAssertTrue(m.isPresented); XCTAssertEqual(m.controller.messageKey,"profile.localCover.failed"); XCTAssertEqual(s.writes,0)
    }
    func testDefaultReviewUsesSameExplicitCommitPath() throws {
        let r=ProfileAuthorPostsRefreshFixtureReader(), s=ProfileLocalCoverFixtureStore(), m=try make(s,reader:r)
        m.open(); m.controller.prepare(try ProfileLocalCoverSyntheticImage.make()); m.confirm(try XCTUnwrap(m.controller.review))
        m.open(); m.controller.prepareDefault(); let review=try XCTUnwrap(m.controller.review); XCTAssertNil(review.image); m.confirm(review)
        XCTAssertNil(m.controller.saved); XCTAssertEqual(s.writes,2)
    }
    func testOwnerFactoryRequiresMatchingBuildAndBindsRealm() throws {
        let base="https://profile.example/native"
        let config=try RegionalConfiguration(market:.china,baseURL:base,approvedBaseURLs:[.china:[base]],verifiedCapabilities:[])
        let build=RegionalLaunchConfiguration.BuildMetadata(market:RegionalMarket.china.rawValue,baseURL:base,bundleIdentifier:"test.profile.cover",realm:"synthetic-a")
        let a=try XCTUnwrap(ProfileLocalCoverOwner.make(accountID:7,configuration:config,build:build))
        let other=RegionalLaunchConfiguration.BuildMetadata(market:RegionalMarket.china.rawValue,baseURL:base,bundleIdentifier:"test.profile.cover",realm:"synthetic-b")
        XCTAssertNotEqual(a,ProfileLocalCoverOwner.make(accountID:7,configuration:config,build:other))
        let mismatch=RegionalLaunchConfiguration.BuildMetadata(market:RegionalMarket.china.rawValue,baseURL:"https://other.example/native",bundleIdentifier:"test.profile.cover",realm:"synthetic-a")
        XCTAssertNil(ProfileLocalCoverOwner.make(accountID:7,configuration:config,build:mismatch)); XCTAssertNil(ProfileLocalCoverOwner.make(accountID:7,configuration:nil,build:build))
    }
}
