import XCTest
@testable import QuestifyCore

final class SocialArticleContentTests: XCTestCase {
    private func text(_ source: String) -> [String] { SocialArticleContent(source).blocks.map(\.text) }

    func testPlainTextKeepsLineBreaksMixedLanguageAndLiteralMarkdown() {
        let article = SocialArticleContent("English 中文\n**literal** [label](https://example.invalid) &amp; text")
        XCTAssertEqual(article.blocks.map(\.text), ["English 中文\n**literal** [label](https://example.invalid) & text"])
        XCTAssertFalse(article.isLimited)
        XCTAssertEqual(article.blocks.first?.kind, .paragraph)
    }
    func testParagraphsHeadingsAndQuotesRetainOrder() {
        let article = SocialArticleContent("<h1>Title</h1><p>First</p><h3>Details</h3><blockquote><p>Quoted</p><p>Again</p></blockquote><p>Last</p>")
        XCTAssertEqual(article.blocks.map(\.text), ["Title", "First", "Details", "Quoted", "Again", "Last"])
        XCTAssertEqual(article.blocks.map(\.kind), [.heading(1), .paragraph, .heading(3), .quote, .quote, .paragraph])
        XCTAssertFalse(article.isLimited)
    }
    func testBasicEmphasisIsExplicitRunsRatherThanMarkdown() {
        let article = SocialArticleContent("<p>Plain <strong>bold <em>both</em></strong> <i>italic</i>.</p>")
        XCTAssertEqual(article.blocks.first?.text, "Plain bold both italic.")
        let runs = article.blocks[0].runs
        XCTAssertTrue(runs.contains { $0.text == "bold " && $0.bold && !$0.italic })
        XCTAssertTrue(runs.contains { $0.text == "both" && $0.bold && $0.italic })
        XCTAssertTrue(runs.contains { $0.text == "italic" && !$0.bold && $0.italic })
    }
    func testNestedListsKeepNumberingAndSafeDepth() {
        let article = SocialArticleContent("<ol><li>First<ul><li>Nested</li></ul></li><li><p>Second</p></li></ol>")
        XCTAssertEqual(article.blocks.map(\.text), ["First", "Nested", "Second"])
        XCTAssertEqual(article.blocks.map(\.kind), [.listItem(marker: "1.", depth: 0), .listItem(marker: "•", depth: 1), .listItem(marker: "2.", depth: 0)])
    }
    func testEmptyListItemDoesNotStyleLaterParagraphAsAList() {
        let article = SocialArticleContent("<ul><li></li></ul><p>After</p>")
        XCTAssertEqual(article.blocks.map(\.text), ["After"])
        XCTAssertEqual(article.blocks.first?.kind, .paragraph)
    }
    func testBreaksAndHTMLWhitespaceAreReadable() {
        XCTAssertEqual(text("<p>  One\n  two<br>Three<br/>Four </p>"), ["One two\nThree\nFour"])
        XCTAssertEqual(text("1 < 2 and 3 > 2"), ["1 < 2 and 3 > 2"])
    }
    func testEntitiesDecodeOnceWithoutCreatingMarkup() {
        XCTAssertEqual(text("&lt;script&gt;literal&lt;/script&gt; &amp;lt; &#20013;&#x6587; &quot;x&quot; &apos;y&apos;"), ["<script>literal</script> &lt; 中文 \"x\" 'y'"])
        XCTAssertEqual(text("<p>&nbsp;&copy;&reg;&trade;&mdash;&ndash;&bull;&hellip;&laquo;&raquo;</p>"), ["\u{00a0}©®™—–•…«»"])
    }
    func testUnknownAndInvalidEntitiesStayInert() {
        XCTAssertEqual(text("&unknown; &amp &#0; &#xD800; &#x110000; &#999999999999999999999999;"), ["&unknown; &amp � � � �"])
    }
    func testLinksAndEventAttributesRetainOnlyVisibleText() {
        let article = SocialArticleContent("<p onclick='attack()'>Keep <a href='javascript:attack()' target='_blank'>label</a> <a href='https://example.invalid/file'>file label</a></p>")
        XCTAssertEqual(article.blocks.map(\.text), ["Keep label file label"])
        XCTAssertFalse(article.blocks[0].text.contains("attack"))
        XCTAssertFalse(article.blocks[0].text.contains("example.invalid"))
    }
    func testExecutableSubtreesAndRemoteMediaCannotBecomeTextOrActions() {
        let source = "<p>Before</p><script>secret()</script><style>hidden</style><iframe src='https://example.invalid'>hidden</iframe><object>hidden</object><svg><text>hidden</text></svg><video src='x'>hidden</video><audio>hidden</audio><img src='file:///secret' onerror='attack()'><p>After</p>"
        let article = SocialArticleContent(source)
        XCTAssertEqual(article.blocks.map(\.text), ["Before", "After"])
        XCTAssertTrue(article.isLimited)
    }
    func testNestedSuppressedSubtreesAndCommentsRemainOmitted() {
        XCTAssertEqual(text("<template>hidden<template>also hidden</template>still hidden</template><p>Visible</p><!-- hidden -->"), ["Visible"])
        let article = SocialArticleContent("<p>Visible</p><!-- unfinished")
        XCTAssertEqual(article.blocks.map(\.text), ["Visible"])
        XCTAssertTrue(article.isLimited)
    }
    func testRawTextInsideOmittedContainersCannotEndOuterSuppression() {
        let sources = [
            "<template><script>const x = \"</template>\"; FORBIDDEN_SCRIPT_TEXT</script></template><p>After</p>",
            "<object><style>content: '</object>'; FORBIDDEN_STYLE_TEXT</style></object><p>After</p>"
        ]
        for source in sources {
            let article = SocialArticleContent(source)
            XCTAssertEqual(article.blocks.map(\.text), ["After"])
            XCTAssertTrue(article.isLimited)
        }
    }
    func testScriptAndStyleRawTextIgnoreApparentTagsCommentsAndQuotes() {
        for tag in ["script", "style"] {
            for body in ["'<\(tag)>'; hidden", "<!-- hidden", "'<p'; hidden", "'</\(tag):bogus>'; hidden", "'</\(tag)-bogus>'; hidden"] {
                let article = SocialArticleContent("<\(tag)>\(body)</\(tag)><p>After</p>")
                XCTAssertEqual(article.blocks.map(\.text), ["After"], body)
                XCTAssertTrue(article.isLimited)
            }
        }
        XCTAssertEqual(text("<SCRIPT>hidden</ScRiPt ><p>After</p>"), ["After"])
    }
    func testInvalidActiveEndTagNamesCannotExposeHiddenText() {
        let article = SocialArticleContent("<script>hidden</script:bogus>FORBIDDEN_SCRIPT_TEXT</script><p>After</p>")
        XCTAssertEqual(article.blocks.map(\.text), ["After"])
        XCTAssertTrue(article.isLimited)
    }
    func testLegacyDoubleEscapedScriptStopsWithoutExposingItsSuffix() {
        for opening in ["<script>", "<ScRiPt >"] {
            let article = SocialArticleContent("<p>Before</p><script><!--\(opening)</script>FORBIDDEN_SCRIPT_TEXT</script><p>After</p>")
            XCTAssertEqual(article.blocks.map(\.text), ["Before"])
            XCTAssertTrue(article.isLimited)
        }
    }
    func testPlainTextLiteralAnglePreservesInstructionLineBreaks() {
        XCTAssertEqual(text("1 < 2\nNext instruction"), ["1 < 2\nNext instruction"])
        XCTAssertEqual(text("3 > 2\n中文"), ["3 > 2\n中文"])
    }
    func testOtherTextOnlyModesCannotEndOuterSuppression() {
        for tag in ["iframe", "textarea", "title", "xmp", "noembed", "noframes", "noscript"] {
            let article = SocialArticleContent("<template><\(tag)></template>FORBIDDEN_TEXT</\(tag)></template><p>After</p>")
            XCTAssertEqual(article.blocks.map(\.text), ["After"], tag)
            XCTAssertTrue(article.isLimited)
        }
        let plaintext = SocialArticleContent("<p>Before</p><template><plaintext></template>FORBIDDEN_TEXT")
        XCTAssertEqual(plaintext.blocks.map(\.text), ["Before"])
        XCTAssertTrue(plaintext.isLimited)
    }
    func testSelfClosingForeignMediaDoesNotConsumeFollowingProse() {
        for tag in ["svg", "math"] {
            XCTAssertEqual(text("<\(tag)/><p>After</p>"), ["After"])
            XCTAssertEqual(text("<\(tag)><\(tag)/></\(tag)><p>After</p>"), ["After"])
        }
        // HTML does not close these raw-text elements with a self-closing slash.
        XCTAssertEqual(text("<iframe/>hidden</iframe><p>After</p>"), ["After"])
        XCTAssertEqual(text("<script/>hidden</script><p>After</p>"), ["After"])
    }
    func testUnquotedAttributeSlashCannotEscapeForeignSuppression() {
        for tag in ["svg", "math"] {
            let article = SocialArticleContent("<\(tag) data=x/>FORBIDDEN_TEXT</\(tag)><p>After</p>")
            XCTAssertEqual(article.blocks.map(\.text), ["After"])
            XCTAssertTrue(article.isLimited)
            XCTAssertEqual(text("<\(tag) data=x /><p>After</p>"), ["After"])
        }
    }
    func testAbruptAndAlternativeCommentEndsCannotExposeScriptSuffixes() {
        for comment in ["<!-- --!>", "<!-->", "<!--->"] {
            let article = SocialArticleContent(comment + "<script>hidden -->FORBIDDEN_SCRIPT_TEXT</script><p>After</p>")
            XCTAssertEqual(article.blocks.map(\.text), ["After"], comment)
            XCTAssertTrue(article.isLimited)
        }
    }
    func testUnsupportedDeclarationModesStopAtReadablePrefix() {
        for marker in ["<!DOCTYPE", "<?instruction", "<![CDATA["] {
            let article = SocialArticleContent("<p>Before</p>" + marker + " hidden><script>hidden</script><p>After</p>")
            XCTAssertEqual(article.blocks.map(\.text), ["Before"])
            XCTAssertTrue(article.isLimited)
        }
    }
    func testMalformedAttributeQuotesCannotSkipARealScriptOpener() {
        let source = "<p>Before</p><p x=foo\"><script>let a=\">\"; FORBIDDEN_SCRIPT_TEXT</script><p>After</p>"
        let article = SocialArticleContent(source)
        XCTAssertEqual(article.blocks.map(\.text), ["Before"])
        XCTAssertTrue(article.isLimited)
        XCTAssertEqual(text("<p x='safe>quoted'>Body</p>"), ["Body"])
    }
    func testAttributeStateDistinguishesQuotedAndUnquotedForeignSlashes() {
        XCTAssertEqual(text("<svg data='x'/><p>After</p>"), ["After"])
        XCTAssertEqual(text("<svg data= />HIDDEN</svg><p>After</p>"), ["After"])
        XCTAssertEqual(text("<svg data=x / ><p>After</p>"), [])
        XCTAssertTrue(SocialArticleContent("<svg data=x / ><p>After</p>").isLimited)
    }
    func testCaseInsensitiveTagsAndQuotedAnglesDoNotExposeAttributes() {
        let article = SocialArticleContent("<H2 data-test='a>b'>Heading</H2><P title=\"a<b\">Body</P>")
        XCTAssertEqual(article.blocks.map(\.text), ["Heading", "Body"])
        XCTAssertEqual(article.blocks.first?.kind, .heading(2))
    }
    func testUnknownWrappersKeepPlainTextAndTablesKeepReadingOrder() {
        XCTAssertEqual(text("<custom><span>Visible</span></custom><table><tr><td>One</td><td>Two</td></tr></table>"), ["Visible", "One Two"])
    }
    func testMalformedMarkupReturnsBoundedReadablePrefix() {
        let article = SocialArticleContent("<p>Keep</p><b>Bold<i>both</b> plain<p title='unterminated")
        XCTAssertEqual(article.blocks.map(\.text), ["Keep", "Boldboth plain"])
        XCTAssertTrue(article.isLimited)
        XCTAssertFalse(article.blocks.last!.runs.last!.italic)
    }
    func testOversizedInputAndOutputAreExplicitlyLimited() {
        let article = SocialArticleContent(String(repeating: "文", count: SocialArticleContent.maximumSourceScalars + 100))
        XCTAssertTrue(article.isLimited)
        XCTAssertEqual(article.blocks[0].text.unicodeScalars.count, SocialArticleContent.maximumOutputScalars)
    }
    func testBlockBudgetIsEnforcedWithoutFabricatedEllipsis() {
        let article = SocialArticleContent(String(repeating: "<p>x</p>", count: SocialArticleContent.maximumBlocks + 1))
        XCTAssertEqual(article.blocks.count, SocialArticleContent.maximumBlocks)
        XCTAssertTrue(article.isLimited)
        XCTAssertTrue(article.blocks.allSatisfy { $0.text == "x" })
    }
    func testRunBudgetBoundsAlternatingFormatting() {
        let article = SocialArticleContent(String(repeating: "<b>x</b>y", count: SocialArticleContent.maximumRuns))
        XCTAssertEqual(article.blocks.flatMap(\.runs).count, SocialArticleContent.maximumRuns)
        XCTAssertTrue(article.isLimited)
    }
    func testDeepFormattingListsAndSuppressedSubtreesStopSafely() {
        for tag in ["b", "ol", "blockquote", "template"] {
            let article = SocialArticleContent(String(repeating: "<\(tag)>", count: SocialArticleContent.maximumDepth + 1) + "hidden")
            XCTAssertTrue(article.isLimited, tag)
            XCTAssertFalse(article.blocks.map(\.text).joined().contains("hidden"), tag)
        }
    }
    func testTokenAndTagBudgetsAreEnforced() {
        XCTAssertTrue(SocialArticleContent(String(repeating: "<span/>", count: SocialArticleContent.maximumTokens + 1)).isLimited)
        let article = SocialArticleContent("<p>Keep</p><a title='" + String(repeating: "x", count: SocialArticleContent.maximumTagScalars + 1) + "'>label</a>")
        XCTAssertEqual(article.blocks.map(\.text), ["Keep"])
        XCTAssertTrue(article.isLimited)
    }
    func testEmptyAndMarkupOnlyContentDoNotInventBodyText() {
        for source in ["", "   ", "<p></p>", "<br>", "<!-- empty -->"] {
            XCTAssertTrue(SocialArticleContent(source).blocks.isEmpty)
        }
        let suppressed = SocialArticleContent("<script>hidden</script>")
        XCTAssertTrue(suppressed.blocks.isEmpty)
        XCTAssertTrue(suppressed.isLimited)
    }
}
