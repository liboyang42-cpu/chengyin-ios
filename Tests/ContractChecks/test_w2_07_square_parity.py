"""w2-07: source guards for mini-program Square list/detail parity and the dormant deletion contract."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


class W207SquareParity(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']

    def zh(self, key):
        return self.catalog[key]['localizations']['zh-Hans']['stringUnit']['value']

    def test_source_copy(self):
        for key, value in {'square.xcx.navTitle': '动态', 'square.xcx.emptyTitle': '广场还很安静',
                           'square.xcx.emptyDetail': '成为第一个发布创意路线的人吧', 'square.xcx.noCommentsTitle': '还没有评论',
                           'square.xcx.commentDeleted': '该评论已删除', 'square.xcx.commentPlaceholder': '留下你的评论',
                           'square.xcx.upcoming.kicker': '即将开始', 'square.xcx.defaultName': '城瘾玩家',
                           'square.xcx.delete.postConfirm': '删除动态', 'square.xcx.delete.commentConfirm': '删除评论'}.items():
            self.assertEqual(self.zh(key), value, key)
        for lifecycle in ['DRAFT', 'CHECKING', 'LIMITED', 'HIDDEN', 'REMOVED']:
            self.assertIn('square.xcx.lifecycle.' + lifecycle, self.catalog)
        self.assertEqual(self.zh('square.title'), '广场')  # home/messaging entry label stays

    def test_list_keeps_existing_identifiers_and_feed_wire(self):
        browser = read('App/SquareBrowserView.swift')
        for exact in ['.accessibilityIdentifier("square.row.\\(post.id)")', 'accessibilityIdentifier("square.empty")',
                      'SquareXcxPostCard(post: post, mediaScope: reader.scope, showsMedia: false)',
                      'NativeMediaGalleryEntry(sources: post.images, scope: reader.scope',
                      'operation == generation, captured == key']:
            self.assertIn(exact, browser)
        # The mini-program adapter's real feed wire is the v1 LATEST feed iOS already calls.
        self.assertIn('api/v1/community/feeds/\\(query.mode.rawValue)', read('Core/SquareService.swift'))

    def test_upcoming_strip_is_read_only_and_source_filtered(self):
        core = read('Core/SquarePresentation.swift') if (ROOT / 'Core/SquarePresentation.swift').exists() else read('Core/SquareXcxPresentation.swift')
        for exact in ['event.bannerEnabled', 'event.status == 1 || event.status == 2', 'start >= now, start < horizon',
                      'Array(event.participantAvatars.prefix(3))', 'max(0, total - 3)']:
            self.assertIn(exact, core)
        strip = read('App/SquareXcxPostCard.swift')
        self.assertIn('try await reader.events(city: nil)', strip)
        self.assertNotRegex(strip, r'URLSession|httpMethod')

    def test_deletion_is_dormant_explicit_and_source_shaped(self):
        flow = read('Core/SquareDeletionFlow.swift')
        for exact in ['request.httpMethod = "DELETE"', '"expectedVersion": target.expectedVersion, "requestId": requestID',
                      'guard case .confirming(let target) = phase, isAllowed(target)',
                      'approval.allows(configuration: configuration, namespace: session.namespace, accountID: session.accountID, path: target.routeTemplate)',
                      'case .unknown: phase = .unknown(target)']:
            self.assertIn(exact, flow)
        app = '\n'.join(p.read_text() for p in (ROOT / 'App').glob('*.swift'))
        # No host supplies an approved coordinator; the reviewed allowlist is empty.
        self.assertNotRegex(app, r'SquareDeletionCoordinator\(service:')
        self.assertNotRegex(app, r'\.environment\(\\\.squareDeletion')
        detail = read('App/SquareDetailView.swift')
        self.assertIn('deletion?.isAllowed($0) != true', detail)
        self.assertIn('deletion.resolveUnknown(stillPresent: false)', detail)

    def test_community_gate_blocks_feed_reads_when_closed(self):
        browser = read('App/SquareBrowserView.swift')
        self.assertIn('guard !gatePending, !communityClosed else', browser)
        self.assertIn('.task(id: key) { await loadGate(); await load(reset: true) }', browser)
        self.assertIn('"api/config/features"', read('Core/SquareService.swift'))
        self.assertIn('SquareSessionReader: SquareReading, SquareCommunityFeatureReading', read('Core/SquareReading.swift'))

    def test_detail_states(self):
        detail = read('App/SquareDetailView.swift')
        for exact in ['comment.lifecycle == "DELETED"', '"square.xcx.commentDeleted"', 'accessibilityIdentifier("square.noComments")',
                      'accessibilityIdentifier("square.commentBar")', 'editor = .init(purpose: .comment, target: .post(post.id), text: "")']:
            self.assertIn(exact, detail)


if __name__ == '__main__':
    unittest.main()
