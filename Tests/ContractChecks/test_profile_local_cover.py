"""Focused local-cover source checks. No Swift execution or user-photo access."""
from pathlib import Path
import json, unittest
ROOT=Path(__file__).resolve().parents[2]
def read(path):return (ROOT/path).read_text()
class ProfileLocalCoverSourceChecks(unittest.TestCase):
 def setUp(self):
  self.core=read('Core/ProfileLocalCover.swift');self.store=read('Core/ProfileLocalCoverFileStore.swift');self.view=read('App/ProfileLocalCoverSection.swift')
 def test_account_and_self_public_entries_exist(self):
  account=read('App/AccountView.swift');public=read('App/SocialPublicProfileView.swift')
  self.assertIn('ProfileLocalCoverSection(owner: localCoverOwner, reader: session.socialAccountReader)',account)
  self.assertIn('localCoverOwner: localCoverOwner)',account)
  self.assertIn('if localCoverOwner?.accountID == memberID',public)
  self.assertIn('ProfileLocalCoverSection(owner: localCoverOwner, reader: reader, isCurrent: isCurrent)',public)
 def test_seventh_live_posts_entry_is_preserved(self):
  self.assertIn('ProfileAuthorPostsSection(memberID: memberID, accountReader: reader, squareReader: squareReader, actions: actions, isCurrent: isCurrent)',read('App/SocialPublicProfileView.swift'))
 def test_default_public_profile_does_not_receive_local_owner(self):
  self.assertIn('var localCoverOwner: ProfileLocalCoverOwner? = nil',read('App/SocialPublicProfileView.swift'))
 def test_owner_requires_account_and_bound_namespace(self):
  self.assertIn('guard accountID > 0, !namespace.isEmpty, namespace.utf8.count <= 4096',self.core)
  self.assertIn('namespace.utf8.count',self.core);self.assertIn('SHA256.hash(data:',self.core)
 def test_namespace_uses_existing_regional_identity_and_matching_build(self):
  for v in ['build.market == configuration.market.rawValue','build.baseURL == configuration.apiConfiguration?.baseURL.absoluteString','RegionalSessionStorageScope(configuration: configuration, bundleIdentifier: build.bundleIdentifier, realm: build.realm)','namespace: scope.service']:
   self.assertIn(v,self.view)
 def test_context_is_reader_revision_and_viewer_bound(self):
  for v in ['viewer = reader.identity','revision = reader.presentationRevision','ObjectIdentifier(reader)','viewer.accountID == owner.accountID','context.isOwnAccount && current() == context']:self.assertIn(v,self.core)
 def test_view_hides_other_accounts_before_reading(self):
  self.assertIn('if let owner, reader.identity.accountID == owner.accountID, isCurrent()',self.view)
  self.assertIn('}).id(context)',self.view)
 def test_local_preview_never_writes(self):
  prepare=self.core.split('public func prepare(_ image:')[1].split('public func prepareDefault')[0]
  self.assertNotIn('store.',prepare);self.assertIn('try Self.validate(image)',prepare)
 def test_cancel_review_never_writes(self):
  cancel=self.core.split('public func cancel(')[1].split('/// Synchronous')[0]
  self.assertNotIn('store.',cancel);self.assertIn('review = nil',cancel)
 def test_confirm_checks_immutable_review_and_cancellation(self):
  self.assertIn('guard !Task.isCancelled, canEdit, value.context == context, review == value else { return }',self.core)
 def test_commit_verifies_old_and_new_images(self):
  for v in ['guard Self.sameImage(persisted, saved)','try store.replace(value.image, owner: context.owner)','let verified = try store.read(owner: context.owner)','guard Self.sameImage(verified, value.image)']:self.assertIn(v,self.core)
  self.assertLess(self.core.index('guard Self.sameImage(verified, value.image)'),self.core.index('saved = verified; review = nil'))
 def test_failure_cannot_claim_success_and_requires_reread(self):
  self.assertIn('loaded = false; messageKey = "profile.localCover.changed"',self.core)
  self.assertIn('loaded = false; messageKey = "profile.localCover.failed"',self.core)
  self.assertIn('Button("profile.localCover.reload") { model.controller.load() }',self.view)
 def test_default_restore_is_explicit_review(self):
  self.assertIn('review = .init(context: context, image: nil)',self.core)
  self.assertIn('model.controller.prepareDefault()',self.view)
  self.assertIn('profile.localCover.restoreReview',self.view)
  self.assertIn('profile.localCover.restoreConfirm',self.view)
 def test_ratio_is_validated_before_persistence(self):
  self.assertIn('image.width * 9 == image.height * 16',self.core)
  self.assertIn('try ProfileLocalCoverController.validate(image)',self.store)
  self.assertIn('aspect: .gallery',self.view)
 def test_only_app_owned_file_is_removed(self):
  self.assertIn('directory.appendingPathComponent(owner.storageKey + ".cover")',self.store)
  self.assertIn('try files.removeItem(at: path)',self.store)
  for forbidden in ['PHPhotoLibrary','deleteAssets','removePersistentDomain','clearStorage']:self.assertNotIn(forbidden,self.store+self.view)
 def test_persistence_is_atomic_and_excluded_from_backup(self):
  self.assertIn('values.isExcludedFromBackup = true',self.store)
  self.assertIn('try root.setResourceValues(values)',self.store)
  self.assertIn('[.atomic, .completeFileProtection]',self.store)
 def test_file_load_checks_owner_version_and_bounds(self):
  for v in ['properties.isRegularFile == true','properties.isSymbolicLink != true','RetainedSelectedImage.maximumBytes + 16384','value.version == 1, value.owner == owner']:self.assertIn(v,self.store)
 def test_no_network_or_avatar_upload_capability(self):
  for v in ['HTTPTransport','URLSession','upload(', 'ProfileAvatarDependencies','RetainedImageScope(', 'Authorization','token:','getUploadClient','member_hero_bg']:
   self.assertNotIn(v,self.core+self.store+self.view)
 def test_picker_is_explicit_current_owner_selected_item_only(self):
  self.assertIn('Button("profile.localCover.choose") { model.pick() }',self.view)
  self.assertIn('pickerHost.makePicker { [weak self]',self.view)
  self.assertIn('self?.isPresented == true && self?.controller.canEdit == true',self.view)
  self.assertIn('let selected = try await picker.select()',self.view)
  for v in ['requestAuthorization','PHPhotoLibrary.request','UIImagePickerController','.camera']:self.assertNotIn(v,self.view)
 def test_existing_picker_is_bounded_sanitized_and_not_changed(self):
  s=read('App/RetainedNativeImagePicker.swift')
  for v in ['loadFileRepresentation','size <= RetainedSelectedImage.maximumInputBytes','RetainedImageSanitizer.sanitize(outcome.get())','config.selectionLimit = limit']:self.assertIn(v,s)
 def test_late_picker_completion_is_fenced(self):
  self.assertIn('guard !Task.isCancelled, run == self.generation, self.isPresented, self.controller.canEdit else { return }',self.view)
  self.assertIn('generation &+= 1; task?.cancel(); task = nil; picker?.cancel()',self.view)
 def test_crop_confirm_rechecks_ownership_and_crop_id(self):
  self.assertIn('guard isPresented, controller.canEdit, let crop, crop.id == id else { return }',self.view)
  self.assertIn('MerchantImageCropRenderer.render(crop.source, rect: rect)',self.view)
 def test_background_close_and_disappear_retire(self):
  self.assertIn('.onChange(of: scenePhase) { _, value in if value != .active { model.close() } }',self.view)
  self.assertIn('.onDisappear { model.retire() }',self.view)
  self.assertIn('func retire() { close(); controller.retire() }',self.view)
 def test_ui_states_device_only_and_uses_local_pixels(self):
  self.assertGreaterEqual(self.view.count('profile.localCover.deviceOnly'),2)
  self.assertIn('UIImage(data: selected.jpeg)',self.view)
  self.assertIn('pixels.width == selected.width, pixels.height == selected.height',self.view)
  self.assertIn('image.imageOrientation == .up',self.view)
  self.assertNotIn('NativeMediaGalleryEntry',self.view)
 def test_registrations_and_localizations(self):
  reg=json.loads(read('docs/profile-local-cover-registration.fragment.json'));loc=json.loads(read(reg['localization_fragment']))['strings']
  self.assertEqual(len(loc),18);self.assertEqual(reg['new_localization_keys'],18);self.assertEqual(reg['central_files_modified'],[])
  for v in loc.values():self.assertEqual(set(v['localizations']),{'en','zh-Hans'})
  self.assertIn('not uploaded',loc['profile.localCover.deviceOnly']['localizations']['en']['stringUnit']['value'])
 def test_synthetic_fixture_stages_real_editor_without_photo_library(self):
  f=read('App/ProfileLocalCoverFixture.swift')
  self.assertTrue(f.startswith('#if DEBUG'));self.assertIn('ProfileLocalCoverEnabledSection(model: model)',f)
  self.assertIn('ProfileLocalCoverSyntheticImage.make()',f);self.assertNotIn('.pick()',f)
 def test_native_tests_cover_full_local_flow(self):
  c=read('Tests/CoreTests/ProfileLocalCoverTests.swift');a=read('Tests/AppUnitTests/ProfileLocalCoverAppTests.swift');u=read('Tests/AppUITests/ProfileLocalCoverFlowTests.swift')
  self.assertEqual(c.count('func test'),18);self.assertEqual(a.count('func test'),9);self.assertEqual(u.count('func test'),5)
  for v in ['ReadbackFailure','CancelPreview','AccountAndDeployment','RevisionABA','ConcurrentCoverChange','MislabeledFileOwner']:self.assertIn(v,c)
  self.assertNotIn('"profile.localCover.choose"',u)
if __name__=='__main__':unittest.main()
