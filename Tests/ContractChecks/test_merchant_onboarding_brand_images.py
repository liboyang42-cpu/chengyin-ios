from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[2]
class BrandImageContracts(unittest.TestCase):
 @classmethod
 def setUpClass(c):
  c.core=(R/'Core/MerchantOnboardingBrandImages.swift').read_text();c.draft=(R/'Core/MerchantOnboardingContracts.swift').read_text();c.model=(R/'App/MerchantOnboardingModel.swift').read_text();c.ui=(R/'App/MerchantOnboardingBrandImagesView.swift').read_text();c.host=(R/'App/MerchantOnboardingView.swift').read_text()
 def test_six_image_source_limit(self):self.assertIn('static let limit = 6',self.core)
 def test_ordered_source_wire(self):self.assertIn('urls.joined(separator: ",")',self.core);self.assertNotIn('Set(',self.core)
 def test_explicit_clear_preserved(self):self.assertIn('if let brandImages { fields["derivatives"] = brandImages.wireValue }',self.draft)
 def test_legacy_untouched_payload_omission(self):self.assertIn('public var brandImages: MerchantOnboardingBrandImages?',self.draft)
 def test_unknown_source_not_cleared(self):self.assertIn('brandImagesSourceUnavailable = brandImages == nil',self.draft);self.assertIn('!draft.brandImagesSourceUnavailable',self.model)
 def test_existing_safe_url_admission(self):self.assertIn('MerchantOnboardingLicense(serverURL: raw)',self.core);self.assertIn('!value.contains(",")',self.core)
 def test_existing_photo_adapter_only(self):self.assertIn('MerchantOnboardingPhotoAdapter.load(item)',self.model);self.assertNotIn('PHPhotoLibrary',self.ui)
 def test_selection_never_uploads(self):
  x=self.model.split('func selectBrandImage(load:')[1].split('func discardBrandImage')[0];self.assertNotIn('uploadLicense',x)
 def test_upload_explicit_confirmation(self):self.assertIn('.confirmationDialog("merchant.onboardingBrand.uploadTitle"',self.ui);self.assertIn('uploadSelectedBrandImage(expectedID: uploadID)',self.ui)
 def test_existing_upload_service_reused(self):self.assertIn('coordinator.uploadLicense(image, expectedIdentity: identity)',self.model);self.assertNotIn('URLSession',self.ui+self.core)
 def test_upload_never_assigns_license(self):
  x=self.model.split('func uploadSelectedBrandImage')[1].split('func prepare()')[0];self.assertNotIn('draft.license =',x);self.assertIn('draft.brandImages = images',x)
 def test_stale_identity_draft_generation(self):
  x=self.model.split('func selectBrandImage(load:')[1].split('func prepare()')[0]
  for s in ['request == generation','identity == coordinator.identity','draft == original','selectedBrandDraft == draft','selectedBrandImageID == expectedID']:self.assertIn(s,x)
 def test_old_remove_rejected(self):self.assertIn('expected == draft.brandImages',self.model)
 def test_picker_bound_to_original_identity(self):self.assertIn('pickerIdentity == model.coordinator.identity, pickerDraft == model.draft',self.ui)
 def test_pending_photo_blocks_progress(self):self.assertIn('if step == 3, selectedBrandImage != nil',self.model);self.assertIn('guard selectedBrandImage == nil else',self.model)
 def test_host_step_three_and_review(self):self.assertIn('MerchantOnboardingBrandImagesEditor(model: model',self.host);self.assertIn('MerchantOnboardingBrandImageRows(images: model.draft.brandImages)',self.host)
 def test_existing_no_permission_picker(self):self.assertIn('.photosPicker(isPresented: $pickerPresented',self.ui);self.assertNotIn('requestAuthorization',self.ui)
 def test_parent_lifecycle_preserves_new_child_presentations(self):self.assertIn('!showBrandPhotos, !showBrandUploadConfirmation',self.host)
if __name__=='__main__':unittest.main()
