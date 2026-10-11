"""Exact P044 directory-only admission and historical scanner input.

This adapter is newly scoped to the published baseline. It never broadens scanner
ignores, renumbers a historical finding, or skips an original assertion.
"""
from pathlib import Path
import copy
import hashlib
import json

BASE_CONTRACT_SHA256 = '11cc2e20ce328dcba2fcfbcb4425bf581908038c71d4f4c7eee15c1bbab1b2b6'
BASE_READINESS_SHA256 = 'cafa9858b24a18f3827ce5678701b1e32cf533e66d51dc43788b15a74d60a79f'
CONTRACT_PATH = 'tools/run138_editor_readiness_contract.json'
HELPER_PATH = 'tools/club_customer_directory_admission.py'
HELPER_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
SOURCE_EDITS = {'Core/ClubCustomerHistoryTopicRoute.swift': {'before_sha256': '4fe6609906f468bb3ee4be8acd37ac59ca8bdc9ceb04855ef5365b60bafeec27', 'after_sha256': '566199e3d716e395082b0fe383464a62917b28d3851cf2437e4433ec35bb11e2', 'hunks': [{'before': '        return (1...maximum).contains(id) ? id : nil\n    }\n}\n', 'after': '        return (1...maximum).contains(id) ? id : nil\n    }\n}\n\n/// Mirrors CRM list/count/detail requireGovernable using current access/me evidence.\n/// Contact-list visibility and event-only grants cannot authorize this club-wide read.\npublic extension ClubGovernancePermissions {\n    func allowsCustomerDirectory(scope: ClubGovernanceScope) -> Bool {\n        guard active, clubID == scope.clubID, (scope.clubID ?? 0) > 0 else { return false }\n        do { try scope.validate() } catch { return false }\n        return roleCodes.contains("CLUB_OWNER") || roleCodes.contains("CLUB_LEGACY_ADMIN") ||\n            permissions.contains("club:member:manage")\n    }\n}\n'}]}, 'Core/ClubGovernanceContracts.swift': {'before_sha256': 'e8b328600808aad0529d3ec6f993a3bb6a08e0a2c0b6d3c6ba2ea19b6bd03264', 'after_sha256': 'ad3935e5f71a0018c1d9db4c86f6afbb021a4e2c78b92d4b7bd931f8f0fdaa32', 'hunks': [{'before': '        if permission == "ROLES" { return canManageRoles }\n', 'after': '        if permission == "ROLES" { return canManageRoles }\n        if permission == "CUSTOMER_DIRECTORY" { return allowsCustomerDirectory(scope: scope) }\n'}, {'before': '        case .customers, .customer, .customerCount, .checkin, .topicCustomers, .registrations: return "club:member:list:read"', 'after': '        case .customers, .customer, .customerCount: return "CUSTOMER_DIRECTORY" // Local preflight, never an API grant.\n        case .checkin, .topicCustomers, .registrations: return "club:member:list:read"'}]}, 'Tests/CoreTests/ClubGovernanceProductionTests.swift': {'before_sha256': '7ec52b15675c3a14de89bd27b32b28b9079d28fc6da784337e2a1f16fc82aa5f', 'after_sha256': '772420e3ec145740c416da29bc5ee2b187e10bc21181e149e5947410733e100a', 'hunks': [{'before': '                payload = "{\\"active\\":true,\\"club\\":{\\"id\\":81},\\"roleCodes\\":[\\"CLUB_MEMBER\\"],\\"permissions\\":\\(allowed ? (chapterFlow ? "[\\"club:content:manage\\"]" : (banFlow ? "[\\"club:member:manage\\"]" : "[\\"club:member:list:read\\"]")) : "[]"),\\"canManageRoles\\":false}"\n', 'after': '                payload = "{\\"active\\":true,\\"club\\":{\\"id\\":81},\\"roleCodes\\":[\\"CLUB_MEMBER\\"],\\"permissions\\":\\(allowed ? (chapterFlow ? "[\\"club:content:manage\\"]" : (banFlow ? "[\\"club:member:manage\\"]" : "[\\"club:member:list:read\\",\\"club:member:manage\\"]")) : "[]"),\\"canManageRoles\\":false}"\n'}]}, 'tools/tests/test_gitleaks_configuration.py': {'before_sha256': 'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c', 'after_sha256': 'e6c0f1cb301fa8a762040ad4ed81c3ab8e5493ca1bfb99329bbbceb395b0c868', 'hunks': [{'before': 'import unittest\n', 'after': 'import unittest\nfrom tools.club_customer_directory_admission import historical_scan_contract\n'}, {'before': '        raw = (ROOT / FILE_DIGEST_PATH).read_text()', 'after': '        raw = historical_scan_contract(ROOT)'}]}}
ADDED_SUPPORT = ('Tests/CoreTests/ClubCustomerPermissionTests.swift', 'Tests/ContractChecks/test_club_customer_permissions.py', 'docs/club-customer-permissions.md', 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py', 'tools/club_customer_directory_admission.py')


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def restore_product_source(relative, raw):
    """Require the complete exact current file, then restore its complete baseline."""
    row = SOURCE_EDITS[relative]
    if digest(raw) != row['after_sha256']:
        raise ValueError('Unknown P044 current source: ' + relative)
    text = raw.decode('utf-8')
    for hunk in reversed(row['hunks']):
        if text.count(hunk['after']) != 1:
            raise ValueError('Missing or repeated P044 source span: ' + relative)
        text = text.replace(hunk['after'], hunk['before'], 1)
    restored = text.encode('utf-8')
    if digest(restored) != row['before_sha256']:
        raise ValueError('P044 baseline was not restored exactly: ' + relative)
    return restored


def historical_scan_contract(root):
    """Admit every new input before returning the exact full historical contract.

    The original baseline domain is also accepted, but a baseline contract mixed
    with any new product/checker bytes is rejected. The existing scanner test
    still runs all original assertions against this independently validated input.
    """
    root = Path(root)
    raw = (root / CONTRACT_PATH).read_bytes()
    if digest(raw) == BASE_CONTRACT_SHA256:
        if digest((root / 'tools/run138_editor_readiness.py').read_bytes()) != BASE_READINESS_SHA256:
            raise ValueError('Hybrid baseline and current readiness reader')
        for relative in ADDED_SUPPORT:
            file = root / relative
            if file.exists() or file.is_symlink():
                raise ValueError('Baseline domain contains new support: ' + relative)
        for relative, row in SOURCE_EDITS.items():
            if digest((root / relative).read_bytes()) != row['before_sha256']:
                raise ValueError('Hybrid baseline and P044 source: ' + relative)
        return raw.decode('utf-8')
    from tools import run138_editor_readiness as current
    if digest((root / 'tools/run138_editor_readiness.py').read_bytes()) != current.IMPLEMENTATION_SHA256:
        raise ValueError('Current readiness reader changed')
    contract = current.contract(root)  # Requires the exact reviewed raw bytes.
    if digest((root / HELPER_PATH).read_bytes()) != HELPER_SHA256:
        raise ValueError('Current P044 scanner input reader changed')
    for relative, expected in SOURCE_EDITS.items():
        if contract['feature_batch_sources'].get(relative) != expected:
            raise ValueError('P044 source admission row changed: ' + relative)
        restore_product_source(relative, (root / relative).read_bytes())
    for relative in ADDED_SUPPORT:
        expected = contract['feature_batch_support_sha256'].get(relative)
        if not expected or digest((root / relative).read_bytes()) != expected:
            raise ValueError('P044 support input changed: ' + relative)
    restored = copy.deepcopy(contract)
    for relative in SOURCE_EDITS:
        del restored['feature_batch_sources'][relative]
    for relative in ADDED_SUPPORT:
        del restored['feature_batch_support_sha256'][relative]
    baseline = (json.dumps(restored, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    if digest(baseline) != BASE_CONTRACT_SHA256:
        raise ValueError('Complete historical scanner contract not restored')
    return baseline.decode('utf-8')

# Exact keyword/PBX evolution. Original eleven-file reader above is retained byte-for-byte.

FROZEN_PERMISSION_CONTRACT_SHA256 = 'f2a58dbe3aaa71a13ae0f7ab45505afdea5f02360164c3c697e4e392ac8db41d'
FROZEN_PERMISSION_READINESS_SHA256 = '0fd831ef72293c21ab8b2af505214585a6a1509acbcc61c9f60015b3e815ef28'
FROZEN_PERMISSION_HELPER_SHA256 = '244f9353c0a31a19b11bfb74054ba454756940a64238974d946ef59cce5ad8cd'
FROZEN_TEST_PATH = 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py'
EVOLUTION_SOURCES = {'App/ClubGovernanceViews.swift': {'before_sha256': 'bff35ca70073f32a548aa10a3741f8e64e82dcb9542117a97c06a22f1d724e4a', 'after_sha256': 'f29b604938d53c1d397f1da93961eae1672a80b45b05bc3016501667dc6533ff', 'hunks': [{'before': 'import SwiftUI\n\n/// Mount independently of legacy isOwner/viewerIsAdmin. access/me decides each row.\nstruct ClubGovernanceEntryButton: View {\n', 'after': 'import SwiftUI\n\n/// P044 keyword-only scheduling. The view still owns authorization and response fences.\n@MainActor final class ClubCustomerKeywordDebounce {\n    static let delayNanoseconds: UInt64 = 300_000_000\n    private var pending: Task<Void, Never>?\n    private var revision: UInt64 = 0\n    private let sleep: @MainActor @Sendable () async throws -> Void\n    nonisolated init(sleep: @escaping @MainActor @Sendable () async throws -> Void = {\n        try await Task.sleep(nanoseconds: ClubCustomerKeywordDebounce.delayNanoseconds)\n    }) { self.sleep = sleep }\n    func cancel() {\n        revision &+= 1\n        pending?.cancel()\n        pending = nil\n    }\n    @discardableResult func schedule(_ action: @escaping @MainActor () async -> Void) -> Task<Void, Never> {\n        cancel()\n        let expected = revision\n        let task = Task { @MainActor [weak self] in\n            guard let self else { return }\n            do { try await self.sleep() } catch { return }\n            guard !Task.isCancelled, self.revision == expected else { return }\n            // Release the handle before load() cancels any still-pending timer.\n            self.pending = nil\n            await action()\n        }\n        pending = task\n        return task\n    }\n}\n\n/// Mount independently of legacy isOwner/viewerIsAdmin. access/me decides each row.\nstruct ClubGovernanceEntryButton: View {\n'}, {'before': '    @State private var filter = "all"\n    @State private var topicCustomerFilter: ClubTopicCustomerFilter = .all\n    @State private var keyword = ""\n    @State private var sort = "composite"\n    @State private var page = 1\n    @State private var editor: ClubGovernanceFormRoute?\n', 'after': '    @State private var filter = "all"\n    @State private var topicCustomerFilter: ClubTopicCustomerFilter = .all\n    @State private var keyword = ""\n    @State private var customerKeywordDebounce = ClubCustomerKeywordDebounce()\n    @State private var sort = "composite"\n    @State private var page = 1\n    @State private var editor: ClubGovernanceFormRoute?\n'}, {'before': '                    Picker("club.gov.filter", selection: $filter) {\n                        ForEach(["all", "repeat", "new", "remark"], id: \\.self) { Text(LocalizedStringKey("club.gov.filter." + $0)).tag($0) }\n                    }\n                    .onChange(of: filter) { _, _ in Task { await load() } }\n                    TextField("club.gov.keyword", text: $keyword).submitLabel(.search).onSubmit { Task { await load() } }\n                    Button("club.gov.search") { Task { await load() } }.disabled(loading)\n                }\n            }\n            if operation == .topicCustomers {\n', 'after': '                    Picker("club.gov.filter", selection: $filter) {\n                        ForEach(["all", "repeat", "new", "remark"], id: \\.self) { Text(LocalizedStringKey("club.gov.filter." + $0)).tag($0) }\n                    }\n                    .onChange(of: filter) { _, _ in loadCustomersNow() }\n                    TextField("club.gov.keyword", text: $keyword).submitLabel(.search)\n                        .onChange(of: keyword) { _, _ in scheduleCustomerKeywordRead() }\n                        .onSubmit { loadCustomersNow() }\n                    Button("club.gov.search") { loadCustomersNow() }.disabled(loading)\n                }\n            }\n            if operation == .topicCustomers {\n'}, {'before': '        .task(id: readContext) { snapshot = nil; editor = nil; customerTopic = nil; feedClub = nil; coordinator.cancelReview(); await load() }\n        .onChange(of: readContext) { _, _ in invalidateRead() }\n        .onChange(of: identity) { _, _ in invalidateRead() }\n        .onDisappear { generation &+= 1 }\n        .refreshable { await load() }\n    }\n    private func load() async {\n        generation &+= 1; let revision = generation; let expected = identity; let context = readContext\n        snapshot = nil; failure = nil; loading = true\n        snapshotContext = nil; customerTopic = nil; feedClub = nil; feedMediaScope = UUID()\n', 'after': '        .task(id: readContext) { snapshot = nil; editor = nil; customerTopic = nil; feedClub = nil; coordinator.cancelReview(); await load() }\n        .onChange(of: readContext) { _, _ in invalidateRead() }\n        .onChange(of: identity) { _, _ in invalidateRead() }\n        .onDisappear {\n            if operation == .customers {\n                customerKeywordDebounce.cancel()\n                generation &+= 1\n            }\n        }\n        .onDisappear { generation &+= 1 }\n        .refreshable { await load() }\n    }\n    @MainActor private func loadCustomersNow() {\n        customerKeywordDebounce.cancel()\n        Task { await load() }\n    }\n    @MainActor private func scheduleCustomerKeywordRead() {\n        guard operation == .customers else { return }\n        let context = readContext; let expected = identity\n        let expectedFilter = filter; let expectedKeyword = keyword\n        // Invalidate an older response immediately, including the 300ms wait.\n        generation &+= 1\n        snapshot = nil; snapshotContext = nil; failure = nil; loading = false\n        let keywordRevision = generation\n        customerKeywordDebounce.schedule {\n            guard operation == .customers, context == readContext, expected == identity,\n                  access.identity == expected, keywordRevision == generation,\n                  filter == expectedFilter, keyword == expectedKeyword,\n                  !Task.isCancelled else { return }\n            await load()\n        }\n    }\n    @MainActor private func load() async {\n        if operation == .customers { customerKeywordDebounce.cancel() }\n        generation &+= 1; let revision = generation; let expected = identity; let context = readContext\n        snapshot = nil; failure = nil; loading = true\n        snapshotContext = nil; customerTopic = nil; feedClub = nil; feedMediaScope = UUID()\n'}, {'before': '        }\n        if revision == generation { loading = false }\n    }\n    private func invalidateRead() {\n        generation &+= 1; snapshot = nil; snapshotContext = nil; failure = nil; editor = nil; customerTopic = nil; feedClub = nil; feedMediaScope = UUID(); coordinator.cancelReview()\n    }\n    private func current(_ target: ClubFeedClubRoute) -> Bool {\n', 'after': '        }\n        if revision == generation { loading = false }\n    }\n    @MainActor private func invalidateRead() {\n        if operation == .customers { customerKeywordDebounce.cancel() }\n        generation &+= 1; snapshot = nil; snapshotContext = nil; failure = nil; editor = nil; customerTopic = nil; feedClub = nil; feedMediaScope = UUID(); coordinator.cancelReview()\n    }\n    private func current(_ target: ClubFeedClubRoute) -> Bool {\n'}]}, 'Questify.xcodeproj/project.pbxproj': {'before_sha256': 'fcf316f51e4bb5b19b7f2b16df7ae161d96cfe5ee8cb6f166fe41b9921eeb552', 'after_sha256': 'a397f1c25ca67e4657846e799d8b1f55f8755d3debc7bc7609dcc6040afc9f50', 'hunks': [{'before': '\t\t"791E6BF02CD332B0299A3459" = {\n', 'after': '\t\t"2A4F7E878F7689C47FE34583" = {\n\t\t\t"isa" = "PBXFileReference";\n\t\t\t"lastKnownFileType" = "sourcecode.swift";\n\t\t\t"path" = "Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift";\n\t\t\t"sourceTree" = "<group>";\n\t\t};\n\t\t"4FF7D0B5D5B04E3FAAE97D5A" = {\n\t\t\t"isa" = "PBXBuildFile";\n\t\t\t"fileRef" = "2A4F7E878F7689C47FE34583";\n\t\t};\n\t\t"791E6BF02CD332B0299A3459" = {\n'}, {'before': '\t\t\t\t"791E6BF02CD332B0299A3459",\n', 'after': '\t\t\t\t"2A4F7E878F7689C47FE34583",\n\t\t\t\t"791E6BF02CD332B0299A3459",\n'}, {'before': '\t\t\t\t"19EC95F64576113ABFA6995C",\n', 'after': '\t\t\t\t"4FF7D0B5D5B04E3FAAE97D5A",\n\t\t\t\t"19EC95F64576113ABFA6995C",\n'}]}}
EVOLUTION_SUPPORT = ('Tests/ContractChecks/test_club_customer_keyword_debounce.py', 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift', 'docs/club-customer-keyword-debounce.md')
TEST_EVOLUTION = {'before_sha256': '262656eb7032755d32ccca9496bfbc1fa1407c8673c45cf1028ff6a589a4af54', 'after_sha256': '9248aa6900c69569aa2f7d27ac3d3dbb58293f363f5dc580a84a0ab60b325aa5', 'hunks': [{'before': "ROOT = Path(__file__).resolve().parents[2]\nINPUTS = set(admission.SOURCE_EDITS) | set(admission.ADDED_SUPPORT) | {\n    admission.CONTRACT_PATH, 'tools/run138_editor_readiness.py'}\n\n\ndef digest(raw):\n", 'after': "ROOT = Path(__file__).resolve().parents[2]\nINPUTS = set(admission.SOURCE_EDITS) | set(admission.ADDED_SUPPORT) | {\n    admission.CONTRACT_PATH, 'tools/run138_editor_readiness.py'}\nCOMBINED_INPUTS = INPUTS | set(admission.EVOLUTION_SOURCES) | set(admission.EVOLUTION_SUPPORT)\n\n\ndef digest(raw):\n"}, {'before': '\n@contextmanager\ndef copied_admission_inputs():\n    """Only the eleven admission files, never a repository or historical checkout."""\n    with tempfile.TemporaryDirectory(prefix=\'club-directory-admission-\') as temporary:\n        root = Path(temporary)\n        for relative in sorted(INPUTS):\n            target = root / relative\n            target.parent.mkdir(parents=True, exist_ok=True)\n            target.write_bytes((ROOT / relative).read_bytes())\n', 'after': '\n@contextmanager\ndef copied_admission_inputs():\n    """Only the sixteen admission files, never a repository or historical checkout."""\n    with tempfile.TemporaryDirectory(prefix=\'club-directory-admission-\') as temporary:\n        root = Path(temporary)\n        for relative in sorted(COMBINED_INPUTS):\n            target = root / relative\n            target.parent.mkdir(parents=True, exist_ok=True)\n            target.write_bytes((ROOT / relative).read_bytes())\n'}, {'before': '            \'Questify.xcodeproj/project.pbxproj\': \'fcf316f51e4bb5b19b7f2b16df7ae161d96cfe5ee8cb6f166fe41b9921eeb552\',\n            \'Package.swift\': \'89fefe8ae302c55a9b8853a792f2426d6331eeaa2c1c1b905a77ef6efeac5e2d\',\n        }.items():\n            self.assertEqual(digest((ROOT / relative).read_bytes()), expected)\n        project = (ROOT / \'Questify.xcodeproj/project.pbxproj\').read_text()\n        for relative in [\'Core/ClubGovernanceContracts.swift\', \'Core/ClubCustomerHistoryTopicRoute.swift\']:\n            self.assertEqual(project.count(\'"path" = "\' + relative + \'";\'), 1)\n', 'after': '            \'Questify.xcodeproj/project.pbxproj\': \'fcf316f51e4bb5b19b7f2b16df7ae161d96cfe5ee8cb6f166fe41b9921eeb552\',\n            \'Package.swift\': \'89fefe8ae302c55a9b8853a792f2426d6331eeaa2c1c1b905a77ef6efeac5e2d\',\n        }.items():\n            self.assertEqual(digest(admission.permission_boundary_bytes(ROOT, relative)), expected)\n        project = (ROOT / \'Questify.xcodeproj/project.pbxproj\').read_text()\n        for relative in [\'Core/ClubGovernanceContracts.swift\', \'Core/ClubCustomerHistoryTopicRoute.swift\']:\n            self.assertEqual(project.count(\'"path" = "\' + relative + \'";\'), 1)\n'}, {'before': "    def test_whole_contract_is_exact_baseline_with_only_new_admission_rows(self):\n        restored = admission.historical_scan_contract(ROOT).encode()\n        self.assertEqual(digest(restored), admission.BASE_CONTRACT_SHA256)\n        old, new = json.loads(restored), readiness.contract(ROOT)\n        self.assertEqual(len(old['feature_batch_sources']), 122)\n        self.assertEqual(len(old['feature_batch_support_sha256']), 498)\n        self.assertEqual(set(new['feature_batch_sources']) - set(old['feature_batch_sources']), set(admission.SOURCE_EDITS))\n", 'after': "    def test_whole_contract_is_exact_baseline_with_only_new_admission_rows(self):\n        restored = admission.historical_scan_contract(ROOT).encode()\n        self.assertEqual(digest(restored), admission.BASE_CONTRACT_SHA256)\n        old, new = json.loads(restored), json.loads(admission.frozen_permission_contract(ROOT))\n        self.assertEqual(len(old['feature_batch_sources']), 122)\n        self.assertEqual(len(old['feature_batch_support_sha256']), 498)\n        self.assertEqual(set(new['feature_batch_sources']) - set(old['feature_batch_sources']), set(admission.SOURCE_EDITS))\n"}, {'before': "            'App/ClubGovernanceCommandForm.swift': '28dcfc08ed90e072e51c7a28202a9af925907c9edbe8a296cf5092678f32174f',\n            '.gitleaksignore': 'e6643cd2a90f794cf60c3f635243897b6fefb5adac156493eb2039e590ee09a0',\n        }.items():\n            self.assertEqual(digest((ROOT / path).read_bytes()), expected)\n\n    def test_all_eleven_physical_inputs_reject_same_size_mtime_crlf_and_cr_edits(self):\n        with copied_admission_inputs() as root:\n            admission.historical_scan_contract(root)  # Warm call cannot authorize later bytes.\n            for relative in sorted(INPUTS):\n                file = root / relative\n                saved, metadata = file.read_bytes(), file.stat()\n                for name, value in [('same-size-mtime', bytes([saved[0] ^ 1]) + saved[1:]),\n", 'after': "            'App/ClubGovernanceCommandForm.swift': '28dcfc08ed90e072e51c7a28202a9af925907c9edbe8a296cf5092678f32174f',\n            '.gitleaksignore': 'e6643cd2a90f794cf60c3f635243897b6fefb5adac156493eb2039e590ee09a0',\n        }.items():\n            self.assertEqual(digest(admission.permission_boundary_bytes(ROOT, path)), expected)\n\n    def test_all_eleven_physical_inputs_reject_same_size_mtime_crlf_and_cr_edits(self):\n        with copied_admission_inputs() as root:\n            admission.historical_scan_contract(root)  # Warm call cannot authorize later bytes.\n            for relative in sorted(COMBINED_INPUTS):\n                file = root / relative\n                saved, metadata = file.read_bytes(), file.stat()\n                for name, value in [('same-size-mtime', bytes([saved[0] ^ 1]) + saved[1:]),\n"}, {'before': '\n    def test_missing_support_and_equivalent_json_are_rejected(self):\n        with copied_admission_inputs() as root:\n            for relative in admission.ADDED_SUPPORT:\n                file = root / relative\n                saved = file.read_bytes()\n                file.unlink()\n', 'after': '\n    def test_missing_support_and_equivalent_json_are_rejected(self):\n        with copied_admission_inputs() as root:\n            for relative in admission.ADDED_SUPPORT + admission.EVOLUTION_SUPPORT:\n                file = root / relative\n                saved = file.read_bytes()\n                file.unlink()\n'}, {'before': '                admission.historical_scan_contract(root)\n            for relative in admission.ADDED_SUPPORT:\n                (root / relative).unlink()\n            self.assertEqual(admission.historical_scan_contract(root), baseline)\n            (root / admission.CONTRACT_PATH).write_bytes((ROOT / admission.CONTRACT_PATH).read_bytes())\n            with self.assertRaises(ValueError):\n', 'after': '                admission.historical_scan_contract(root)\n            for relative in admission.ADDED_SUPPORT:\n                (root / relative).unlink()\n            for relative in admission.EVOLUTION_SOURCES:\n                file = root / relative\n                file.write_bytes(admission.restore_evolution_source(relative, file.read_bytes()))\n            for relative in admission.EVOLUTION_SUPPORT:\n                (root / relative).unlink()\n            self.assertEqual(admission.historical_scan_contract(root), baseline)\n            (root / admission.CONTRACT_PATH).write_bytes((ROOT / admission.CONTRACT_PATH).read_bytes())\n            with self.assertRaises(ValueError):\n'}]}

_FROZEN_READER = historical_scan_contract


def _inverse_row(relative, raw, row):
    if digest(raw) != row['after_sha256']:
        raise ValueError('Unreviewed complete evolution input: ' + relative)
    text = raw.decode('utf-8')
    for hunk in reversed(row['hunks']):
        if text.count(hunk['after']) != 1:
            raise ValueError('Missing/repeated exact evolution span: ' + relative)
        text = text.replace(hunk['after'], hunk['before'], 1)
    restored = text.encode('utf-8')
    if digest(restored) != row['before_sha256']:
        raise ValueError('Evolution did not restore frozen file: ' + relative)
    return restored


def restore_evolution_source(relative, raw):
    return _inverse_row(relative, raw, EVOLUTION_SOURCES[relative])


def _require_old_evolution_domain(root):
    for relative, row in EVOLUTION_SOURCES.items():
        if digest((root / relative).read_bytes()) != row['before_sha256']:
            raise ValueError('Hybrid baseline and keyword/PBX source: ' + relative)
    for relative in EVOLUTION_SUPPORT:
        file = root / relative
        if file.exists() or file.is_symlink():
            raise ValueError('Baseline domain contains new support: ' + relative)


def frozen_permission_contract(root):
    """Validate the whole sixteen-file set, then return exact frozen eleven-file JSON."""
    root = Path(root)
    raw = (root / CONTRACT_PATH).read_bytes()
    if digest(raw) == FROZEN_PERMISSION_CONTRACT_SHA256:
        if digest((root / 'tools/run138_editor_readiness.py').read_bytes()) != FROZEN_PERMISSION_READINESS_SHA256:
            raise ValueError('Hybrid frozen permission reader')
        if digest((root / HELPER_PATH).read_bytes()) != FROZEN_PERMISSION_HELPER_SHA256:
            raise ValueError('Hybrid frozen permission helper')
        _require_old_evolution_domain(root)
        contract = json.loads(raw)
        for relative in SOURCE_EDITS:
            restore_product_source(relative, (root / relative).read_bytes())
        for relative in ADDED_SUPPORT:
            if digest((root / relative).read_bytes()) != contract['feature_batch_support_sha256'][relative]:
                raise ValueError('Hybrid frozen permission support: ' + relative)
        return raw.decode('utf-8')
    from tools import run138_editor_readiness as current
    if digest((root / 'tools/run138_editor_readiness.py').read_bytes()) != current.IMPLEMENTATION_SHA256:
        raise ValueError('Current readiness reader changed')
    contract = current.contract(root)
    if digest((root / HELPER_PATH).read_bytes()) != HELPER_SHA256:
        raise ValueError('Current combined admission reader changed')
    for relative, expected in SOURCE_EDITS.items():
        if contract['feature_batch_sources'].get(relative) != expected:
            raise ValueError('Original permission source row changed: ' + relative)
        restore_product_source(relative, (root / relative).read_bytes())
    for relative in ADDED_SUPPORT + EVOLUTION_SUPPORT:
        expected = contract['feature_batch_support_sha256'].get(relative)
        if not expected or digest((root / relative).read_bytes()) != expected:
            raise ValueError('Combined support input changed: ' + relative)
    for relative in EVOLUTION_SOURCES:
        restore_evolution_source(relative, (root / relative).read_bytes())
    # Both changed original support files must also restore actual frozen bytes.
    _inverse_row(FROZEN_TEST_PATH, (root / FROZEN_TEST_PATH).read_bytes(), TEST_EVOLUTION)
    marker = '\n# Exact keyword/PBX evolution. Original eleven-file reader above is retained byte-for-byte.\n'
    helper = (root / HELPER_PATH).read_bytes().split(marker.encode(), 1)[0]
    if digest(helper) != FROZEN_PERMISSION_HELPER_SHA256:
        raise ValueError('Original permission reader was not retained exactly')
    restored = copy.deepcopy(contract)
    app = 'App/ClubGovernanceViews.swift'
    pbx = 'Questify.xcodeproj/project.pbxproj'
    if restored['feature_batch_sources'].pop(app, None) != EVOLUTION_SOURCES[app]:
        raise ValueError('Keyword source inverse row changed')
    pbx_row = restored['feature_batch_sources'][pbx]
    new_hunks = EVOLUTION_SOURCES[pbx]['hunks']
    if pbx_row['after_sha256'] != EVOLUTION_SOURCES[pbx]['after_sha256'] or pbx_row['hunks'][-len(new_hunks):] != new_hunks:
        raise ValueError('PBX exact extension row changed')
    pbx_row['after_sha256'] = EVOLUTION_SOURCES[pbx]['before_sha256']
    del pbx_row['hunks'][-len(new_hunks):]
    for relative in EVOLUTION_SUPPORT:
        del restored['feature_batch_support_sha256'][relative]
    restored['feature_batch_support_sha256'][FROZEN_TEST_PATH] = TEST_EVOLUTION['before_sha256']
    restored['feature_batch_support_sha256'][HELPER_PATH] = FROZEN_PERMISSION_HELPER_SHA256
    frozen = (json.dumps(restored, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    if digest(frozen) != FROZEN_PERMISSION_CONTRACT_SHA256:
        raise ValueError('Complete frozen eleven-file contract not restored')
    return frozen.decode('utf-8')


def permission_boundary_bytes(root, relative):
    raw = (Path(root) / relative).read_bytes()
    if relative not in EVOLUTION_SOURCES:
        return raw
    frozen_permission_contract(root)
    row = EVOLUTION_SOURCES[relative]
    if digest(raw) == row['before_sha256']:
        return raw  # Only reached after exact frozen-domain validation.
    return restore_evolution_source(relative, raw)


def historical_scan_contract(root):
    root = Path(root)
    raw = (root / CONTRACT_PATH).read_bytes()
    if digest(raw) == BASE_CONTRACT_SHA256:
        # Keep the original baseline rejection order and all its checks.
        baseline = _FROZEN_READER(root)
        _require_old_evolution_domain(root)
        return baseline
    frozen = frozen_permission_contract(root)
    restored = json.loads(frozen)
    for relative in SOURCE_EDITS:
        del restored['feature_batch_sources'][relative]
    for relative in ADDED_SUPPORT:
        del restored['feature_batch_support_sha256'][relative]
    baseline = (json.dumps(restored, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    if digest(baseline) != BASE_CONTRACT_SHA256:
        raise ValueError('Complete historical scanner contract not restored')
    return baseline.decode('utf-8')

# Finite club layer on the exact creator/fixed45 floor. Frozen reader above retained.
CLUB_PRECONTRACT_SHA256 = 'eb80d6bb10463819a30d41530cc00c909d94f6f79fd1108401b22031369b2053'
CLUB_PREADMISSION_SHA256 = 'df08d6c30bcebd89e901e5ae3a5920b22142dbd8b2cf4a7dfa4c765be5917271'
CLUB_PREADMISSION_PATH = 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py'
CLUB_SOURCE_ROWS = {'Core/ClubCustomerHistoryTopicRoute.swift': {'before_sha256': '4fe6609906f468bb3ee4be8acd37ac59ca8bdc9ceb04855ef5365b60bafeec27',
                                              'after_sha256': '566199e3d716e395082b0fe383464a62917b28d3851cf2437e4433ec35bb11e2',
                                              'hunks': [{'before': '        return '
                                                                   '(1...maximum).contains(id) ? id : nil\n'
                                                                   '    }\n'
                                                                   '}\n',
                                                         'after': '        return (1...maximum).contains(id) '
                                                                  '? id : nil\n'
                                                                  '    }\n'
                                                                  '}\n'
                                                                  '\n'
                                                                  '/// Mirrors CRM list/count/detail '
                                                                  'requireGovernable using current access/me '
                                                                  'evidence.\n'
                                                                  '/// Contact-list visibility and '
                                                                  'event-only grants cannot authorize this '
                                                                  'club-wide read.\n'
                                                                  'public extension '
                                                                  'ClubGovernancePermissions {\n'
                                                                  '    func allowsCustomerDirectory(scope: '
                                                                  'ClubGovernanceScope) -> Bool {\n'
                                                                  '        guard active, clubID == '
                                                                  'scope.clubID, (scope.clubID ?? 0) > 0 '
                                                                  'else { return false }\n'
                                                                  '        do { try scope.validate() } catch '
                                                                  '{ return false }\n'
                                                                  '        return '
                                                                  'roleCodes.contains("CLUB_OWNER") || '
                                                                  'roleCodes.contains("CLUB_LEGACY_ADMIN") '
                                                                  '||\n'
                                                                  '            '
                                                                  'permissions.contains("club:member:manage")\n'
                                                                  '    }\n'
                                                                  '}\n'}]},
 'Core/ClubGovernanceContracts.swift': {'before_sha256': 'e8b328600808aad0529d3ec6f993a3bb6a08e0a2c0b6d3c6ba2ea19b6bd03264',
                                        'after_sha256': 'ad3935e5f71a0018c1d9db4c86f6afbb021a4e2c78b92d4b7bd931f8f0fdaa32',
                                        'hunks': [{'before': '        if permission == "ROLES" { return '
                                                             'canManageRoles }\n',
                                                   'after': '        if permission == "ROLES" { return '
                                                            'canManageRoles }\n'
                                                            '        if permission == "CUSTOMER_DIRECTORY" { '
                                                            'return allowsCustomerDirectory(scope: scope) '
                                                            '}\n'},
                                                  {'before': '        case .customers, .customer, '
                                                             '.customerCount, .checkin, .topicCustomers, '
                                                             '.registrations: return "club:member:list:read"',
                                                   'after': '        case .customers, .customer, '
                                                            '.customerCount: return "CUSTOMER_DIRECTORY" // '
                                                            'Local preflight, never an API grant.\n'
                                                            '        case .checkin, .topicCustomers, '
                                                            '.registrations: return '
                                                            '"club:member:list:read"'}]},
 'Tests/CoreTests/ClubGovernanceProductionTests.swift': {'before_sha256': '7ec52b15675c3a14de89bd27b32b28b9079d28fc6da784337e2a1f16fc82aa5f',
                                                         'after_sha256': '772420e3ec145740c416da29bc5ee2b187e10bc21181e149e5947410733e100a',
                                                         'hunks': [{'before': '                payload = '
                                                                              '"{\\"active\\":true,\\"club\\":{\\"id\\":81},\\"roleCodes\\":[\\"CLUB_MEMBER\\"],\\"permissions\\":\\(allowed '
                                                                              '? (chapterFlow ? '
                                                                              '"[\\"club:content:manage\\"]" '
                                                                              ': (banFlow ? '
                                                                              '"[\\"club:member:manage\\"]" '
                                                                              ': '
                                                                              '"[\\"club:member:list:read\\"]")) '
                                                                              ': '
                                                                              '"[]"),\\"canManageRoles\\":false}"\n',
                                                                    'after': '                payload = '
                                                                             '"{\\"active\\":true,\\"club\\":{\\"id\\":81},\\"roleCodes\\":[\\"CLUB_MEMBER\\"],\\"permissions\\":\\(allowed '
                                                                             '? (chapterFlow ? '
                                                                             '"[\\"club:content:manage\\"]" '
                                                                             ': (banFlow ? '
                                                                             '"[\\"club:member:manage\\"]" : '
                                                                             '"[\\"club:member:list:read\\",\\"club:member:manage\\"]")) '
                                                                             ': '
                                                                             '"[]"),\\"canManageRoles\\":false}"\n'}]},
 'App/ClubGovernanceViews.swift': {'before_sha256': 'bff35ca70073f32a548aa10a3741f8e64e82dcb9542117a97c06a22f1d724e4a',
                                   'after_sha256': 'f29b604938d53c1d397f1da93961eae1672a80b45b05bc3016501667dc6533ff',
                                   'hunks': [{'before': 'import SwiftUI\n'
                                                        '\n'
                                                        '/// Mount independently of legacy '
                                                        'isOwner/viewerIsAdmin. access/me decides each row.\n'
                                                        'struct ClubGovernanceEntryButton: View {\n',
                                              'after': 'import SwiftUI\n'
                                                       '\n'
                                                       '/// P044 keyword-only scheduling. The view still '
                                                       'owns authorization and response fences.\n'
                                                       '@MainActor final class ClubCustomerKeywordDebounce '
                                                       '{\n'
                                                       '    static let delayNanoseconds: UInt64 = '
                                                       '300_000_000\n'
                                                       '    private var pending: Task<Void, Never>?\n'
                                                       '    private var revision: UInt64 = 0\n'
                                                       '    private let sleep: @MainActor @Sendable () async '
                                                       'throws -> Void\n'
                                                       '    nonisolated init(sleep: @escaping @MainActor '
                                                       '@Sendable () async throws -> Void = {\n'
                                                       '        try await Task.sleep(nanoseconds: '
                                                       'ClubCustomerKeywordDebounce.delayNanoseconds)\n'
                                                       '    }) { self.sleep = sleep }\n'
                                                       '    func cancel() {\n'
                                                       '        revision &+= 1\n'
                                                       '        pending?.cancel()\n'
                                                       '        pending = nil\n'
                                                       '    }\n'
                                                       '    @discardableResult func schedule(_ action: '
                                                       '@escaping @MainActor () async -> Void) -> Task<Void, '
                                                       'Never> {\n'
                                                       '        cancel()\n'
                                                       '        let expected = revision\n'
                                                       '        let task = Task { @MainActor [weak self] in\n'
                                                       '            guard let self else { return }\n'
                                                       '            do { try await self.sleep() } catch { '
                                                       'return }\n'
                                                       '            guard !Task.isCancelled, self.revision '
                                                       '== expected else { return }\n'
                                                       '            // Release the handle before load() '
                                                       'cancels any still-pending timer.\n'
                                                       '            self.pending = nil\n'
                                                       '            await action()\n'
                                                       '        }\n'
                                                       '        pending = task\n'
                                                       '        return task\n'
                                                       '    }\n'
                                                       '}\n'
                                                       '\n'
                                                       '/// Mount independently of legacy '
                                                       'isOwner/viewerIsAdmin. access/me decides each row.\n'
                                                       'struct ClubGovernanceEntryButton: View {\n'},
                                             {'before': '    @State private var filter = "all"\n'
                                                        '    @State private var topicCustomerFilter: '
                                                        'ClubTopicCustomerFilter = .all\n'
                                                        '    @State private var keyword = ""\n'
                                                        '    @State private var sort = "composite"\n'
                                                        '    @State private var page = 1\n'
                                                        '    @State private var editor: '
                                                        'ClubGovernanceFormRoute?\n',
                                              'after': '    @State private var filter = "all"\n'
                                                       '    @State private var topicCustomerFilter: '
                                                       'ClubTopicCustomerFilter = .all\n'
                                                       '    @State private var keyword = ""\n'
                                                       '    @State private var customerKeywordDebounce = '
                                                       'ClubCustomerKeywordDebounce()\n'
                                                       '    @State private var sort = "composite"\n'
                                                       '    @State private var page = 1\n'
                                                       '    @State private var editor: '
                                                       'ClubGovernanceFormRoute?\n'},
                                             {'before': '                    Picker("club.gov.filter", '
                                                        'selection: $filter) {\n'
                                                        '                        ForEach(["all", "repeat", '
                                                        '"new", "remark"], id: \\.self) { '
                                                        'Text(LocalizedStringKey("club.gov.filter." + '
                                                        '$0)).tag($0) }\n'
                                                        '                    }\n'
                                                        '                    .onChange(of: filter) { _, _ in '
                                                        'Task { await load() } }\n'
                                                        '                    TextField("club.gov.keyword", '
                                                        'text: $keyword).submitLabel(.search).onSubmit { '
                                                        'Task { await load() } }\n'
                                                        '                    Button("club.gov.search") { '
                                                        'Task { await load() } }.disabled(loading)\n'
                                                        '                }\n'
                                                        '            }\n'
                                                        '            if operation == .topicCustomers {\n',
                                              'after': '                    Picker("club.gov.filter", '
                                                       'selection: $filter) {\n'
                                                       '                        ForEach(["all", "repeat", '
                                                       '"new", "remark"], id: \\.self) { '
                                                       'Text(LocalizedStringKey("club.gov.filter." + '
                                                       '$0)).tag($0) }\n'
                                                       '                    }\n'
                                                       '                    .onChange(of: filter) { _, _ in '
                                                       'loadCustomersNow() }\n'
                                                       '                    TextField("club.gov.keyword", '
                                                       'text: $keyword).submitLabel(.search)\n'
                                                       '                        .onChange(of: keyword) { _, '
                                                       '_ in scheduleCustomerKeywordRead() }\n'
                                                       '                        .onSubmit { '
                                                       'loadCustomersNow() }\n'
                                                       '                    Button("club.gov.search") { '
                                                       'loadCustomersNow() }.disabled(loading)\n'
                                                       '                }\n'
                                                       '            }\n'
                                                       '            if operation == .topicCustomers {\n'},
                                             {'before': '        .task(id: readContext) { snapshot = nil; '
                                                        'editor = nil; customerTopic = nil; feedClub = nil; '
                                                        'coordinator.cancelReview(); await load() }\n'
                                                        '        .onChange(of: readContext) { _, _ in '
                                                        'invalidateRead() }\n'
                                                        '        .onChange(of: identity) { _, _ in '
                                                        'invalidateRead() }\n'
                                                        '        .onDisappear { generation &+= 1 }\n'
                                                        '        .refreshable { await load() }\n'
                                                        '    }\n'
                                                        '    private func load() async {\n'
                                                        '        generation &+= 1; let revision = '
                                                        'generation; let expected = identity; let context = '
                                                        'readContext\n'
                                                        '        snapshot = nil; failure = nil; loading = '
                                                        'true\n'
                                                        '        snapshotContext = nil; customerTopic = nil; '
                                                        'feedClub = nil; feedMediaScope = UUID()\n',
                                              'after': '        .task(id: readContext) { snapshot = nil; '
                                                       'editor = nil; customerTopic = nil; feedClub = nil; '
                                                       'coordinator.cancelReview(); await load() }\n'
                                                       '        .onChange(of: readContext) { _, _ in '
                                                       'invalidateRead() }\n'
                                                       '        .onChange(of: identity) { _, _ in '
                                                       'invalidateRead() }\n'
                                                       '        .onDisappear {\n'
                                                       '            if operation == .customers {\n'
                                                       '                customerKeywordDebounce.cancel()\n'
                                                       '                generation &+= 1\n'
                                                       '            }\n'
                                                       '        }\n'
                                                       '        .onDisappear { generation &+= 1 }\n'
                                                       '        .refreshable { await load() }\n'
                                                       '    }\n'
                                                       '    @MainActor private func loadCustomersNow() {\n'
                                                       '        customerKeywordDebounce.cancel()\n'
                                                       '        Task { await load() }\n'
                                                       '    }\n'
                                                       '    @MainActor private func '
                                                       'scheduleCustomerKeywordRead() {\n'
                                                       '        guard operation == .customers else { return '
                                                       '}\n'
                                                       '        let context = readContext; let expected = '
                                                       'identity\n'
                                                       '        let expectedFilter = filter; let '
                                                       'expectedKeyword = keyword\n'
                                                       '        // Invalidate an older response immediately, '
                                                       'including the 300ms wait.\n'
                                                       '        generation &+= 1\n'
                                                       '        snapshot = nil; snapshotContext = nil; '
                                                       'failure = nil; loading = false\n'
                                                       '        let keywordRevision = generation\n'
                                                       '        customerKeywordDebounce.schedule {\n'
                                                       '            guard operation == .customers, context '
                                                       '== readContext, expected == identity,\n'
                                                       '                  access.identity == expected, '
                                                       'keywordRevision == generation,\n'
                                                       '                  filter == expectedFilter, keyword '
                                                       '== expectedKeyword,\n'
                                                       '                  !Task.isCancelled else { return }\n'
                                                       '            await load()\n'
                                                       '        }\n'
                                                       '    }\n'
                                                       '    @MainActor private func load() async {\n'
                                                       '        if operation == .customers { '
                                                       'customerKeywordDebounce.cancel() }\n'
                                                       '        generation &+= 1; let revision = generation; '
                                                       'let expected = identity; let context = readContext\n'
                                                       '        snapshot = nil; failure = nil; loading = '
                                                       'true\n'
                                                       '        snapshotContext = nil; customerTopic = nil; '
                                                       'feedClub = nil; feedMediaScope = UUID()\n'},
                                             {'before': '        }\n'
                                                        '        if revision == generation { loading = false '
                                                        '}\n'
                                                        '    }\n'
                                                        '    private func invalidateRead() {\n'
                                                        '        generation &+= 1; snapshot = nil; '
                                                        'snapshotContext = nil; failure = nil; editor = nil; '
                                                        'customerTopic = nil; feedClub = nil; feedMediaScope '
                                                        '= UUID(); coordinator.cancelReview()\n'
                                                        '    }\n'
                                                        '    private func current(_ target: '
                                                        'ClubFeedClubRoute) -> Bool {\n',
                                              'after': '        }\n'
                                                       '        if revision == generation { loading = false '
                                                       '}\n'
                                                       '    }\n'
                                                       '    @MainActor private func invalidateRead() {\n'
                                                       '        if operation == .customers { '
                                                       'customerKeywordDebounce.cancel() }\n'
                                                       '        generation &+= 1; snapshot = nil; '
                                                       'snapshotContext = nil; failure = nil; editor = nil; '
                                                       'customerTopic = nil; feedClub = nil; feedMediaScope '
                                                       '= UUID(); coordinator.cancelReview()\n'
                                                       '    }\n'
                                                       '    private func current(_ target: '
                                                       'ClubFeedClubRoute) -> Bool {\n'}]}}
CLUB_PBX_PRE_ROW_SHA256 = 'ff594b1b5a61984d047d5b807ee2d3a4c596df75e3537a397abe82cf5054dd71'
CLUB_SUPPORT_PATHS = ('Tests/CoreTests/ClubCustomerPermissionTests.swift',
 'Tests/ContractChecks/test_club_customer_permissions.py',
 'docs/club-customer-permissions.md',
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py',
 'tools/club_customer_directory_admission.py',
 'Tests/ContractChecks/test_club_customer_keyword_debounce.py',
 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift',
 'docs/club-customer-keyword-debounce.md',
 'tools/tests/test_creator_shelf_state_history.py')
CLUB_RAW_SHA256 = {'Core/ClubCustomerHistoryTopicRoute.swift': '566199e3d716e395082b0fe383464a62917b28d3851cf2437e4433ec35bb11e2',
 'Core/ClubGovernanceContracts.swift': 'ad3935e5f71a0018c1d9db4c86f6afbb021a4e2c78b92d4b7bd931f8f0fdaa32',
 'Tests/CoreTests/ClubGovernanceProductionTests.swift': '772420e3ec145740c416da29bc5ee2b187e10bc21181e149e5947410733e100a',
 'Tests/CoreTests/ClubCustomerPermissionTests.swift': 'b4451e3ab27422f568b31c114f2c0cfc30335c24115c36f117b1f64579271590',
 'Tests/ContractChecks/test_club_customer_permissions.py': '773186689d0583d41d6ab75298e4b815e86dc688a2ce5043cdba43d0a5b2ffba',
 'docs/club-customer-permissions.md': 'f32d0102eeb5bb2bc696b139389a5e674140623f7597973ffce5468629cd1f10',
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py': 'b1ee3e1eac62c6a670986301f1fe2713d615c7a8a82ece5dfdd8946ae08e43c1',
 'App/ClubGovernanceViews.swift': 'f29b604938d53c1d397f1da93961eae1672a80b45b05bc3016501667dc6533ff',
 'Tests/ContractChecks/test_club_customer_keyword_debounce.py': '262ed2f2d1151dbe6994048cc21e76b98799fc34a68caeba59c08947508c8e6c',
 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift': '2c3cfc1da3d145221e13d9561c1bfb9166b58c84807bfd93034fcaff44b303a5',
 'docs/club-customer-keyword-debounce.md': '1fa12a8011cb1b2c3d7425dcd8f1f8ca07f27be08adb8a545c1be98f97806f0e',
 'Questify.xcodeproj/project.pbxproj': 'a397f1c25ca67e4657846e799d8b1f55f8755d3debc7bc7609dcc6040afc9f50',
 'tools/tests/test_creator_shelf_state_history.py': 'baa95d45430a19f2a7c472dcd269150197617f45d50735aa84b142ca2973d33c'}
FLOOR_INPUTS = ('App/MerchantBusinessEditor.swift',
 'App/MerchantOperationsEditor.swift',
 'App/ProjectNodeImageCrop.swift',
 'App/TemplateAuthoringMineView.swift',
 'Core/ProfileEditCoordinator.swift',
 'Core/TemplateAuthoringShelf.swift',
 'Resources/Localizable.xcstrings',
 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift',
 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift',
 'Tests/ContractChecks/test_merchant_decor_tag_picker.py',
 'Tests/ContractChecks/test_merchant_review_draft_return.py',
 'Tests/ContractChecks/test_profile_avatar.py',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py',
 'Tests/ContractChecks/test_profile_reload_discard.py',
 'Tests/ContractChecks/test_template_shelf_read_bridge.py',
 'Tests/ContractChecks/test_template_shelf_state_projection.py',
 'Tests/CoreTests/MerchantDecorTagDraftTests.swift',
 'Tests/CoreTests/ProfileEditTests.swift',
 'Tests/CoreTests/ProjectCityStoryNodeRemovalTests.swift',
 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift',
 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift',
 'docs/merchant-decor-tag-picker/implementation.md',
 'docs/profile-read-failure-recovery.md',
 'tools/check_profile_read_failure_contract.py',
 'tools/run_static_checks.py',
 'tools/tests/creator_shelf_refresh_history.py',
 'tools/tests/creator_shelf_state_history.py',
 'tools/tests/test_creator_pending_synthetic_storage_history.py',
 'tools/tests/test_creator_shelf_refresh_history.py',
 'tools/tests/test_creator_shelf_state_history.py',
 'tools/tests/test_gitleaks_configuration.py',
 'tools/tests/test_native_static_checks.py')
CURRENT_SCANNER_SHA256 = 'a5f5cd4f8670fb10405ab73fba1ac15700ace46a0c8dd4e8321e29e5da90cb30'
CLUB_HISTORY_PATH = 'tools/tests/test_creator_shelf_state_history.py'
CLUB_HISTORY_INVERSE = {'before_sha256': '28e14028204276d0277afb29064d0f2ad65bcb05e57aadf226b63d61e606c924',
 'after_sha256': '2632c0f052be7dd29c5981c0c27c1a074b82203463cd177ae21bb69881c8cea7',
 'hunks': [{'before': '        from tools import run138_editor_readiness as planning\n'
                      '        projection.validate_feature_batch_sources(ROOT)\n'
                      '        contract=planning.contract(ROOT)\n'
                      "        self.assertEqual(len(contract['feature_batch_support_sha256']),502)\n"
                      '        original=Path.read_bytes\n'
                      '        # Read actual inputs once; mutations are isolated read substitutions,\n'
                      '        # never copies of the repository or historical acceptance expectations.\n',
            'after': '        from tools import run138_editor_readiness as planning\n'
                     '        projection.validate_feature_batch_sources(ROOT)\n'
                     '        contract=planning.contract(ROOT)\n'
                     '        from Tests.ContractChecks import test_profile_read_failure_remote_admission as '
                     'admission\n'
                     '        current_contract=contract\n'
                     '        '
                     'contract=admission._club_directory_contract(json.loads(json.dumps(contract)),ROOT)\n'
                     "        self.assertEqual(len(contract['feature_batch_support_sha256']),502)\n"
                     '        contract=current_contract\n'
                     '        original=Path.read_bytes\n'
                     '        # Read actual inputs once; mutations are isolated read substitutions,\n'
                     '        # never copies of the repository or historical acceptance expectations.\n'},
           {'before': 'class CreatorFixed45TestPreservation(unittest.TestCase):\n'
                      '    def test_original_reviewed_creator_history_test_restores_complete_bytes(self):\n'
                      "        data=(ROOT/'tools/tests/test_creator_shelf_state_history.py').read_bytes()\n"
                      '        data=_restore_premerchant_history_test(data)\n'
                      "        first=b'\\n# CREATOR_FIXED45_PORT_BEGIN\\n';last=b'# "
                      "CREATOR_FIXED45_PORT_END\\n'\n"
                      '        self.assertEqual(data.count(first),1);self.assertEqual(data.count(last),1)\n'
                      '        start=data.index(first);end=data.index(last,start)+len(last)\n',
            'after': 'class CreatorFixed45TestPreservation(unittest.TestCase):\n'
                     '    def test_original_reviewed_creator_history_test_restores_complete_bytes(self):\n'
                     "        data=(ROOT/'tools/tests/test_creator_shelf_state_history.py').read_bytes()\n"
                     '        data=_restore_premerchant_history_test(_restore_preclub_history_test(data))\n'
                     "        first=b'\\n# CREATOR_FIXED45_PORT_BEGIN\\n';last=b'# "
                     "CREATOR_FIXED45_PORT_END\\n'\n"
                     '        self.assertEqual(data.count(first),1);self.assertEqual(data.count(last),1)\n'
                     '        start=data.index(first);end=data.index(last,start)+len(last)\n'}]}
FROZEN16_HELPER_SHA256 = 'bf14068e7dd7c8193c88121064168935b88c608ef0def7730e9eb878bc264cea'
FROZEN16_CONTRACT_SHA256 = '2ad2b32bd6063a28f4d1acce78c600c2e0285565032b9ae6ab833bc01581b54a'
FROZEN16_TEST_INVERSE = {'before_sha256': '9248aa6900c69569aa2f7d27ac3d3dbb58293f363f5dc580a84a0ab60b325aa5',
 'after_sha256': 'b1ee3e1eac62c6a670986301f1fe2713d615c7a8a82ece5dfdd8946ae08e43c1',
 'hunks': [{'before': 'ROOT = Path(__file__).resolve().parents[2]\n'
                      'INPUTS = set(admission.SOURCE_EDITS) | set(admission.ADDED_SUPPORT) | {\n'
                      "    admission.CONTRACT_PATH, 'tools/run138_editor_readiness.py'}\n"
                      'COMBINED_INPUTS = INPUTS | set(admission.EVOLUTION_SOURCES) | '
                      'set(admission.EVOLUTION_SUPPORT)\n'
                      '\n'
                      '\n'
                      'def digest(raw):\n',
            'after': 'ROOT = Path(__file__).resolve().parents[2]\n'
                     'INPUTS = set(admission.SOURCE_EDITS) | set(admission.ADDED_SUPPORT) | {\n'
                     "    admission.CONTRACT_PATH, 'tools/run138_editor_readiness.py'}\n"
                     'COMBINED_INPUTS = INPUTS | set(admission.EVOLUTION_SOURCES) | '
                     'set(admission.EVOLUTION_SUPPORT) | set(admission.FLOOR_INPUTS)\n'
                     '\n'
                     '\n'
                     'def digest(raw):\n'},
           {'before': '\n'
                      '@contextmanager\n'
                      'def copied_admission_inputs():\n'
                      '    """Only the sixteen admission files, never a repository or historical '
                      'checkout."""\n'
                      "    with tempfile.TemporaryDirectory(prefix='club-directory-admission-') as "
                      'temporary:\n'
                      '        root = Path(temporary)\n'
                      '        for relative in sorted(COMBINED_INPUTS):\n',
            'after': '\n'
                     '@contextmanager\n'
                     'def copied_admission_inputs():\n'
                     '    """Only bounded club and preceding admission inputs, never a repository '
                     'checkout."""\n'
                     "    with tempfile.TemporaryDirectory(prefix='club-directory-admission-') as "
                     'temporary:\n'
                     '        root = Path(temporary)\n'
                     '        for relative in sorted(COMBINED_INPUTS):\n'},
           {'before': '    def '
                      'test_three_product_sources_restore_exact_published_baseline_and_reject_edits(self):\n'
                      '        self.assertEqual(len(admission.SOURCE_EDITS), 4)\n'
                      '        for relative, row in admission.SOURCE_EDITS.items():\n'
                      '            raw = (ROOT / relative).read_bytes()\n'
                      '            restored = admission.restore_product_source(relative, raw)\n'
                      "            self.assertEqual(digest(restored), row['before_sha256'])\n"
                      "            self.assertEqual(digest(raw), row['after_sha256'])\n",
            'after': '    def '
                     'test_three_product_sources_restore_exact_published_baseline_and_reject_edits(self):\n'
                     '        self.assertEqual(len(admission.SOURCE_EDITS), 4)\n'
                     '        for relative, row in admission.SOURCE_EDITS.items():\n'
                     '            raw = admission.permission_product_bytes(ROOT, relative)\n'
                     '            restored = admission.restore_product_source(relative, raw)\n'
                     "            self.assertEqual(digest(restored), row['before_sha256'])\n"
                     "            self.assertEqual(digest(raw), row['after_sha256'])\n"},
           {'before': '\n'
                      '    def '
                      'test_original_scanner_methods_assertions_and_historical_lines_are_preserved(self):\n'
                      "        path = 'tools/tests/test_gitleaks_configuration.py'\n"
                      '        raw = (ROOT / path).read_bytes()\n'
                      '        previous = admission.restore_product_source(path, raw)\n'
                      '        self.assertEqual(digest(previous), '
                      "'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c')\n"
                      '        old_tree, new_tree = ast.parse(previous), ast.parse(raw)\n',
            'after': '\n'
                     '    def '
                     'test_original_scanner_methods_assertions_and_historical_lines_are_preserved(self):\n'
                     "        path = 'tools/tests/test_gitleaks_configuration.py'\n"
                     '        raw = admission.permission_product_bytes(ROOT, path)\n'
                     '        previous = admission.restore_product_source(path, raw)\n'
                     '        self.assertEqual(digest(previous), '
                     "'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c')\n"
                     '        old_tree, new_tree = ast.parse(previous), ast.parse(raw)\n'},
           {'before': '                file.write_bytes(admission.restore_evolution_source(relative, '
                      'file.read_bytes()))\n'
                      '            for relative in admission.EVOLUTION_SUPPORT:\n'
                      '                (root / relative).unlink()\n'
                      '            self.assertEqual(admission.historical_scan_contract(root), baseline)\n'
                      '            (root / admission.CONTRACT_PATH).write_bytes((ROOT / '
                      'admission.CONTRACT_PATH).read_bytes())\n'
                      '            with self.assertRaises(ValueError):\n',
            'after': '                file.write_bytes(admission.restore_evolution_source(relative, '
                     'file.read_bytes()))\n'
                     '            for relative in admission.EVOLUTION_SUPPORT:\n'
                     '                (root / relative).unlink()\n'
                     '            (root / admission.CLUB_PREADMISSION_PATH).unlink()\n'
                     '            self.assertEqual(admission.historical_scan_contract(root), baseline)\n'
                     '            (root / admission.CONTRACT_PATH).write_bytes((ROOT / '
                     'admission.CONTRACT_PATH).read_bytes())\n'
                     '            with self.assertRaises(ValueError):\n'}]}
FROZEN16_SOURCE_ROWS = {'Core/ClubCustomerHistoryTopicRoute.swift': {'before_sha256': '4fe6609906f468bb3ee4be8acd37ac59ca8bdc9ceb04855ef5365b60bafeec27',
                                              'after_sha256': '566199e3d716e395082b0fe383464a62917b28d3851cf2437e4433ec35bb11e2',
                                              'hunks': [{'before': '        return '
                                                                   '(1...maximum).contains(id) ? id : nil\n'
                                                                   '    }\n'
                                                                   '}\n',
                                                         'after': '        return (1...maximum).contains(id) '
                                                                  '? id : nil\n'
                                                                  '    }\n'
                                                                  '}\n'
                                                                  '\n'
                                                                  '/// Mirrors CRM list/count/detail '
                                                                  'requireGovernable using current access/me '
                                                                  'evidence.\n'
                                                                  '/// Contact-list visibility and '
                                                                  'event-only grants cannot authorize this '
                                                                  'club-wide read.\n'
                                                                  'public extension '
                                                                  'ClubGovernancePermissions {\n'
                                                                  '    func allowsCustomerDirectory(scope: '
                                                                  'ClubGovernanceScope) -> Bool {\n'
                                                                  '        guard active, clubID == '
                                                                  'scope.clubID, (scope.clubID ?? 0) > 0 '
                                                                  'else { return false }\n'
                                                                  '        do { try scope.validate() } catch '
                                                                  '{ return false }\n'
                                                                  '        return '
                                                                  'roleCodes.contains("CLUB_OWNER") || '
                                                                  'roleCodes.contains("CLUB_LEGACY_ADMIN") '
                                                                  '||\n'
                                                                  '            '
                                                                  'permissions.contains("club:member:manage")\n'
                                                                  '    }\n'
                                                                  '}\n'}]},
 'Core/ClubGovernanceContracts.swift': {'before_sha256': 'e8b328600808aad0529d3ec6f993a3bb6a08e0a2c0b6d3c6ba2ea19b6bd03264',
                                        'after_sha256': 'ad3935e5f71a0018c1d9db4c86f6afbb021a4e2c78b92d4b7bd931f8f0fdaa32',
                                        'hunks': [{'before': '        if permission == "ROLES" { return '
                                                             'canManageRoles }\n',
                                                   'after': '        if permission == "ROLES" { return '
                                                            'canManageRoles }\n'
                                                            '        if permission == "CUSTOMER_DIRECTORY" { '
                                                            'return allowsCustomerDirectory(scope: scope) '
                                                            '}\n'},
                                                  {'before': '        case .customers, .customer, '
                                                             '.customerCount, .checkin, .topicCustomers, '
                                                             '.registrations: return "club:member:list:read"',
                                                   'after': '        case .customers, .customer, '
                                                            '.customerCount: return "CUSTOMER_DIRECTORY" // '
                                                            'Local preflight, never an API grant.\n'
                                                            '        case .checkin, .topicCustomers, '
                                                            '.registrations: return '
                                                            '"club:member:list:read"'}]},
 'Tests/CoreTests/ClubGovernanceProductionTests.swift': {'before_sha256': '7ec52b15675c3a14de89bd27b32b28b9079d28fc6da784337e2a1f16fc82aa5f',
                                                         'after_sha256': '772420e3ec145740c416da29bc5ee2b187e10bc21181e149e5947410733e100a',
                                                         'hunks': [{'before': '                payload = '
                                                                              '"{\\"active\\":true,\\"club\\":{\\"id\\":81},\\"roleCodes\\":[\\"CLUB_MEMBER\\"],\\"permissions\\":\\(allowed '
                                                                              '? (chapterFlow ? '
                                                                              '"[\\"club:content:manage\\"]" '
                                                                              ': (banFlow ? '
                                                                              '"[\\"club:member:manage\\"]" '
                                                                              ': '
                                                                              '"[\\"club:member:list:read\\"]")) '
                                                                              ': '
                                                                              '"[]"),\\"canManageRoles\\":false}"\n',
                                                                    'after': '                payload = '
                                                                             '"{\\"active\\":true,\\"club\\":{\\"id\\":81},\\"roleCodes\\":[\\"CLUB_MEMBER\\"],\\"permissions\\":\\(allowed '
                                                                             '? (chapterFlow ? '
                                                                             '"[\\"club:content:manage\\"]" '
                                                                             ': (banFlow ? '
                                                                             '"[\\"club:member:manage\\"]" : '
                                                                             '"[\\"club:member:list:read\\",\\"club:member:manage\\"]")) '
                                                                             ': '
                                                                             '"[]"),\\"canManageRoles\\":false}"\n'}]},
 'tools/tests/test_gitleaks_configuration.py': {'before_sha256': 'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c',
                                                'after_sha256': 'e6c0f1cb301fa8a762040ad4ed81c3ab8e5493ca1bfb99329bbbceb395b0c868',
                                                'hunks': [{'before': 'import unittest\n',
                                                           'after': 'import unittest\n'
                                                                    'from '
                                                                    'tools.club_customer_directory_admission '
                                                                    'import historical_scan_contract\n'},
                                                          {'before': '        raw = (ROOT / '
                                                                     'FILE_DIGEST_PATH).read_text()',
                                                           'after': '        raw = '
                                                                    'historical_scan_contract(ROOT)'}]},
 'App/ClubGovernanceViews.swift': {'before_sha256': 'bff35ca70073f32a548aa10a3741f8e64e82dcb9542117a97c06a22f1d724e4a',
                                   'after_sha256': 'f29b604938d53c1d397f1da93961eae1672a80b45b05bc3016501667dc6533ff',
                                   'hunks': [{'before': 'import SwiftUI\n'
                                                        '\n'
                                                        '/// Mount independently of legacy '
                                                        'isOwner/viewerIsAdmin. access/me decides each row.\n'
                                                        'struct ClubGovernanceEntryButton: View {\n',
                                              'after': 'import SwiftUI\n'
                                                       '\n'
                                                       '/// P044 keyword-only scheduling. The view still '
                                                       'owns authorization and response fences.\n'
                                                       '@MainActor final class ClubCustomerKeywordDebounce '
                                                       '{\n'
                                                       '    static let delayNanoseconds: UInt64 = '
                                                       '300_000_000\n'
                                                       '    private var pending: Task<Void, Never>?\n'
                                                       '    private var revision: UInt64 = 0\n'
                                                       '    private let sleep: @MainActor @Sendable () async '
                                                       'throws -> Void\n'
                                                       '    nonisolated init(sleep: @escaping @MainActor '
                                                       '@Sendable () async throws -> Void = {\n'
                                                       '        try await Task.sleep(nanoseconds: '
                                                       'ClubCustomerKeywordDebounce.delayNanoseconds)\n'
                                                       '    }) { self.sleep = sleep }\n'
                                                       '    func cancel() {\n'
                                                       '        revision &+= 1\n'
                                                       '        pending?.cancel()\n'
                                                       '        pending = nil\n'
                                                       '    }\n'
                                                       '    @discardableResult func schedule(_ action: '
                                                       '@escaping @MainActor () async -> Void) -> Task<Void, '
                                                       'Never> {\n'
                                                       '        cancel()\n'
                                                       '        let expected = revision\n'
                                                       '        let task = Task { @MainActor [weak self] in\n'
                                                       '            guard let self else { return }\n'
                                                       '            do { try await self.sleep() } catch { '
                                                       'return }\n'
                                                       '            guard !Task.isCancelled, self.revision '
                                                       '== expected else { return }\n'
                                                       '            // Release the handle before load() '
                                                       'cancels any still-pending timer.\n'
                                                       '            self.pending = nil\n'
                                                       '            await action()\n'
                                                       '        }\n'
                                                       '        pending = task\n'
                                                       '        return task\n'
                                                       '    }\n'
                                                       '}\n'
                                                       '\n'
                                                       '/// Mount independently of legacy '
                                                       'isOwner/viewerIsAdmin. access/me decides each row.\n'
                                                       'struct ClubGovernanceEntryButton: View {\n'},
                                             {'before': '    @State private var filter = "all"\n'
                                                        '    @State private var topicCustomerFilter: '
                                                        'ClubTopicCustomerFilter = .all\n'
                                                        '    @State private var keyword = ""\n'
                                                        '    @State private var sort = "composite"\n'
                                                        '    @State private var page = 1\n'
                                                        '    @State private var editor: '
                                                        'ClubGovernanceFormRoute?\n',
                                              'after': '    @State private var filter = "all"\n'
                                                       '    @State private var topicCustomerFilter: '
                                                       'ClubTopicCustomerFilter = .all\n'
                                                       '    @State private var keyword = ""\n'
                                                       '    @State private var customerKeywordDebounce = '
                                                       'ClubCustomerKeywordDebounce()\n'
                                                       '    @State private var sort = "composite"\n'
                                                       '    @State private var page = 1\n'
                                                       '    @State private var editor: '
                                                       'ClubGovernanceFormRoute?\n'},
                                             {'before': '                    Picker("club.gov.filter", '
                                                        'selection: $filter) {\n'
                                                        '                        ForEach(["all", "repeat", '
                                                        '"new", "remark"], id: \\.self) { '
                                                        'Text(LocalizedStringKey("club.gov.filter." + '
                                                        '$0)).tag($0) }\n'
                                                        '                    }\n'
                                                        '                    .onChange(of: filter) { _, _ in '
                                                        'Task { await load() } }\n'
                                                        '                    TextField("club.gov.keyword", '
                                                        'text: $keyword).submitLabel(.search).onSubmit { '
                                                        'Task { await load() } }\n'
                                                        '                    Button("club.gov.search") { '
                                                        'Task { await load() } }.disabled(loading)\n'
                                                        '                }\n'
                                                        '            }\n'
                                                        '            if operation == .topicCustomers {\n',
                                              'after': '                    Picker("club.gov.filter", '
                                                       'selection: $filter) {\n'
                                                       '                        ForEach(["all", "repeat", '
                                                       '"new", "remark"], id: \\.self) { '
                                                       'Text(LocalizedStringKey("club.gov.filter." + '
                                                       '$0)).tag($0) }\n'
                                                       '                    }\n'
                                                       '                    .onChange(of: filter) { _, _ in '
                                                       'loadCustomersNow() }\n'
                                                       '                    TextField("club.gov.keyword", '
                                                       'text: $keyword).submitLabel(.search)\n'
                                                       '                        .onChange(of: keyword) { _, '
                                                       '_ in scheduleCustomerKeywordRead() }\n'
                                                       '                        .onSubmit { '
                                                       'loadCustomersNow() }\n'
                                                       '                    Button("club.gov.search") { '
                                                       'loadCustomersNow() }.disabled(loading)\n'
                                                       '                }\n'
                                                       '            }\n'
                                                       '            if operation == .topicCustomers {\n'},
                                             {'before': '        .task(id: readContext) { snapshot = nil; '
                                                        'editor = nil; customerTopic = nil; feedClub = nil; '
                                                        'coordinator.cancelReview(); await load() }\n'
                                                        '        .onChange(of: readContext) { _, _ in '
                                                        'invalidateRead() }\n'
                                                        '        .onChange(of: identity) { _, _ in '
                                                        'invalidateRead() }\n'
                                                        '        .onDisappear { generation &+= 1 }\n'
                                                        '        .refreshable { await load() }\n'
                                                        '    }\n'
                                                        '    private func load() async {\n'
                                                        '        generation &+= 1; let revision = '
                                                        'generation; let expected = identity; let context = '
                                                        'readContext\n'
                                                        '        snapshot = nil; failure = nil; loading = '
                                                        'true\n'
                                                        '        snapshotContext = nil; customerTopic = nil; '
                                                        'feedClub = nil; feedMediaScope = UUID()\n',
                                              'after': '        .task(id: readContext) { snapshot = nil; '
                                                       'editor = nil; customerTopic = nil; feedClub = nil; '
                                                       'coordinator.cancelReview(); await load() }\n'
                                                       '        .onChange(of: readContext) { _, _ in '
                                                       'invalidateRead() }\n'
                                                       '        .onChange(of: identity) { _, _ in '
                                                       'invalidateRead() }\n'
                                                       '        .onDisappear {\n'
                                                       '            if operation == .customers {\n'
                                                       '                customerKeywordDebounce.cancel()\n'
                                                       '                generation &+= 1\n'
                                                       '            }\n'
                                                       '        }\n'
                                                       '        .onDisappear { generation &+= 1 }\n'
                                                       '        .refreshable { await load() }\n'
                                                       '    }\n'
                                                       '    @MainActor private func loadCustomersNow() {\n'
                                                       '        customerKeywordDebounce.cancel()\n'
                                                       '        Task { await load() }\n'
                                                       '    }\n'
                                                       '    @MainActor private func '
                                                       'scheduleCustomerKeywordRead() {\n'
                                                       '        guard operation == .customers else { return '
                                                       '}\n'
                                                       '        let context = readContext; let expected = '
                                                       'identity\n'
                                                       '        let expectedFilter = filter; let '
                                                       'expectedKeyword = keyword\n'
                                                       '        // Invalidate an older response immediately, '
                                                       'including the 300ms wait.\n'
                                                       '        generation &+= 1\n'
                                                       '        snapshot = nil; snapshotContext = nil; '
                                                       'failure = nil; loading = false\n'
                                                       '        let keywordRevision = generation\n'
                                                       '        customerKeywordDebounce.schedule {\n'
                                                       '            guard operation == .customers, context '
                                                       '== readContext, expected == identity,\n'
                                                       '                  access.identity == expected, '
                                                       'keywordRevision == generation,\n'
                                                       '                  filter == expectedFilter, keyword '
                                                       '== expectedKeyword,\n'
                                                       '                  !Task.isCancelled else { return }\n'
                                                       '            await load()\n'
                                                       '        }\n'
                                                       '    }\n'
                                                       '    @MainActor private func load() async {\n'
                                                       '        if operation == .customers { '
                                                       'customerKeywordDebounce.cancel() }\n'
                                                       '        generation &+= 1; let revision = generation; '
                                                       'let expected = identity; let context = readContext\n'
                                                       '        snapshot = nil; failure = nil; loading = '
                                                       'true\n'
                                                       '        snapshotContext = nil; customerTopic = nil; '
                                                       'feedClub = nil; feedMediaScope = UUID()\n'},
                                             {'before': '        }\n'
                                                        '        if revision == generation { loading = false '
                                                        '}\n'
                                                        '    }\n'
                                                        '    private func invalidateRead() {\n'
                                                        '        generation &+= 1; snapshot = nil; '
                                                        'snapshotContext = nil; failure = nil; editor = nil; '
                                                        'customerTopic = nil; feedClub = nil; feedMediaScope '
                                                        '= UUID(); coordinator.cancelReview()\n'
                                                        '    }\n'
                                                        '    private func current(_ target: '
                                                        'ClubFeedClubRoute) -> Bool {\n',
                                              'after': '        }\n'
                                                       '        if revision == generation { loading = false '
                                                       '}\n'
                                                       '    }\n'
                                                       '    @MainActor private func invalidateRead() {\n'
                                                       '        if operation == .customers { '
                                                       'customerKeywordDebounce.cancel() }\n'
                                                       '        generation &+= 1; snapshot = nil; '
                                                       'snapshotContext = nil; failure = nil; editor = nil; '
                                                       'customerTopic = nil; feedClub = nil; feedMediaScope '
                                                       '= UUID(); coordinator.cancelReview()\n'
                                                       '    }\n'
                                                       '    private func current(_ target: '
                                                       'ClubFeedClubRoute) -> Bool {\n'}]}}
FROZEN16_SUPPORT_ROWS = {'Tests/CoreTests/ClubCustomerPermissionTests.swift': 'b4451e3ab27422f568b31c114f2c0cfc30335c24115c36f117b1f64579271590',
 'Tests/ContractChecks/test_club_customer_permissions.py': '773186689d0583d41d6ab75298e4b815e86dc688a2ce5043cdba43d0a5b2ffba',
 'docs/club-customer-permissions.md': 'f32d0102eeb5bb2bc696b139389a5e674140623f7597973ffce5468629cd1f10',
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py': '9248aa6900c69569aa2f7d27ac3d3dbb58293f363f5dc580a84a0ab60b325aa5',
 'tools/club_customer_directory_admission.py': 'bf14068e7dd7c8193c88121064168935b88c608ef0def7730e9eb878bc264cea',
 'Tests/ContractChecks/test_club_customer_keyword_debounce.py': '262ed2f2d1151dbe6994048cc21e76b98799fc34a68caeba59c08947508c8e6c',
 'Tests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift': '2c3cfc1da3d145221e13d9561c1bfb9166b58c84807bfd93034fcaff44b303a5',
 'docs/club-customer-keyword-debounce.md': '1fa12a8011cb1b2c3d7425dcd8f1f8ca07f27be08adb8a545c1be98f97806f0e'}
FROZEN_SCANNER_BYTES = ('"""Offline configuration guards; the real full-history scanner runs in CI."""\n'
 'from pathlib import Path\n'
 'import re\n'
 'import json\n'
 'import hashlib\n'
 'import unittest\n'
 'from tools.club_customer_directory_admission import historical_scan_contract\n'
 '\n'
 '\n'
 'ROOT = Path(__file__).resolve().parents[2]\n'
 'MAIN_MERGE_COMMIT = "4e7349186d21448354d3bf4c6b4ab6adfc25fc1f"\n'
 'MAIN_MERGE_RECORDS = json.loads((ROOT / '
 '"tools/tests/fixtures/gitleaks-main-merge-audit-2026-10-05.json").read_text())["findings"]\n'
 'MAIN_MERGE_FINDINGS = {f"{r[\'commit\']}:{r[\'path\']}:{r[\'rule\']}:{r[\'line\']}" for r in '
 'MAIN_MERGE_RECORDS}\n'
 'IMPORT_COMMIT = "e39c367a35e1f15f9553701cbad56d0d10796c80"\n'
 'COVERAGE_PROSE_FINDING = '
 '"bcd754bd41dd41b3dad22a436211cd89ee47b657:docs/public-template/composition-read-grant.md:generic-api-key:75"\n'
 'CI132_PROSE_FINDING = '
 '"c95737b4c54881a7492ca72bd31f68749304d1d1:docs/square-post-local-media.md:generic-api-key:31"\n'
 'FILE_DIGEST_COMMIT = "65023b84211895bf6c3f6d8ec64804edbfc45e4d"\n'
 'FILE_DIGEST_PATH = "tools/run138_editor_readiness_contract.json"\n'
 'FILE_DIGEST_RECORDS = (\n'
 '    (174, "current_ui_sources", "WeChatAppAuthFlowTests.swift",\n'
 '     "Tests/AppUITests/WeChatAppAuthFlowTests.swift",\n'
 '     "ea2f3808becfbbc25f684cadf02ed8ad3f402d91ea621ead1b4d0c107890aeaa"),\n'
 '    (243, "previous_ui_sources", "WeChatAppAuthFlowTests.swift",\n'
 '     "Tests/AppUITests/WeChatAppAuthFlowTests.swift",\n'
 '     "ea2f3808becfbbc25f684cadf02ed8ad3f402d91ea621ead1b4d0c107890aeaa"),\n'
 '    (4028, "feature_batch_support_sha256", '
 '"Tests/ContractChecks/test_merchant_business_access_lifetime.py",\n'
 '     "Tests/ContractChecks/test_merchant_business_access_lifetime.py",\n'
 '     "a808e190bda202c021e4cbada812e684d92e4e7ac6848d2016c944c3d3d494e4"),\n'
 ')\n'
 'FILE_DIGEST_FINDINGS = {\n'
 '    f"{FILE_DIGEST_COMMIT}:{FILE_DIGEST_PATH}:generic-api-key:{row[0]}"\n'
 '    for row in FILE_DIGEST_RECORDS\n'
 '}\n'
 '\n'
 'COUPON_FIXTURE_FINDINGS = {\n'
 '    f"abe535809517ceb327223679f85c14b5f5b8b6d7:App/CouponRuntimeFixture.swift:generic-api-key:{line}"\n'
 '    for line in (55, 81, 110)\n'
 '}\n'
 '\n'
 '\n'
 'class GitleaksConfigurationTests(unittest.TestCase):\n'
 '    def test_reviewed_ignores_are_commit_bound(self):\n'
 '        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")]\n'
 '        self.assertEqual(len(entries), 92)\n'
 '        self.assertEqual(len(set(entries)), 92)\n'
 '        self.assertEqual(entries.count(COVERAGE_PROSE_FINDING), 1)\n'
 '        self.assertEqual(entries.count(CI132_PROSE_FINDING), 1)\n'
 '        legacy = [entry for entry in entries if entry not in (COVERAGE_PROSE_FINDING, CI132_PROSE_FINDING) '
 'and entry not in COUPON_FIXTURE_FINDINGS and entry not in MAIN_MERGE_FINDINGS and entry not in '
 'FILE_DIGEST_FINDINGS]\n'
 '        self.assertEqual(len(legacy), 42)\n'
 '        for entry in legacy:\n'
 '            with self.subTest(entry=entry):\n'
 '                self.assertRegex(entry, rf"^{IMPORT_COMMIT}:[^:*?\\[\\]]+:generic-api-key:[1-9][0-9]*$")\n'
 '                commit, path, rule, line = entry.split(":")\n'
 '                self.assertNotIn(f"{path}:{rule}:{line}", entries)\n'
 '                self.assertNotIn(f"{\'0\' * 40}:{path}:{rule}:{line}", entries)\n'
 '\n'
 '    def test_main_merge_exceptions_bind_exact_source_lines_and_do_not_cover_new_history(self):\n'
 '        entries = {line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")}\n'
 '        self.assertEqual(len(MAIN_MERGE_FINDINGS), 42)\n'
 '        self.assertTrue(MAIN_MERGE_FINDINGS.issubset(entries))\n'
 '        self.assertEqual({r["classification"] for r in MAIN_MERGE_RECORDS},\n'
 '                         {"external_source_sha256_provenance", "native_source_sha256", '
 '"forbidden_mutation_route_assertion_literal"})\n'
 '        for row in MAIN_MERGE_RECORDS:\n'
 '            with self.subTest(path=row["path"], line=row["line"]):\n'
 '                self.assertEqual(row["commit"], MAIN_MERGE_COMMIT)\n'
 '                self.assertEqual(row["rule"], "generic-api-key")\n'
 '                line = (ROOT / row["path"]).read_text().splitlines()[row["line"] - 1]\n'
 '                self.assertEqual(hashlib.sha256(line.encode()).hexdigest(), row["source_line_sha256"])\n'
 '                suffix = f"{row[\'path\']}:{row[\'rule\']}:{row[\'line\']}"\n'
 '                self.assertNotIn(suffix, entries)\n'
 '                self.assertNotIn("0" * 40 + ":" + suffix, entries)\n'
 '                unlisted_line = max(r["line"] for r in MAIN_MERGE_RECORDS if r["path"] == row["path"]) + '
 '1\n'
 '                self.assertNotIn(f"{MAIN_MERGE_COMMIT}:{row[\'path\']}:{row[\'rule\']}:{unlisted_line}", '
 'entries)\n'
 '                self.assertNotIn(f"{MAIN_MERGE_COMMIT}:{row[\'path\']}:other-rule:{row[\'line\']}", '
 'entries)\n'
 '        self.assertFalse(any(entry.startswith("6757dfac63086ac80bc849df587895bcaaa820df:") for entry in '
 'entries))\n'
 '\n'
 '    def test_file_digest_findings_recompute_from_exact_native_source_bytes(self):\n'
 '        raw = historical_scan_contract(ROOT)\n'
 '        contract = json.loads(raw)\n'
 '        for number, section, key, source, line_digest in FILE_DIGEST_RECORDS:\n'
 '            with self.subTest(line=number):\n'
 '                line = raw.splitlines()[number - 1]\n'
 '                self.assertEqual(hashlib.sha256(line.encode()).hexdigest(), line_digest)\n'
 '                expected = hashlib.sha256((ROOT / source).read_bytes()).hexdigest()\n'
 '                self.assertEqual(contract[section][key], expected)\n'
 '                # Bind the actual finding line to the reviewed JSON field, not just a matching value '
 'elsewhere.\n'
 '                self.assertEqual(json.loads("{" + line.strip().rstrip(",") + "}"), {key: expected})\n'
 '\n'
 '    def test_file_digest_exceptions_cannot_ignore_new_commits_paths_rules_or_lines(self):\n'
 '        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")]\n'
 '        self.assertEqual({entry for entry in entries if FILE_DIGEST_PATH in entry}, FILE_DIGEST_FINDINGS)\n'
 '        self.assertEqual({entry for entry in entries if entry.startswith(FILE_DIGEST_COMMIT + ":")}, '
 'FILE_DIGEST_FINDINGS)\n'
 '        for finding in FILE_DIGEST_FINDINGS:\n'
 '            self.assertEqual(entries.count(finding), 1)\n'
 '            commit, path, rule, line = finding.split(":")\n'
 '            for other in (f"{path}:{rule}:{line}",\n'
 '                          f"{\'0\' * 40}:{path}:{rule}:{line}",\n'
 '                          f"{commit}:tools/other.json:{rule}:{line}",\n'
 '                          f"{commit}:{path}:other-rule:{line}",\n'
 '                          f"{commit}:{path}:{rule}:{int(line) - 1}",\n'
 '                          f"{commit}:{path}:{rule}:{int(line) + 1}"):\n'
 '                with self.subTest(other=other):\n'
 '                    self.assertNotIn(other, entries)\n'
 '        self.assertFalse((ROOT / ".gitleaks.toml").exists())\n'
 '\n'
 '    def test_new_prose_exception_is_exact_and_new_text_is_not_ignored(self):\n'
 '        commit, path, rule, line = COVERAGE_PROSE_FINDING.split(":")\n'
 '        self.assertEqual(commit, "bcd754bd41dd41b3dad22a436211cd89ee47b657")\n'
 '        self.assertEqual(path, "docs/public-template/composition-read-grant.md")\n'
 '        self.assertEqual((rule, line), ("generic-api-key", "75"))\n'
 '        entries = (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '        self.assertNotIn(f"{path}:{rule}:{line}", entries)\n'
 '        self.assertNotIn(f"{\'0\' * 40}:{path}:{rule}:{line}", entries)\n'
 '        self.assertIn("viewers, absent grants", (ROOT / path).read_text())\n'
 '\n'
 '    def test_ci132_prose_exception_cannot_ignore_other_commits_paths_rules_or_lines(self):\n'
 '        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")]\n'
 '        commit, path, rule, line = CI132_PROSE_FINDING.split(":")\n'
 '        self.assertEqual(commit, "c95737b4c54881a7492ca72bd31f68749304d1d1")\n'
 '        self.assertEqual(path, "docs/square-post-local-media.md")\n'
 '        self.assertEqual((rule, line), ("generic-api-key", "31"))\n'
 '        self.assertEqual([entry for entry in entries if path in entry], [CI132_PROSE_FINDING])\n'
 '        for other in (f"{path}:{rule}:{line}",\n'
 '                      f"{\'0\' * 40}:{path}:{rule}:{line}",\n'
 '                      f"{commit}:docs/other.md:{rule}:{line}",\n'
 '                      f"{commit}:{path}:other-rule:{line}",\n'
 '                      f"{commit}:{path}:{rule}:30",\n'
 '                      f"{commit}:{path}:{rule}:32"):\n'
 '            with self.subTest(other=other):\n'
 '                self.assertNotIn(other, entries)\n'
 '        for entry in entries:\n'
 '            self.assertRegex(entry, r"^[0-9a-f]{40}:[^:*?\\[\\]]+:generic-api-key:[1-9][0-9]*$")\n'
 '        current_line = (ROOT / path).read_text().splitlines()[int(line) - 1]\n'
 '        self.assertIn("Backend ownership checks and moderation remain prerequisites.", current_line)\n'
 '        self.assertIn("Readback must remain authenticated.", current_line)\n'
 '        self.assertIn("Expired or revoked approvals and interrupted uploads require explicit recovery '
 'handling.", current_line)\n'
 '\n'
 '    def test_coupon_fixture_exceptions_are_exact_historical_findings_only(self):\n'
 '        entries = [line.strip() for line in (ROOT / ".gitleaksignore").read_text().splitlines()\n'
 '                   if line.strip() and not line.lstrip().startswith("#")]\n'
 '        self.assertEqual({entry for entry in entries if "CouponRuntimeFixture" in entry}, '
 'COUPON_FIXTURE_FINDINGS)\n'
 '        for finding in COUPON_FIXTURE_FINDINGS:\n'
 '            self.assertEqual(entries.count(finding), 1)\n'
 '            commit, path, rule, line = finding.split(":")\n'
 '            self.assertEqual(commit, "abe535809517ceb327223679f85c14b5f5b8b6d7")\n'
 '            self.assertEqual(path, "App/CouponRuntimeFixture.swift")\n'
 '            self.assertEqual(rule, "generic-api-key")\n'
 '            self.assertNotIn(f"{path}:{rule}:{line}", entries)\n'
 '            self.assertNotIn(f"{\'0\' * 40}:{path}:{rule}:{line}", entries)\n'
 '        fixture = (ROOT / "App/CouponRuntimeFixture.swift").read_text()\n'
 '        self.assertTrue(fixture.startswith("#if DEBUG"))\n'
 '        self.assertEqual(fixture.count(\'"test-7"\'), 3)\n'
 "        self.assertIn('https://coupon-runtime.example/native', fixture)\n"
 "        self.assertIn('makeTransport: { self }', fixture)\n"
 "        self.assertNotIn('URLSession', fixture)\n"
 '        self.assertFalse((ROOT / ".gitleaks.toml").exists())\n'
 '\n'
 '    def test_scan_stays_read_only_and_pinned(self):\n'
 '        workflow = (ROOT / ".github/workflows/native-ios.yml").read_text()\n'
 '        job = workflow.split("  secrets:\\n", 1)[1].split("  app-unit-tests:\\n", 1)[0]\n'
 '        self.assertIn("permissions:\\n  contents: read\\n", workflow)\n'
 '        self.assertIn("fetch-depth: 0", job)\n'
 '        self.assertIn("persist-credentials: false", job)\n'
 '        self.assertIn("gitleaks/gitleaks-action@e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e", job)\n'
 '        for key, value in [("GITLEAKS_VERSION", "8.24.3"),\n'
 '                           ("GITLEAKS_ENABLE_COMMENTS", "false"),\n'
 '                           ("GITLEAKS_ENABLE_UPLOAD_ARTIFACT", "false")]:\n'
 '            self.assertIn(f"{key}: \'{value}\'", job)\n'
 '        self.assertNotIn("continue-on-error", job)\n'
 '\n'
 '    def test_full_history_step_reuses_binary_and_fails_closed(self):\n'
 '        workflow = (ROOT / ".github/workflows/native-ios.yml").read_text()\n'
 '        step = workflow.split("      - name: Scan full checked-out branch history\\n", 1)[1]\n'
 '        step = step.split("  app-unit-tests:\\n", 1)[0]\n'
 '        self.assertIn("shell: bash", step)\n'
 '        self.assertIn("set -euo pipefail", step)\n'
 '        self.assertIn("command -v gitleaks >/dev/null", step)\n'
 '        self.assertIn("test \\"$(gitleaks version)\\" = \'8.24.3\'", step)\n'
 '        self.assertIn(\'gitleaks git --redact --exit-code=2 --log-opts="--full-history -m HEAD"\', step)\n'
 '        commands = "\\n".join(line for line in step.splitlines() if not line.lstrip().startswith("#"))\n'
 '        self.assertNotRegex(commands, r"--all|--first-parent|--no-merges|curl|wget|\\|\\|\\s*true")\n'
 '\n'
 '\n'
 'if __name__ == "__main__":\n'
 '    unittest.main()\n')

_FROZEN16_PERMISSION_READER = frozen_permission_contract
_FROZEN16_HISTORICAL_READER = historical_scan_contract
_FROZEN16_PRODUCT_READER = restore_product_source


def _encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def restore_creator_history_test(data):
    if digest(data) != CLUB_RAW_SHA256[CLUB_HISTORY_PATH]:
        raise ValueError('Unreviewed complete club creator-history input')
    first=b'\n# CLUB_HISTORY_INPUT_BEGIN\n';last=b'# CLUB_HISTORY_INPUT_END\n'
    if data.count(first)!=1 or data.count(last)!=1:
        raise ValueError('Missing or repeated club creator-history extension')
    start=data.index(first);end=data.index(last,start)+len(last)
    return _inverse_row(CLUB_HISTORY_PATH,data[:start]+data[end:],CLUB_HISTORY_INVERSE)


def _profile_module():
    import importlib.util
    path = Path(__file__).resolve().parents[1] / CLUB_PREADMISSION_PATH
    spec = importlib.util.spec_from_file_location('club_finite_profile_reader', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def current_predecessor_contract(contract, root):
    """Full club raw admission -> exact complete creator floor; never a scanner view."""
    root = Path(root)
    if digest((root / HELPER_PATH).read_bytes()) != HELPER_SHA256:
        raise ValueError('Current club reader changed')
    prefix = (root / HELPER_PATH).read_bytes().split(b'\n# Finite club layer on the exact creator/fixed45 floor. Frozen reader above retained.\n', 1)[0]
    if digest(prefix) != FROZEN16_HELPER_SHA256:
        raise ValueError('Frozen club reader was not retained exactly')
    permission_prefix = prefix.split(b'\n# Exact keyword/PBX evolution. Original eleven-file reader above is retained byte-for-byte.\n', 1)[0]
    if digest(permission_prefix) != FROZEN_PERMISSION_HELPER_SHA256:
        raise ValueError('Frozen original club11 helper not retained exactly')
    restore_creator_history_test((root / CLUB_HISTORY_PATH).read_bytes())
    support = contract['feature_batch_support_sha256']
    if support.get(HELPER_PATH) != HELPER_SHA256:
        raise ValueError('Current club helper support changed')
    for name, expected in CLUB_RAW_SHA256.items():
        if digest((root / name).read_bytes()) != expected:
            raise ValueError('Changed or mixed club raw input: ' + name)
        if name in support and support[name] != expected:
            raise ValueError('Changed club support binding: ' + name)
    if digest((root / 'tools/tests/test_gitleaks_configuration.py').read_bytes()) != CURRENT_SCANNER_SHA256:
        raise ValueError('Current scanner changed')
    for name, expected in CLUB_SOURCE_ROWS.items():
        if contract['feature_batch_sources'].pop(name, None) != expected:
            raise ValueError('Unknown club source inverse: ' + name)
        _inverse_row(name, (root / name).read_bytes(), expected)
    pbx = 'Questify.xcodeproj/project.pbxproj'
    row = contract['feature_batch_sources'][pbx]
    extension = EVOLUTION_SOURCES[pbx]
    if row['after_sha256'] != extension['after_sha256'] or row['hunks'][-len(extension['hunks']):] != extension['hunks']:
        raise ValueError('Unknown club PBX extension')
    restore_evolution_source(pbx, (root / pbx).read_bytes())
    del row['hunks'][-len(extension['hunks']):]
    row['after_sha256'] = extension['before_sha256']
    if digest(_encoded(row)) != CLUB_PBX_PRE_ROW_SHA256:
        raise ValueError('Complete preceding PBX row not restored')
    for name in CLUB_SUPPORT_PATHS:
        if name not in support:
            raise ValueError('Missing club support row: ' + name)
        del support[name]
    support[CLUB_PREADMISSION_PATH] = CLUB_PREADMISSION_SHA256
    if digest(_encoded(contract)) != CLUB_PRECONTRACT_SHA256:
        raise ValueError('Complete creator predecessor not restored')
    return contract


def _current_baseline(root):
    from tools import run138_editor_readiness as current
    root = Path(root)
    if digest((root / 'tools/run138_editor_readiness.py').read_bytes()) != current.IMPLEMENTATION_SHA256:
        raise ValueError('Current readiness reader changed')
    raw = (root / CONTRACT_PATH).read_bytes()
    current.contract(root)  # Current raw pin must succeed before historical projection.
    return _profile_module().historical_readiness_contract(raw, root)


def _validated_frozen16(root):
    baseline = _current_baseline(root)
    if digest(baseline) != BASE_CONTRACT_SHA256:
        raise ValueError('Full historical baseline changed')
    # Bind both changed club support files to their exact frozen predecessors.
    frozen_test = _inverse_row(FROZEN_TEST_PATH, (Path(root) / FROZEN_TEST_PATH).read_bytes(), FROZEN16_TEST_INVERSE)
    _inverse_row(FROZEN_TEST_PATH, frozen_test, TEST_EVOLUTION)
    restored = json.loads(baseline)
    restored['feature_batch_sources'].update(copy.deepcopy(FROZEN16_SOURCE_ROWS))
    pbx = restored['feature_batch_sources']['Questify.xcodeproj/project.pbxproj']
    extension = EVOLUTION_SOURCES['Questify.xcodeproj/project.pbxproj']
    if digest(_encoded(pbx)) != CLUB_PBX_PRE_ROW_SHA256:
        raise ValueError('Original baseline PBX row differs from creator floor')
    pbx['after_sha256'] = extension['after_sha256']
    pbx['hunks'].extend(copy.deepcopy(extension['hunks']))
    restored['feature_batch_support_sha256'].update(FROZEN16_SUPPORT_ROWS)
    raw = _encoded(restored)
    if digest(raw) != FROZEN16_CONTRACT_SHA256:
        raise ValueError('Complete frozen club16 contract not restored')
    return restored


def frozen_permission_contract(root):
    root = Path(root)
    raw = (root / CONTRACT_PATH).read_bytes()
    if digest(raw) == FROZEN_PERMISSION_CONTRACT_SHA256:
        for name, row in SOURCE_EDITS.items():
            if digest((root / name).read_bytes()) != row['after_sha256']:
                raise ValueError('Hybrid frozen permission source: ' + name)
        frozen = _FROZEN16_PERMISSION_READER(root)
        if (root / CLUB_PREADMISSION_PATH).exists() or (root / CLUB_PREADMISSION_PATH).is_symlink():
            raise ValueError('Frozen domain contains current admission')
        return frozen
    contract = _validated_frozen16(root)
    app = 'App/ClubGovernanceViews.swift'; pbx = 'Questify.xcodeproj/project.pbxproj'
    for name in EVOLUTION_SOURCES:
        restore_evolution_source(name, (root / name).read_bytes())
    if contract['feature_batch_sources'].pop(app) != EVOLUTION_SOURCES[app]:
        raise ValueError('Frozen keyword inverse changed')
    row = contract['feature_batch_sources'][pbx]
    new_hunks = EVOLUTION_SOURCES[pbx]['hunks']
    if row['hunks'][-len(new_hunks):] != new_hunks:
        raise ValueError('Frozen PBX inverse changed')
    del row['hunks'][-len(new_hunks):]
    row['after_sha256'] = EVOLUTION_SOURCES[pbx]['before_sha256']
    for name in EVOLUTION_SUPPORT:
        del contract['feature_batch_support_sha256'][name]
    contract['feature_batch_support_sha256'][FROZEN_TEST_PATH] = TEST_EVOLUTION['before_sha256']
    contract['feature_batch_support_sha256'][HELPER_PATH] = FROZEN_PERMISSION_HELPER_SHA256
    raw = _encoded(contract)
    if digest(raw) != FROZEN_PERMISSION_CONTRACT_SHA256:
        raise ValueError('Complete frozen club11 contract not restored')
    return raw.decode()


def _original_scanner(raw):
    if digest(raw) != CURRENT_SCANNER_SHA256:
        raise ValueError('Unknown current scanner input')
    text = raw.decode()
    for before, after in reversed(_profile_module().SCANNER_READER_HUNKS):
        if text.count(after) != 1:
            raise ValueError('Missing or repeated original scanner inverse')
        text = text.replace(after, before, 1)
    original = text.encode()
    if digest(original) != SOURCE_EDITS['tools/tests/test_gitleaks_configuration.py']['before_sha256']:
        raise ValueError('Original complete scanner not restored')
    return original


def permission_product_bytes(root, relative):
    raw = (Path(root) / relative).read_bytes()
    if relative != 'tools/tests/test_gitleaks_configuration.py':
        return raw
    frozen_permission_contract(root)
    if digest(raw) != CURRENT_SCANNER_SHA256:
        raise ValueError('Unknown current scanner')
    frozen = FROZEN_SCANNER_BYTES.encode()
    # Both adapters restore the identical original scanner with every assertion.
    original = _original_scanner(raw)
    if original != _FROZEN16_PRODUCT_READER(relative, frozen):
        raise ValueError('Historical scanner adapter predecessors differ')
    return frozen


def restore_product_source(relative, raw):
    if relative == 'tools/tests/test_gitleaks_configuration.py' and digest(raw) == CURRENT_SCANNER_SHA256:
        return _original_scanner(raw)
    return _FROZEN16_PRODUCT_READER(relative, raw)


def historical_scan_contract(root):
    root = Path(root)
    if digest((root / CONTRACT_PATH).read_bytes()) == BASE_CONTRACT_SHA256:
        baseline = _FROZEN16_HISTORICAL_READER(root)
        if (root / CLUB_PREADMISSION_PATH).exists() or (root / CLUB_PREADMISSION_PATH).is_symlink():
            raise ValueError('Baseline domain contains current admission')
        return baseline
    frozen = json.loads(frozen_permission_contract(root))
    for name in SOURCE_EDITS:
        del frozen['feature_batch_sources'][name]
    for name in ADDED_SUPPORT:
        del frozen['feature_batch_support_sha256'][name]
    baseline = _encoded(frozen)
    if digest(baseline) != BASE_CONTRACT_SHA256:
        raise ValueError('Complete original club baseline not restored')
    return baseline.decode()
