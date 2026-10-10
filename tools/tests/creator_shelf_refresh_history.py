"""Strict complete-bundle historical projection for shelf refresh retention.

Only historical helper-byte assertions use this adapter. Current behavior is
checked independently against raw current sources in ContractChecks. Full raw
identities admit all five old or all five new files, never a mixed bundle.
"""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MINE_SOURCE = 'App/TemplateAuthoringMineView.swift'
SOURCE_SHA256 = {'App/TemplateAuthoringMineView.swift': ('882bdcf7b5467e0f57dc28c21b3e7c38e32b956f4c19a2713a1d88b31e4cb85d',
                                         '91d2c740529dd2970568cacfcd68409618c6e2d1d6cda007daccfdb3dc8164d7'),
 'Core/TemplateAuthoringShelf.swift': ('079a78c9ca829f79bf35fff0eb3c9dc575baddd7332ae20e092b3eba22a4a5f6',
                                       '3d8865b315f1712f0056d1b376f0f7f2b1aa01e8417dab95f438c200cefe2e91'),
 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift': ('d0a7f13f6f66fdf29d2db630d5aefc5f97113921d7c3977d5a0e1f9793123224',
                                                                '7311d093a69f2291048f9f08110ef1425cd884ede1781abb28c037c1b50a2673'),
 'Tests/ContractChecks/test_template_shelf_read_bridge.py': ('efe2ba8a755453f86964af41c5335fb41abb7423d5d173500a7df8e9502347b2',
                                                             'c6739456a84e353060b42225dae9b8c2a472d8f080bb831ccd7bb74c39afaec8'),
 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift': ('95bb75ebea6aa3b76314843463ca7e09e2bab68366281b4e99b1cbbcb8155baa',
                                                      '760c57eef41df4f73d89ea5143fd629c68d82ffe1c290a203006371c684e8ee6')}

