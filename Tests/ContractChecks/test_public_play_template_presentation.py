"""Public-template source/presentation guards; static checks are not Apple execution."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PublicPlayTemplatePresentationContracts(unittest.TestCase):
    def read(self, name):
        return (ROOT / name).read_text()

    def test_only_current_public_dto_images_form_ordered_bounded_gallery(self):
        model = self.read('Core/DiscoveryPlayTemplatePresentation.swift')
        self.assertIn('for raw in [item.imgUrl, item.storyImg]', model)
        self.assertIn('!sources.contains(source)', model)
        self.assertIn('parts.scheme == "https"', model)
        self.assertIn('parts.user == nil, parts.password == nil', model)
        self.assertIn('CharacterSet.controlCharacters.contains', model)
        self.assertIn('value.removingPercentEncoding != nil', model)
        self.assertIn('value.utf8.count <= 8192', model)
        for forbidden in ['item.imgUrls', 'item.memberId', 'item.collaborators', 'URLSession', 'isOwner', 'isPurchased', 'isOfficial']:
            self.assertNotIn(forbidden, model)
        contract = self.read('Core/DiscoveryContracts.swift')
        self.assertNotIn('public let imgUrls', contract)
        self.assertNotIn('creatorNote', contract)
        self.assertIn('guard useNum.map({ $0 >= 0 }) ?? true', contract)

    def test_independent_attribution_narrative_image_only_and_unknown_counts(self):
        model = self.read('Core/DiscoveryPlayTemplatePresentation.swift')
        for text in ['publisher = Self.nonempty(item.publisher)', 'storyText = Self.nonempty(item.storyText)',
                     'useCount = item.useNum', 'storyText != nil || storyImage != nil']:
            self.assertIn(text, model)
        view = self.read('App/DiscoveryPlayTemplatePresentationView.swift')
        for text in ['if let publisher = presentation.publisher', 'if let count = presentation.useCount',
                     'if presentation.hasStory', 'if presentation.storyImage != nil',
                     'Text(verbatim: publisher)', 'Text(verbatim: text)', 'NativeMediaGalleryEntry(',
                     'scope: scope', 'reader: imageReader']:
            self.assertIn(text, view)
        for forbidden in ['NavigationLink', 'URLSession', 'AsyncImage', 'isOfficial', 'memberId', '.lineLimit(']:
            self.assertNotIn(forbidden, view)

    def test_existing_media_gate_and_owner_namespace_remain_separate(self):
        view = self.read('App/DiscoveryTemplateDetailView.swift').split('/// Uses only the server', 1)[0]
        self.assertIn('imageReader ?? RetainedPublicImageReader()', view)
        self.assertIn('if let authoringFactory', view)
        self.assertIn('TemplateAuthoringView(coordinator: authoringFactory(item)', view)
        self.assertNotIn('DiscoveryArtwork', view)
        self.assertNotIn('AsyncImage', view)
        self.assertNotIn('enabled: true', view)
        gallery = self.read('App/NativeMediaGallery.swift')
        self.assertIn('.onChange(of: scope)', gallery)
        self.assertIn('.onChange(of: sources)', gallery)
        self.assertIn('focusedImageIndex = returnFocusIndex', gallery)
        self.assertIn('reader.enabled', gallery)
        self.assertIn('RetainedImageSanitizer.sanitize', gallery)
        self.assertIn('NativeMediaGalleryEntry(sources: part.images, scope: reader.scope', self.read('App/MemberTemplateDetailView.swift'))

    def test_reload_scope_identity_and_exact_public_id_are_fenced(self):
        view = self.read('App/DiscoveryTemplateDetailView.swift').split('/// Uses only the server', 1)[0]
        for text in ['ObjectIdentifier(reader)', 'scope: reader.discoveryPresentationIdentity',
                     'loadedKey != requestKey', '.task(id: requestKey)',
                     '.onReceive(reader.discoveryPresentationChanges)', 'galleryScope = UUID(); loadedKey = nil',
                     'requested.scope == reader.discoveryPresentationIdentity', 'value.id == requested.id',
                     'guard !Task.isCancelled, requested == requestKey']:
            self.assertIn(text, view)
        scope = self.read('App/DiscoveryPresentationScope.swift')
        self.assertIn('sessionRevision', scope)
        self.assertIn('contentDetailRevision', scope)
        self.assertIn('objectWillChange.eraseToAnyPublisher()', scope)
        service = self.read('Core/DiscoveryService.swift').split('public func playTemplate(id:', 1)[1].split('private func post', 1)[0]
        self.assertIn('post("api/template/info", fields: ["id": String(id)]', service)
        self.assertIn('guard detail.id == id else { throw APIError.malformedResponse }', service)
        for forbidden in ['myinfo', 'scope', 'memberId', 'purchase', 'unlock']:
            self.assertNotIn(forbidden, service)

    def test_localization_and_authored_runtime_cases(self):
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        for suffix in ['publisher', 'useCount', 'images', 'story', 'storyImageInGallery']:
            self.assertEqual(set(catalog['discovery.template.' + suffix]['localizations']), {'en', 'zh-Hans'})
        tests = self.read('Tests/CoreTests/DiscoveryPlayTemplatePresentationTests.swift')
        for name in ['PublisherStoryAndKnownUseCountStayIndependent', 'PublisherOnlyNeverBecomesStoryAndMissingAuthorNeverBecomesOfficial',
                     'OnlyCurrentDTOCoverThenStoryFormTheBoundedGallery', 'DuplicateAndWhitespaceImagesKeepFirstPositionWithoutLosingImageOnlyStory',
                     'MissingNullAndBlankContentRemainUnknownWithoutFabricatedZero', 'MalformedImageShapesAndCountsAreNotSilentlyCoerced',
                     'UnsafeImagesAreOmittedWithoutOriginOrNetworkAuthority', 'ReadOnlyProjectionNeverImportsSecretsOwnerOrPurchaseAuthority',
                     'PublicReadRejectsMismatchedAndMalformedIdentityWithoutOwnerNamespace']:
            self.assertIn('func test' + name, tests)
        ui = self.read('Tests/AppUITests/PublicPlayTemplatePresentationFlowTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', ui)), 6)
        fixture = self.read('App/PublicPlayTemplateFixtureHost.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('DiscoveryTemplateBrowserView(reader: reader, imageReader: imageReader)', fixture)
        self.assertIn('RetainedPublicImageReader(enabled: true, origins: [])', fixture)
        self.assertIn('NativePresentationImageReader()', fixture)
        self.assertNotIn('URLSession', fixture)


if __name__ == '__main__':
    unittest.main()
