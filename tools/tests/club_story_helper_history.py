"""Exact reversible helper history for the run109 horizontal chapter query repair.

The historical lossless-split proof keeps its original hash and assertions.
"""
import hashlib
OLD_HELPER_SHA256 = '709c59e275d758008250d95015e9d81129bee64383e9332c4cc48e94112babf4'
CURRENT_HELPER_SHA256 = '7a11af1fecc0fc01221ed4d388e572e5cf5857a0cfc0d5ea14d5469200299338'
CHAPTER_BRANCH = '        if ["club.story.chapter.0", "club.story.chapter.1", "club.story.chapter.2"].contains(id) {\n            tapChapter(id); return\n        }\n'

def before_horizontal_chapter_query(helper):
    digest = hashlib.sha256(helper.encode()).hexdigest()
    if digest == OLD_HELPER_SHA256:
        return helper
    assert digest == CURRENT_HELPER_SHA256, 'Unreviewed chapter helper bytes cannot be treated as historical'
    start = helper.index('    private func tapChapter(')
    end = helper.index('    private func gameplay()', start)
    prior = helper[:start] + helper[end:]
    assert prior.count(CHAPTER_BRANCH) == 1
    prior = prior.replace(CHAPTER_BRANCH, '', 1)
    assert hashlib.sha256(prior.encode()).hexdigest() == OLD_HELPER_SHA256
    return prior
