"""Exact AX-row evolution. Source checks are not Apple runtime acceptance."""
from pathlib import Path
import hashlib
import unittest
ROOT = Path(__file__).resolve().parents[2]
CURRENT_SHA = "5ef7bb14672e5de38347a5190e82c88752cf2e17e7a5becaca37391b96571003"
PREVIOUS_SHA = "e545ca2551d36cd3f745e0505f80f6bb7203e75575bac2af2f0a050bcac6861f"
ROW_SHA = "674f108bdb6a87184b584efe301fc94175edd211f6b2f5cd2fe8a633f0640cb7"
AFTER = '                        ProjectRemoteVersionRow(revision: model.draft.baseRevision)\n'
BEFORE = ('                        LabeledContent("projectRemote.version") {\n'
          '                            Text(verbatim: model.draft.baseRevision).accessibilityIdentifier("projectRemote.version.value")\n'
          '                                .accessibilityLabel(Text(verbatim: model.draft.baseRevision))\n'
          '                        }.accessibilityElement(children: .contain)\n')
def digest(value): return hashlib.sha256(value.encode()).hexdigest()
def restore_version_row(source, row=None):
    from tools.ci138_followon_projection import historical_app_source
    try:
        source = historical_app_source("App/ProjectEditView.swift", source, ROOT)
    except ValueError as error:
        raise AssertionError("Unreviewed current editor availability bytes") from error
    assert digest(source) == CURRENT_SHA, "Complete current editor bytes changed"
    row = (ROOT / "App/ProjectRemoteVersionRow.swift").read_bytes().decode('utf-8') if row is None else row
    assert digest(row) == ROW_SHA, "Current AX component changed"
    assert source.count(AFTER) == 1
    restored = source.replace(AFTER, BEFORE, 1)
    assert digest(restored) == PREVIOUS_SHA, "Exact previous editor not restored"
    return restored
class VersionRowSourceChecks(unittest.TestCase):
    def test_only_exact_component_and_mount_are_accepted(self):
        source = (ROOT / "App/ProjectEditView.swift").read_bytes().decode('utf-8')
        self.assertEqual(digest(restore_version_row(source)), PREVIOUS_SHA)
        for changed in [source.replace(AFTER, "", 1), source.replace(AFTER, AFTER + AFTER, 1),
                        source.replace(AFTER, AFTER.replace("model.draft.baseRevision", '\"fixture-r2\"'), 1),
                        source.replace(AFTER, "", 1) + AFTER, source + "\n"]:
            with self.assertRaises(AssertionError): restore_version_row(changed)
        row = (ROOT / "App/ProjectRemoteVersionRow.swift").read_bytes().decode('utf-8')
        for changed in [row + "\n", row.replace("\n", "\r\n"), row.replace("children: .contain", "children: .combine"),
                        row.replace("Text(verbatim: revision)", 'Text("fixture-r2")')]:
            with self.assertRaises(AssertionError): restore_version_row(source, changed)
    def test_original_ui_and_shared_helper_remain_byte_exact(self):
        for path, sha in {
            "Tests/AppUITests/ProjectOwnedEditorFlowTests.swift": "e06f4f77108ca084088c5a0a412fe754938530611fd4e2ff12199e4d1ae278c6",
            "Tests/AppUITests/FailureScreenshot.swift": "705ba7fa14128cfd9e81f181fd2b5f5edd0cb464b2ececd26119510d98ed6e49",
        }.items(): self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), sha)