# Exact unique bounded postimage regions, inverted in descending offset order.
MINE_INVERSE_DELTAS = ((1071,
  b'    @State private var busy = false\n    @State private var locked = true\n    @State private '
  b'var readSnapshot = false\n    var body: some View {\n        List {\n',
  b'    @State private var busy = false\n    @State private var locked = true\n    var body: some '
  b'View {\n        List {\n'),
 (3715,
  b'                        prepare(row.id, .libraryStatus)\n                    }.disabled(!coor'
  b'dinator.canSubmit || locked || busy || !coordinator.rows.contains(row)).accessibilityIdentif'
  b'ier("templateAuthor.shelf.library.\\(row.id)")\n                        .disabled(readSnapshot'
  b')\n                    Button("templateAuthor.shelf.delete", role: .destructive) { prepare(ro'
  b'w.id, .remove) }\n                        .disabled(!coordinator.canSubmit || locked || busy '
  b'|| !coordinator.rows.contains(row)).accessibilityIdentifier("templateAuthor.shelf.delete.\\(r'
  b'ow.id)")\n                        .disabled(readSnapshot)\n                }\n            }\n',
  b'                        prepare(row.id, .libraryStatus)\n                    }.disabled(!coor'
  b'dinator.canSubmit || locked || busy || !coordinator.rows.contains(row)).accessibilityIdentif'
  b'ier("templateAuthor.shelf.library.\\(row.id)")\n                    Button("templateAuthor.she'
  b'lf.delete", role: .destructive) { prepare(row.id, .remove) }\n                        .disabl'
  b'ed(!coordinator.canSubmit || locked || busy || !coordinator.rows.contains(row)).accessibilit'
  b'yIdentifier("templateAuthor.shelf.delete.\\(row.id)")\n                }\n            }\n'),
 (9123,
  b'        coordinator.synchronizeSession(); coordinator.shelfReader.synchronizeSession()\n     '
  b'   rows = coordinator.shelfReader.rows; hasMore = coordinator.shelfReader.hasMore\n        re'
  b'adSnapshot = coordinator.shelfReader.isShowingRefreshSnapshot\n        readMessageKey = coord'
  b'inator.shelfReader.messageKey; messageKey = coordinator.shelfMessageKey; locked = coordinato'
  b'r.shelfLocked\n    }\n    private func prepare(_ id: Int, _ action: TemplateOwnShelfAction) {\n'
  b'        guard !coordinator.shelfReader.isShowingRefreshSnapshot else { return }\n        coor'
  b'dinator.prepareShelf(templateID: id, action: action); review = coordinator.shelfReview; sync'
  b'()\n    }\n',
  b'        coordinator.synchronizeSession(); coordinator.shelfReader.synchronizeSession()\n     '
  b'   rows = coordinator.shelfReader.rows; hasMore = coordinator.shelfReader.hasMore\n        re'
  b'adMessageKey = coordinator.shelfReader.messageKey; messageKey = coordinator.shelfMessageKey;'
  b' locked = coordinator.shelfLocked\n    }\n    private func prepare(_ id: Int, _ action: Templa'
  b'teOwnShelfAction) {\n        coordinator.prepareShelf(templateID: id, action: action); review'
  b' = coordinator.shelfReview; sync()\n    }\n'),
 (10058,
  b'    private func refresh() async {\n        let stamp = UUID(); viewRequest = stamp\n        d'
  b'efer {\n            if stamp == viewRequest, Task.isCancelled {\n                rows = []; ha'
  b'sMore = false; readSnapshot = false; busy = false\n            }\n        }\n        busy = tru'
  b'e; review = nil; hasMore = false; readMessageKey = nil; messageKey = nil\n        coordinator'
  b'.synchronizeSession(); coordinator.cancelShelfReview()\n        rows = coordinator.shelfReade'
  b'r.refreshSnapshot(keyword: keyword)\n        readSnapshot = !rows.isEmpty\n        await coord'
  b'inator.shelfReader.refresh(keyword: keyword)\n        guard stamp == viewRequest, !Task.isCan'
  b'celled else { return }\n',
  b'    private func refresh() async {\n        let stamp = UUID(); viewRequest = stamp\n        b'
  b'usy = true; review = nil; rows = []; hasMore = false; readMessageKey = nil; messageKey = nil'
  b'\n        coordinator.synchronizeSession()\n        await coordinator.shelfReader.refresh(keyw'
  b'ord: keyword)\n        guard stamp == viewRequest, !Task.isCancelled else { return }\n'))


def _digest(data):
    return hashlib.sha256(data).hexdigest()


def _restore_mine_bytes(postimage):
    if _digest(postimage) != SOURCE_SHA256[MINE_SOURCE][1]:
        raise ValueError('Unreviewed shelf refresh postimage')
    restored = postimage
    for offset, after, before in reversed(MINE_INVERSE_DELTAS):
        if restored.count(after) != 1 or restored[offset:offset + len(after)] != after:
            raise ValueError('Missing, repeated or moved shelf refresh delta')
        restored = restored[:offset] + before + restored[offset + len(after):]
    if _digest(restored) != SOURCE_SHA256[MINE_SOURCE][0]:
        raise ValueError('Shelf refresh inverse did not restore the original full bytes')
    return restored


def historical_pre_shelf_refresh_mine_bytes(*, root=ROOT):
    root = Path(root)
    sources = {}
    for name in SOURCE_SHA256:
        try:
            sources[name] = (root / name).read_bytes()
        except OSError as error:
            raise ValueError('Missing or unreadable shelf refresh history input: ' + name) from error
    identities = {name: _digest(raw) for name, raw in sources.items()}
    original = all(identities[name] == pair[0] for name, pair in SOURCE_SHA256.items())
    changed = all(identities[name] == pair[1] for name, pair in SOURCE_SHA256.items())
    if not (original or changed):
        raise ValueError('Mixed or unreviewed shelf refresh source bundle')
    return sources[MINE_SOURCE] if original else _restore_mine_bytes(sources[MINE_SOURCE])
