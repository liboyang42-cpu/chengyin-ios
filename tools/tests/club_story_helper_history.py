"""Exact reversible helper history for the run109 horizontal chapter query repair.

The historical lossless-split proof keeps its original hash and assertions.
"""
import hashlib
OLD_HELPER_SHA256 = '709c59e275d758008250d95015e9d81129bee64383e9332c4cc48e94112babf4'
PREVIOUS_HELPER_SHA256 = '7a11af1fecc0fc01221ed4d388e572e5cf5857a0cfc0d5ea14d5469200299338'
ADAPTIVE_HELPER_SHA256 = '4da0e5d4628d2fda706444c8ce357d7abd8f9af1414fb7ea8bd1833e5c246f7e'
CURRENT_HELPER_SHA256 = '135f1ad3d1708f25f41df9d168f4b85e3b07a93261723a395192b464b296a619'
HELD_DRAG = '            // Default-velocity short drags still coast past the measured edge.\n            // Hold at the endpoint before lifting, then remeasure the same button.\n            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)'
PREVIOUS_DRAG = '            start.press(forDuration: 0.05, thenDragTo: end)'
ADAPTIVE_SCROLL = '            // A full swipe moves past the middle chapter to either end and oscillates.\n            // Drag only the missing horizontal edge, within this exact selector\'s frame.\n            var delta: CGFloat = 0\n            if frame.minX < visible.minX { delta = visible.minX - frame.minX + 8 }\n            else if frame.maxX > visible.maxX { delta = visible.maxX - frame.maxX - 8 }\n            guard delta != 0 else { XCTFail("Fully visible chapter is not enabled/hittable. " + app.debugDescription); return }\n            delta = min(visible.width * 0.35, max(-visible.width * 0.35, delta))\n            let origin = scroller.coordinate(withNormalizedOffset: .zero)\n            let start = origin.withOffset(CGVector(dx: visible.midX - scroller.frame.minX, dy: visible.midY - scroller.frame.minY))\n            let end = origin.withOffset(CGVector(dx: visible.midX + delta - scroller.frame.minX, dy: visible.midY - scroller.frame.minY))\n            start.press(forDuration: 0.05, thenDragTo: end)'
PREVIOUS_SCROLL = '            if frame.midX < visible.midX { scroller.swipeRight() }\n            else { scroller.swipeLeft() }'
CHAPTER_BRANCH = '        if ["club.story.chapter.0", "club.story.chapter.1", "club.story.chapter.2"].contains(id) {\n            tapChapter(id); return\n        }\n'

def before_horizontal_chapter_query(helper):
    digest = hashlib.sha256(helper.encode()).hexdigest()
    if digest == OLD_HELPER_SHA256:
        return helper
    if digest == CURRENT_HELPER_SHA256:
        assert helper.count(HELD_DRAG) == 1
        helper = helper.replace(HELD_DRAG, PREVIOUS_DRAG, 1)
        digest = hashlib.sha256(helper.encode()).hexdigest()
        assert digest == ADAPTIVE_HELPER_SHA256
    if digest == ADAPTIVE_HELPER_SHA256:
        assert helper.count(ADAPTIVE_SCROLL) == 1
        helper = helper.replace(ADAPTIVE_SCROLL, PREVIOUS_SCROLL, 1)
        digest = hashlib.sha256(helper.encode()).hexdigest()
    assert digest == PREVIOUS_HELPER_SHA256, 'Unreviewed chapter helper bytes cannot be treated as historical'
    start = helper.index('    private func tapChapter(')
    end = helper.index('    private func gameplay()', start)
    prior = helper[:start] + helper[end:]
    assert prior.count(CHAPTER_BRANCH) == 1
    prior = prior.replace(CHAPTER_BRANCH, '', 1)
    assert hashlib.sha256(prior.encode()).hexdigest() == OLD_HELPER_SHA256
    return prior
