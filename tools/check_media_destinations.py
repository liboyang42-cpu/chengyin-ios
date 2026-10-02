#!/usr/bin/env python3
"""Native structural/source contract checks only; no Swift or device execution."""
from pathlib import Path
import json, re
r=Path(__file__).resolve().parents[1]
def text(name): return (r/name).read_text()
def expect(name,*parts):
 s=text(name)
 for p in parts: assert p in s,(name,p)
expect('App/NativeMediaGallery.swift','fullScreenCover(item:', 'TabView(selection:', 'NativeZoomImage', 'RetainedImageSanitizer.sanitize', 'self.reader = reader ?? RetainedPublicImageReader()', 'maximumZoomScale = 5')
assert 'AsyncImage' not in text('App/NativeMediaGallery.swift')
expect('Core/RoamMerchant.swift','case id, name, cityRole, storyTitle, description, tags, gallery','prefix(100)')
expect('App/RoamItemDetailView.swift','NativeMediaGalleryEntry(sources: merchant.gallery','posterDestination(node)','stampDestination()')
expect('App/SquareBrowserView.swift','showImages: false','NativeMediaGalleryEntry(sources: post.images, scope: reader.scope')
expect('App/SquareDetailView.swift','NativeMediaGalleryEntry(sources: comment.images, scope: reader.scope')
expect('App/RoamStampCameraView.swift','picker.sourceType = .camera','RoamStampPixelCrop.render','AVCaptureDevice.requestAccess','captureGeneration','cameraEnabled = false','4:5')
assert 'PhotosPicker' not in text('App/RoamStampCameraView.swift')
expect('Core/RetainedImageContracts.swift','case stamp','case roamPoster(poiID: Int)','name=\\"bizType\\"\\r\\n\\r\\nstamp')
expect('Core/RoamStampCaptureCoordinator.swift','try self.storage.save(record','uploads.applyLocally','idempotencyKey: pending.idempotencyKey','ticket == generation','scope: scope','RoamStampCreatedReceipt.self')
expect('Core/RoamMediaMutationService.swift','enabled: Bool = false','approval: OperationEndpointApproval? = nil','approvedImageOrigins: Set<String> = []','case .completeNode(let id','captured.destination == .roamPoster(poiID: id)')
expect('Core/RoamPosterCoordinator.swift','node.completed','node.needRedeem','node.canInteract == false','node.validationMethod != 4','fix.datum == .gcj02','try journal.write(pending)','case .rejected','refreshNode')
expect('App/AppSession.swift','func makeRoamStampCaptureCoordinator','func makeRoamPosterCoordinator','enabled: factory.permits(.stampUpload), approvedOrigins: factory.configuration.stampImageOrigins','DisabledRoamPosterLocation()')
expect('App/QuestifyApp.swift','stampDestination: { AnyView(SessionRoamStampCameraView()) }','posterDestination: { AnyView(SessionRoamPosterView(node: $0)) }')
expect('Core/WalletCommerceService.swift','api/user/info','["member_id": String(memberID)]')
expect('App/WithdrawalSupportLandingView.swift','withdrawalBalance(memberID: scope.accountID','stages(token: $1)','loadedScope == reader.scope','contact: WithdrawalSupportContact? = nil')
# Every new key is bilingual. Dynamic phase keys are covered explicitly by the fragment.
fragment=json.loads(text('Resources/MediaDestinationsLocalizations.fragment.json'))['strings']
for key,item in fragment.items():
 for lang in ['en','zh-Hans']: assert item['localizations'][lang]['stringUnit']['value']
for name in ['App/NativeMediaGallery.swift','App/RoamPosterScanView.swift','App/RoamStampCameraView.swift','App/WithdrawalSupportLandingView.swift']:
 for key in re.findall(r'"((?:media\.(?:destination|stamp|poster)|withdrawal\.support)\.[A-Za-z]+)"',text(name)):
  if key.endswith('.phase') or key.endswith('.destination') or key in ['media.poster.open']: continue
  if key not in fragment: assert key in ['withdrawal.support.landing'],key
assert len(re.findall('func test',text('Tests/CoreTests/MediaDestinationsTests.swift'))) >= 15
assert len(re.findall('func test',text('Tests/AppUnitTests/RoamStampPixelTests.swift'))) == 2
print('PASS media destination structural contracts; Swift/Apple/device/visual tests NOT_RUN')

poster = text('Core/RoamPosterCoordinator.swift')
submit = poster.split('public func submit() async {', 1)[1].split('public func cancel()', 1)[0]
assert submit.index('guard phase == .review else { return }') < submit.index('try await refreshNode()')
assert submit.index('phase = .preflighting; changed?()') < submit.index('try await refreshNode()')
assert submit.index('self.command = nil; self.expires = nil; phase = .preflighting') < submit.index('try await refreshNode()')
assert submit.index('generation += 1; let ticket = generation') < submit.index('try await refreshNode()')
assert 'ticket == generation, phase == .preflighting, !Task.isCancelled' in submit
for name in ['testConcurrentPosterConfirmDuringDelayedRefreshDispatchesOnce', 'testCancelPosterDuringPreflightCannotDispatch', 'testCancelPosterTaskDuringPreflightCannotDispatch']:
 assert name in text('Tests/CoreTests/MediaDestinationsTests.swift')
print('PASS poster one-use preflight and cancellation structural regression checks; Swift runtime NOT_RUN locally')
