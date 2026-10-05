"""Inert native article structure and authored tests; not parser execution or Apple acceptance."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SocialArticleContentChecks(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_renderer_is_wired_only_to_existing_scoped_article_contents(self):
        guide = self.read('App/SocialGuideViews.swift')
        self.assertEqual(guide.count('SocialArticleContentView(contents: contents)'), 1)
        for token in ['if id <= 0', 'reader.information(id: id)', 'requestKey: "information-\\(id)"',
                      'if row.isRemoved', 'Text("social.guide.noContent")']:
            self.assertIn(token, guide)
        screen = self.read('App/SocialAccountComponents.swift')
        for token in ['loadedKey != key || busy', 'try Task.checkCancellation()',
                      'guard generation == run, key == captured',
                      '.task(id: key)', '.onDisappear { loads.cancel(); generation += 1; busy = false }']:
            self.assertIn(token, screen)

    def test_pure_projection_has_fixed_input_output_work_and_depth_caps(self):
        core = self.read('Core/SocialArticleContent.swift')
        for token in ['maximumSourceScalars = 65_536', 'maximumOutputScalars = 32_768',
                      'maximumBlocks = 256', 'maximumRuns = 512', 'maximumDepth = 32',
                      'maximumTokens = 4_096', 'maximumTagScalars = 1_024',
                      '.prefix(Article.maximumSourceScalars + 1)', 'tokens <= Article.maximumTokens',
                      'outputCount < Article.maximumOutputScalars', 'blocks.count < Article.maximumBlocks',
                      'runCount < Article.maximumRuns', 'styles.count < Article.maximumDepth',
                      'lists.count < Article.maximumDepth', 'quoteDepth < Article.maximumDepth',
                      'suppressedDepth > Article.maximumDepth', 'end - index <= 32']:
            self.assertIn(token, core)
        for token in ['URLSession', 'URLRequest', 'import WebKit', 'NSAttributedString',
                      '.regularExpression', 'try!']:
            self.assertNotIn(token, core)

    def test_text_is_literal_and_has_no_resource_or_link_execution_surface(self):
        view = self.read('App/SocialArticleContentView.swift')
        for token in ['Text(verbatim: run.text)', 'Text(verbatim: marker)', '.textSelection(.enabled)',
                      '.fixedSize(horizontal: false, vertical: true)', '.accessibilityAddTraits(.isHeader)',
                      '.accessibilityElement(children: .combine)', 'Text("social.guide.noContent")',
                      'Text("social.article.limited")', 'min(depth, 4)']:
            self.assertIn(token, view)
        for token in ['Link(', 'Button(', 'NavigationLink', 'openURL', 'WebView', 'WKWebView',
                      'AsyncImage', 'Image(', 'URLSession', '.task', 'AttributedString(markdown:', '.lineLimit(']:
            self.assertNotIn(token, view)
        core = self.read('Core/SocialArticleContent.swift')
        for tag in ['script', 'style', 'iframe', 'object', 'svg', 'math', 'template', 'canvas',
                    'video', 'audio', 'noscript', 'img', 'embed', 'source', 'track', 'link', 'meta']:
            self.assertIn('"' + tag + '"', core)
        self.assertIn('if suppressed != nil', core)
        self.assertIn('unknown names stay literal', core)

    def test_limitation_is_generic_bilingual_and_not_server_authored(self):
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        entry = catalog['social.article.limited']['localizations']
        self.assertEqual(set(entry), {'en', 'zh-Hans'})
        for value in entry.values():
            self.assertTrue(value['stringUnit']['value'].strip())
        self.assertNotIn('error.localizedDescription', self.read('App/SocialArticleContentView.swift'))

    def test_adversarial_and_repeated_flow_coverage_is_authored(self):
        core = self.read('Tests/CoreTests/SocialArticleContentTests.swift')
        for name in ['testPlainTextKeepsLineBreaksMixedLanguageAndLiteralMarkdown',
                     'testNestedListsKeepNumberingAndSafeDepth', 'testEntitiesDecodeOnceWithoutCreatingMarkup',
                     'testUnknownAndInvalidEntitiesStayInert', 'testLinksAndEventAttributesRetainOnlyVisibleText',
                     'testExecutableSubtreesAndRemoteMediaCannotBecomeTextOrActions',
                     'testNestedSuppressedSubtreesAndCommentsRemainOmitted',
                     'testRawTextInsideOmittedContainersCannotEndOuterSuppression',
                     'testScriptAndStyleRawTextIgnoreApparentTagsCommentsAndQuotes',
                     'testInvalidActiveEndTagNamesCannotExposeHiddenText',
                     'testLegacyDoubleEscapedScriptStopsWithoutExposingItsSuffix',
                     'testPlainTextLiteralAnglePreservesInstructionLineBreaks',
                     'testMalformedMarkupReturnsBoundedReadablePrefix', 'testOversizedInputAndOutputAreExplicitlyLimited',
                     'testBlockBudgetIsEnforcedWithoutFabricatedEllipsis', 'testRunBudgetBoundsAlternatingFormatting',
                     'testDeepFormattingListsAndSuppressedSubtreesStopSafely', 'testTokenAndTagBudgetsAreEnforced']:
            self.assertIn('func ' + name, core)
        ui = self.read('Tests/AppUITests/SocialAccountFlowTests.swift')
        for name in ['testHTMLArticleIsReadableInertAndReopensAfterBack',
                     'testChineseLargeTextArticleReplacesOldContentAfterAccountSwitch',
                     'testArticleRemovedEmptyAndReadFailureKeepExistingRecovery']:
            self.assertIn('func ' + name, ui)
        fixture = self.read('App/SocialAccountFixtureSupport.swift')
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertNotIn('URLSession', fixture)
        self.assertIn('informationAttempts == 1', fixture)
        self.assertIn('identity.accountID == 81 ? "Synthetic article heading', fixture)


if __name__ == '__main__':
    unittest.main()
