#!/usr/bin/env python3
"""Source/structural checks only. Does not execute Swift, PhotosUI or network requests."""
from pathlib import Path
import json, re, hashlib
root = Path(__file__).resolve().parents[1]
source = root.parent / 'app-audit/lib'
def read(p): return (root / p).read_text()
core=read('Core/RetainedImageContracts.swift'); picker=read('App/RetainedNativeImagePicker.swift')
bridge=read('Core/RetainedImageConsumerBridges.swift'); writes=read('Core/PublicMerchantReviewWrites.swift')
coordinator=read('Core/PublicMerchantReviewCoordinator.swift'); ui=read('App/RetainedImageSelectionView.swift')
assert "'/api/common/uploadOSS'" in (source/'data/api/play_api.dart').read_text()
assert "return body['url'].toString()" in (source/'data/api/play_api.dart').read_text()
assert 'api/common/uploadOSS' in core and 'let url: String?' in core
assert 'fileprivate init(review:' in core and 'enabled: Bool = false' in core and 'approvedOrigins: Set<String> = []' in core
assert 'review.scope.realm == configuration.baseURL.absoluteString' in core
assert 'currentScope() == review.scope, token() == auth' in core
assert 'case .uploading, .unknown: return true' in core
assert 'state = locked ? .unknown : .idle' in core
assert 'CGImageSourceCreateThumbnailAtIndex' in picker and 'CGImageSourceGetCount(source) == 1' in picker
assert 'width <= 100_000_000 / height' in picker and 'fileSizeKey' in picker
assert 'UIGraphicsImageRenderer' in picker and 'onCancel:' in picker and 'presentationControllerDidDismiss' in picker
assert 'currentScope() == scope' in picker and 'purpose == .selection' in picker
assert 'images: [RetainedUploadedImage] = []' in writes and 'images.count <= 9' in writes
assert '"imageUrls": images.map' in writes and 'try command.validateImages' in writes
assert 'try review.command.validateImages' in coordinator
assert 'namespace == npc.namespace' in bridge and 'let namespace = scope.namespace' in bridge
assert 'scope.epoch == session.scope' in bridge and 'scope.accessRevision == npc.accessRevision' in bridge
assert 'case (.gallery, .gallery' in bridge and 'd.gallery.count < 9' in bridge
assert 'd.id == scope.resourceID' in bridge
reader=read('Core/RetainedPublicImageReader.swift')
assert 'completionHandler(nil)' in reader and 'maximumInputBytes - bytes.count' in reader
assert 'config.urlCredentialStorage = nil' in reader and 'config.httpCookieStorage = nil' in reader
assert 'RetainedPublicReviewImages' in read('App/PublicMerchantReviewsView.swift')
assert 'image.applying(to: draft' in read('App/MerchantOperationsEditor.swift')
for field in ['logo','coverImage','gallery','avatar','imgUrl']: assert field in bridge
assert 'pickAndUploadImages' in (source/'feature/merchant/node_template_edit_page.dart').read_text()
assert '_uploadedImages.addAll(uploaded)' in (source/'feature/merchant/merchant_public_reviews_page.dart').read_text()
assert "_draft.copyWith(avatar: urls.first)" in (source/'feature/merchant/merchant_npc_edit_page.dart').read_text()
assert 'IMExpandedService' not in core+bridge and 'uploadCommunityImage' not in core
assert 'requestAuthorization(' not in picker and 'AVCapture' not in picker
catalog=json.loads(read('Resources/RetainedImagesLocalizations.fragment.json'))['strings']
keys=set(re.findall(r'"(image\.retained\.[A-Za-z]+)"','\n'.join(p.read_text() for p in (root/'App').glob('*.swift'))))
# Accessibility IDs are intentionally not localized.
for key in keys:
 if key in catalog:
  for lang in ['en','zh-Hans']: assert catalog[key]['localizations'][lang]['stringUnit']['value']
assert len(catalog)==17
assert len(re.findall(r'func test',read('Tests/CoreTests/RetainedImageConsumerTests.swift')))==10
assert len(re.findall(r'func test',read('Tests/AppUnitTests/RetainedImageSanitizerTests.swift')))==4
assert len(re.findall(r'func test',read('Tests/AppUITests/RetainedImageUITests.swift')))==3
print('PASS retained image source/structural checks; 10 core + 4 app-unit + 3 UI tests AUTHORED, NOT_RUN')
