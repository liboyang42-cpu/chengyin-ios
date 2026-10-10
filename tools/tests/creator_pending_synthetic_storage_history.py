"""Exact byte projection for the approved DEBUG creator-fixture storage change.

This adapter serves only the existing historical helper-byte assertion. It is
not evidence of current storage behavior: current safety contracts run against
the real sources separately. UI methods, actions, helpers and planning costs
are neither rewritten nor re-estimated here.

Only complete original, approved storage-change, or reviewed evolved three-file
bundles are accepted. Later App wiring is inverted through exact bounded bytes
before the unchanged storage inverse. No source text decoding, newline
normalization, regex replacement, partial-match fallback or unverified snapshot
substitution is allowed.
"""
import hashlib
import json
from pathlib import Path

from tools.tests.club_parity_budget_history import historical_pre_club_source
from tools.tests.creator_shelf_refresh_history import historical_pre_shelf_refresh_mine_bytes


ROOT = Path(__file__).resolve().parents[2]
FIXTURE_SOURCE = 'App/WorkshopCreatorPendingFixtureSupport.swift'
PREIMAGE_FILE = (
    'tools/fixtures/creator_pending_synthetic_storage/'
    'WorkshopCreatorPendingFixtureSupport.swift.preimage'
)

# Full raw-file identities, before and after this one approved storage change.
# Neither a mixed bundle nor an unreviewed evolution is a recognized history state.
APP_SHA256 = {
    'App/AppCompositionRoot.swift': (
        '2c1d87087325898aaa78cb644b780c3132736536c1971318c473eddabdf439d4',
        '006923cb90a730259ba135784ae802350125c31cfb584d89a88d4209f8986dbb',
    ),
    'App/AppSession.swift': (
        'e2f082a23132df938bebd49972eb4a1eab79c1070a76f04348cae080a28a377f',
        '5ac846ff656a7b74f0c9bd28200f11a257ae260f5c881f201c2a3b026af6dd09',
    ),
    FIXTURE_SOURCE: (
        'a7fe8e68a972c3ffc0eb4390654669d85c78771c24237c9b2c09b34a68bfcf75',
        '4084ba4106fb94630ba3091ef7eb754e29864a21a85c38123b82ec58e4f7ebee',
    ),
}

# (absolute byte offset in the reviewed postimage, exact postimage region,
# exact preimage region). Apply in reverse offset order so bounds never shift.
# These are the only three FixtureSupport regions permitted to differ.
FIXTURE_INVERSE_DELTAS = (
    (
        5978,
        b'    /// One recovery lifetime per harness, retained through Back and fresh controller selection.\n'
        b'    let recoveryStorage = TemplateAuthoringMemoryStorage()\n',
        b'',
    ),
    (
        6760,
        b'        var storage = AppScopedStorageFactory(defaults: UserDefaults(suiteName: suite)!, tokenStore: { [vault] _ in vault })\n'
        b'        storage.syntheticWorkshopCreatorPendingRecoveryStorage = recoveryStorage\n'
        b'        session = AppCompositionRoot(deployment: .reviewed(deployment), storage: storage, makeTransport: { [wire] in wire },\n',
        b'        session = AppCompositionRoot(deployment: .reviewed(deployment), storage: .init(defaults: UserDefaults(suiteName: suite)!, tokenStore: { [vault] _ in vault }), makeTransport: { [wire] in wire },\n',
    ),
    (
        9356,
        b'    func clean() {\n'
        b'        recoveryStorage.values.removeAll()\n'
        b'        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)\n'
        b'    }\n',
        b'    func clean() { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }\n',
    ),
)


# Complete originals restored from the archived d09c delivery using the already
# reviewed storage deltas. Their old hashes above remain the acceptance anchors.
PREIMAGE_FILES = {
    name: 'tools/fixtures/creator_pending_synthetic_storage/' + Path(name).name + '.preimage'
    for name in APP_SHA256
}
EVOLUTION_FILE = 'tools/fixtures/creator_pending_synthetic_storage/reviewed-evolution.json'
EVOLUTION_SHA256 = '0ae850e9884ea864a3584847aeb923037fee3dda58f9a1e6d0245a7cb7232542'
EVOLVED_APP_SHA256 = {
    'App/AppCompositionRoot.swift': 'ed3ef356f8762a0690bcfdfad8fe5c053381df72ec0b60a108a7f9c7a7ffdde1',
    'App/AppSession.swift': '56e188e6c1cf80050ea642a4ebe53a7fd03645d0dda9635ce189b7e9a4d033f0',
    FIXTURE_SOURCE: APP_SHA256[FIXTURE_SOURCE][1],
}

