"""Exact byte projection for the approved DEBUG creator-fixture storage change.

This adapter serves only the existing historical helper-byte assertion. It is
not evidence of current storage behavior: current safety contracts run against
the real sources separately. UI methods, actions, helpers and planning costs
are neither rewritten nor re-estimated here.

Only the complete original three-file bundle or the complete approved changed
bundle is accepted. No text decoding, newline normalization, regex replacement,
partial-match fallback or unverified snapshot substitution is allowed.
"""
import hashlib
from pathlib import Path

from tools.tests.club_parity_budget_history import historical_pre_club_source


ROOT = Path(__file__).resolve().parents[2]
FIXTURE_SOURCE = 'App/WorkshopCreatorPendingFixtureSupport.swift'
PREIMAGE_FILE = (
    'tools/fixtures/creator_pending_synthetic_storage/'
    'WorkshopCreatorPendingFixtureSupport.swift.preimage'
)

# Full raw-file identities, before and after this one approved storage change.
# Neither a mixed bundle nor another evolution is a recognized history state.
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


def historical_pre_synthetic_storage_helper_bytes(path, *, root=ROOT):
    """Read historical helper bytes only after validating this complete bundle.

    Other helpers retain their original pre-club reader. The original caller's
    historical SHA-256 assertion still executes on the returned raw bytes.
    Nothing is cached, so later file or preimage mutations are also rejected.
    """
    root, path = Path(root), Path(path)
    relative = path.relative_to(root).as_posix()
    sources = {name: _read_bytes(root / name) for name in APP_SHA256}
    identities = {name: _digest(data) for name, data in sources.items()}
    original = all(identities[name] == hashes[0] for name, hashes in APP_SHA256.items())
    changed = all(identities[name] == hashes[1] for name, hashes in APP_SHA256.items())
    if not (original or changed):
        raise ValueError('Mixed or unreviewed creator storage App source bundle')

    preimage = _read_bytes(root / PREIMAGE_FILE)
    if _digest(preimage) != APP_SHA256[FIXTURE_SOURCE][0]:
        raise ValueError('Creator fixture complete preimage changed')
    restored = (sources[FIXTURE_SOURCE] if original
                else _restore_fixture_bytes(sources[FIXTURE_SOURCE]))
    if restored != preimage:
        raise ValueError('Creator fixture inverse differs from the complete preimage')
    if relative == FIXTURE_SOURCE:
        return restored
    return historical_pre_club_source(path).read_bytes()