# Exact original storage-change App regions, independently retained by the tests.
# These postimage offsets refer to the historical d09c delivery, not current App.
STORAGE_INVERSE_DELTAS = {
    'App/AppCompositionRoot.swift': (
        (
            2352,
            b'#if DEBUG\n'
            b'    /// Explicit fixture-only override. Ordinary and Release composition keep system storage.\n'
            b'    var syntheticWorkshopCreatorPendingRecoveryStorage: (any TemplateAuthoringStorage)? = nil\n'
            b'#endif\n',
            b'',
        ),
    ),
    'App/AppSession.swift': (
        (
            40382,
            b'    private var workshopCreatorPendingRecoveryStorage: any TemplateAuthoringStorage {\n'
            b'#if DEBUG\n'
            b'        if let storage = composition.storage.syntheticWorkshopCreatorPendingRecoveryStorage { return storage }\n'
            b'#endif\n'
            b'        return templateAuthoringSecureStorage\n'
            b'    }\n',
            b'',
        ),
        (
            42369,
            b'                  let store = try? WorkshopCreatorPendingStore(storage: workshopCreatorPendingRecoveryStorage, context: captured, sourceTemplateId: sourceTemplateId),\n',
            b'                  let store = try? WorkshopCreatorPendingStore(storage: templateAuthoringSecureStorage, context: captured, sourceTemplateId: sourceTemplateId),\n',
        ),
        (
            42536,
            b'                  let declarationStore = try? WorkshopCreatorConsentPendingStore(storage: workshopCreatorPendingRecoveryStorage, context: captured, sourceTemplateId: sourceTemplateId) else { return nil }\n',
            b'                  let declarationStore = try? WorkshopCreatorConsentPendingStore(storage: templateAuthoringSecureStorage, context: captured, sourceTemplateId: sourceTemplateId) else { return nil }\n',
        ),
        (
            44536,
            b'                          let consentStore = try? WorkshopCreatorConsentPendingStore(storage: self.workshopCreatorPendingRecoveryStorage, context: captured, sourceTemplateId: sourceTemplateId) else { return nil }\n',
            b'                          let consentStore = try? WorkshopCreatorConsentPendingStore(storage: self.templateAuthoringSecureStorage, context: captured, sourceTemplateId: sourceTemplateId) else { return nil }\n',
        ),
    ),
}


def _digest(data):
    return hashlib.sha256(data).hexdigest()


def _read_bytes(path):
    try:
        return path.read_bytes()
    except OSError as error:
        raise ValueError('Missing or unreadable creator storage history input: ' + str(path)) from error


def _restore_fixture_bytes(postimage):
    """Invert exact bounded regions, then require the original full-file hash."""
    if _digest(postimage) != APP_SHA256[FIXTURE_SOURCE][1]:
        raise ValueError('Unreviewed creator fixture postimage')
    restored = postimage
    for offset, after, before in reversed(FIXTURE_INVERSE_DELTAS):
        if restored.count(after) != 1 or restored[offset:offset + len(after)] != after:
            raise ValueError('Missing, repeated or moved creator fixture delta')
        restored = restored[:offset] + before + restored[offset + len(after):]
    if _digest(restored) != APP_SHA256[FIXTURE_SOURCE][0]:
        raise ValueError('Creator fixture inverse did not restore the original full bytes')
    return restored


def _reviewed_evolution(root):
    raw = _read_bytes(root / EVOLUTION_FILE)
    if _digest(raw) != EVOLUTION_SHA256:
        raise ValueError('Creator storage reviewed evolution changed')
    return json.loads(raw)['files']


def _invert_exact(data, deltas, postimage_sha256, preimage_sha256):
    """Only invert unique, exact regions at their fixed raw-byte offsets."""
    if _digest(data) != postimage_sha256:
        raise ValueError('Unreviewed creator storage evolution postimage')
    restored = data
    for offset, after, before in reversed(deltas):
        if not after or restored.count(after) != 1 or restored[offset:offset + len(after)] != after:
            raise ValueError('Missing, repeated or moved creator storage evolution delta')
        restored = restored[:offset] + before + restored[offset + len(after):]
    if _digest(restored) != preimage_sha256:
        raise ValueError('Creator storage inverse did not restore the original full bytes')
    return restored


def historical_pre_synthetic_storage_helper_bytes(path, *, root=ROOT):
    """Validate the complete bundle and originals before the old helper assertion.

    Later approved App evolution is inverted only for a complete reviewed bundle.
    Only that evolved state requires the later manifest and complete App preimages.
    Original and storage-only bundles keep their original input requirements.
    Other helpers retain their pre-club reader; no current source is rewritten.
    Nothing is cached, so later mutations of required inputs fail closed.
    """
    root, path = Path(root), Path(path)
    relative = path.relative_to(root).as_posix()
    sources = {name: _read_bytes(root / name) for name in APP_SHA256}
    identities = {name: _digest(data) for name, data in sources.items()}
    original = all(identities[name] == hashes[0] for name, hashes in APP_SHA256.items())
    changed = all(identities[name] == hashes[1] for name, hashes in APP_SHA256.items())
    evolved = identities == EVOLVED_APP_SHA256
    if not (original or changed or evolved):
        raise ValueError('Mixed or unreviewed creator storage App source bundle')
    if evolved:
        evolution = _reviewed_evolution(root)
        for name, row in evolution.items():
            deltas = tuple((item['postimage_offset'], bytes.fromhex(item['postimage_hex']),
                            bytes.fromhex(item['preimage_hex'])) for item in row['inverse_deltas'])
            sources[name] = _invert_exact(sources[name], deltas, row['reviewed_sha256'],
                                          APP_SHA256[name][1])
    restored = dict(sources)
    if not original:
        restored[FIXTURE_SOURCE] = _restore_fixture_bytes(sources[FIXTURE_SOURCE])
        if evolved:
            for name, deltas in STORAGE_INVERSE_DELTAS.items():
                restored[name] = _invert_exact(sources[name], deltas, APP_SHA256[name][1],
                                                APP_SHA256[name][0])
    required_preimages = PREIMAGE_FILES if evolved else {FIXTURE_SOURCE: PREIMAGE_FILE}
    for name, preimage_file in required_preimages.items():
        preimage = _read_bytes(root / preimage_file)
        if _digest(preimage) != APP_SHA256[name][0]:
            label = 'Creator fixture' if name == FIXTURE_SOURCE else 'Creator App'
            raise ValueError(label + ' complete preimage changed: ' + name)
        if restored[name] != preimage:
            raise ValueError('Creator storage inverse differs from the complete preimage: ' + name)
    if relative == FIXTURE_SOURCE:
        return restored[FIXTURE_SOURCE]
    if relative == 'App/TemplateAuthoringMineView.swift':
        return historical_pre_shelf_refresh_mine_bytes(root=root)
    return historical_pre_club_source(path).read_bytes()
