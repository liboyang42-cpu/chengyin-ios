"""Public raw-source read-failure admission; no Swift/backend execution implied."""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
DISCOVERY_HELPER_FINGERPRINT = 'c88ad4a2fb94afa7bce846935ac8a81fd3c9a598a7e2746f90dd0b8aaa949134'

def load(relative, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

raw = load('tools/check_profile_read_failure_contract.py', 'profile_read_failure_raw')
# Ordinary unittest discovery must execute the unchanged thirteen raw cases.
ProfileReadFailureContracts = raw.ProfileReadFailureContracts

def digest(value):
    return hashlib.sha256(value).hexdigest()


ORIGINAL_READINESS_SHA256 = '11cc2e20ce328dcba2fcfbcb4425bf581908038c71d4f4c7eee15c1bbab1b2b6'
READINESS_PATH = 'tools/run138_editor_readiness_contract.json'
SCANNER_PATH = 'tools/tests/test_gitleaks_configuration.py'

# Combined admission authenticates current bytes before either historical layer.
COMBINED_ADMISSION_FINGERPRINT = '09273a52c1e9eeccfe29122c23663e7c1131e12657997b620893a16a4aa8671f'
PROFILE_R2_CONTRACT_SHA256 = '3538a4526a2f42c07a8837ddb2cd12e4598ecf0d97459b36e4fcd61fb7e07efb'
PROFILE_R2_ADMISSION_SHA256 = '81041b1c2ba2e328284555841f3b14b0e3630ed78f1190f701a86016ab558d84'
COMBINED_ADMISSION_PATH = 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py'
COMBINED_RAW_SHA256 = {'App/MerchantOperationsEditor.swift': '3656f645fdac72a57fc05caeafc71a61bdcb1728d7c5da0196ce7d0fa184fbbe',
 'Core/ProfileEditCoordinator.swift': 'bbd462eed41321ab249fda4e2f80e48aad51942cc6ce195bbd45b7e52b1e1b67',
 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift': '8f6e488cbdb80d6c62ebd1aa62c280aadbd9c2b9e69b0f62dd17c1ad435a703e',
 'Tests/ContractChecks/test_merchant_decor_tag_picker.py': 'ce4a480162243e0e8b497fcc13fe6e08c8d28f00c3574e956f4ae4c6260ff1b5',
 'Tests/ContractChecks/test_profile_avatar.py': '031747f2374ef01e935753b51be7859c75f3f5861a83037cd935089ed006a1db',
 'Tests/ContractChecks/test_profile_reload_discard.py': '044ef04942dd76592917397f686cbe6c7d50bd199ceb0776806af965da78fada',
 'Tests/CoreTests/MerchantDecorTagDraftTests.swift': '407e2da4496c3d3a81a1017a84220a41636631c3dfa6867805d510412e0cc3af',
 'Tests/CoreTests/ProfileEditTests.swift': '6319234ba77c43afec858692bc9ff00308be774b58ea585069a7b3dc90ce654c',
 'docs/merchant-decor-tag-picker/implementation.md': '1d320a30163c369a222815a565bb1bc8ab4675b7905de465a205e50a95297539',
 'docs/profile-read-failure-recovery.md': 'b9ec88b1988042cd4d28a39e4640e6980fc1d02d2a7f248ab564a05e25b372fa',
 'tools/check_profile_read_failure_contract.py': 'e492facdded0e76615721d90081b912738ba490e503aab61a7ed549a6b2a4b8a',
 'tools/tests/test_gitleaks_configuration.py': 'a5f5cd4f8670fb10405ab73fba1ac15700ace46a0c8dd4e8321e29e5da90cb30'}
MERCHANT_SOURCE_PATH = 'App/MerchantOperationsEditor.swift'
MERCHANT_PREIMAGE_SHA256 = '3e1a134db3355e63c068fcb4ff5dbb5abc7d7ac00488c6548d9a054339e80e1f'
MERCHANT_SUPPORT_PREIMAGES = {'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift': 'caaae8dab10e8a9d69500cf1243d1b31311f0b8d4eda568a2dfc58c7ab10d0cc',
 'Tests/ContractChecks/test_merchant_decor_tag_picker.py': '491182e97a8e53e1b3372c130d1a1f7857c10804302578a624c706d473e2fec7',
 'Tests/CoreTests/MerchantDecorTagDraftTests.swift': '5e90fd3657fd322477dc3c28347fb0efc3e33553ae39ef4bf990308bf445de86',
 'docs/merchant-decor-tag-picker/implementation.md': '5d7d4a190a5b0146433d7e7d077789ce99fad2669f0a44798a067e7f1702b141'}
MERCHANT_TAG_HUNK = {'after': '            Section("merchant.operations.tags") {\n'
          '                ForEach(Array(value.tags.enumerated()), id: \\.offset) { index, tag in\n'
          '                    Text(verbatim: tag)\n'
          '                        .accessibilityIdentifier("merchant.operations.tags.value." + '
          'String(index))\n'
          '                }\n'
          '                MerchantDecorTagEditor(model: model)\n'
          '            }\n',
 'before': '            Section("merchant.operations.tags") {\n'
           '                TextField("merchant.operations.tags", text: Binding(get: { '
           'currentDecor?.tags.joined(separator: ";") ?? "" }, set: { raw in\n'
           '                    guard var value = currentDecor else { return }; value.tags = '
           'raw.components(separatedBy: ";").map { $0.trimmingCharacters(in: '
           '.whitespacesAndNewlines) }.filter { !$0.isEmpty }; model.edit(.decor(value))\n'
           '                }), axis: '
           '.vertical).accessibilityIdentifier("merchant.operations.field.tags")\n'
           '                '
           'Text("merchant.operations.tagsHint").font(.footnote).foregroundStyle(.secondary)\n'
           '                MerchantDecorTagEditor(model: model)\n'
           '            }\n'}

# The compiler-only repair is a new finite layer over the already reviewed
# complete profile/merchant contract. It never substitutes historical products.
COMPILE_REPAIR_PATH = 'Tests/CoreTests/ProjectCityStoryNodeRemovalTests.swift'
COMPILE_REPAIR_ROW = {'before_sha256': 'c0d731ccb927b9bad2ae07f65fac52ac99f924e121c66bede81ee5b411742bba', 'after_sha256': 'bad6293bda4a08e10687686625969954a6b906f9b8c618c8462579840d343a3c', 'hunks': [{'before': '        d=draft();d.chapters[0].blocks?[2].id=d.chapters[0].blocks![0].id;XCTAssertThrowsError(try remove(d))\n', 'after': '        d=draft();let duplicateBlockID=d.chapters[0].blocks![0].id;d.chapters[0].blocks?[2].id=duplicateBlockID;XCTAssertThrowsError(try remove(d))\n'}]}
COMBINED_PRECOMPILE_SHA256 = '58ff3d8f33a15cb17ff8ac753ae39799a68434a2c742e4630abe9c0b24154f1b'
COMBINED_PRECOMPILE_ADMISSION_SHA256 = '7da17371272409260ed364f7c1aed5d2777380039fd8a9354b3b084266d25b30'


def _compile_repair_combined_contract(contract, root=ROOT):
    # Current complete module/raw group checks must have run before this layer.
    row = contract['feature_batch_sources'].get(COMPILE_REPAIR_PATH)
    if row != COMPILE_REPAIR_ROW:
        raise ValueError('Unknown compiler repair inverse')
    support = contract['feature_batch_support_sha256']
    value = (Path(root) / COMPILE_REPAIR_PATH).read_bytes()
    if digest(value) != row['after_sha256'] or support.get(COMPILE_REPAIR_PATH) != row['after_sha256']:
        raise ValueError('Changed compiler repair current source/support')
    for hunk in reversed(row['hunks']):
        after = hunk['after'].encode(); before = hunk['before'].encode()
        if value.count(after) != 1:
            raise ValueError('Missing or repeated compiler repair hunk')
        value = value.replace(after, before, 1)
    if digest(value) != row['before_sha256']:
        raise ValueError('Compiler repair did not restore complete original test')
    del contract['feature_batch_sources'][COMPILE_REPAIR_PATH]
    support[COMPILE_REPAIR_PATH] = row['before_sha256']
    support[COMBINED_ADMISSION_PATH] = COMBINED_PRECOMPILE_ADMISSION_SHA256
    restored = (json.dumps(contract, indent=2, ensure_ascii=False)+'\n').encode()
    if digest(restored) != COMBINED_PRECOMPILE_SHA256:
        raise ValueError('Complete reviewed combined contract not restored')
    return contract


# Static observability adds only a current-byte support layer. Restore the
# complete published R5 contract before the unchanged compiler/product chain.
STATIC_OBSERVABILITY_PRECONTRACT_SHA256 = 'b5dff5b209ce495bb46075dcc514a20ebd2e4561a9d1ea3aadb02b02f8d393c9'
STATIC_OBSERVABILITY_PREADMISSION_SHA256 = 'fa88459ba1d948253d825335db9bf8391cc59aa2dac2935019eabfcab23b25a0'
STATIC_OBSERVABILITY_SUPPORT = {'tools/run_static_checks.py': {'before_sha256': '5765354aae29e6b044cd45bc6145c3a35b6420579295631a5c74bca4959a1ed4', 'after_sha256': 'a681d224bfbef5372678a11625fa6330da097b470592e0572c1afd88f77a0210'}, 'tools/tests/test_native_static_checks.py': {'before_sha256': 'f1a980c56b45f543465417d3a2d884a2dc1fc624eaeb6625d84ace7f88735f0c', 'after_sha256': 'b471892d1834b973424f1d74d4e00fb12fe37a8df8689f063441813d265eee3a'}}


def _static_observability_contract(contract, root=ROOT):
    # The complete current runner/module/raw group is authenticated by the
    # caller first. New raw bytes and the central support must agree exactly;
    # before hashes are separately bound by the complete R5 contract digest.
    followon = contract['followon_support_sha256']
    for relative, row in STATIC_OBSERVABILITY_SUPPORT.items():
        if (digest((Path(root) / relative).read_bytes()) != row['after_sha256']
                or followon.get(relative) != row['after_sha256']):
            raise ValueError('Changed current static observability source/support: ' + relative)
        followon[relative] = row['before_sha256']
    contract['feature_batch_support_sha256'][COMBINED_ADMISSION_PATH] = STATIC_OBSERVABILITY_PREADMISSION_SHA256
    restored = (json.dumps(contract, indent=2, ensure_ascii=False)+'\n').encode()
    if digest(restored) != STATIC_OBSERVABILITY_PRECONTRACT_SHA256:
        raise ValueError('Complete published R5 contract not restored')
    return contract


# The reviewed crop compiler repair is a finite layer above static visibility.
# Authenticate current crop bytes, then restore the complete frozen static group.
CROP_COMPILE_REPAIR_PATH = 'App/ProjectNodeImageCrop.swift'
CROP_COMPILE_REPAIR_ROW = {'before_sha256': 'f9997b618a2d850070052092f2e83ef8b81b7ee1bcadba1cb7e7b846e7ab964a', 'after_sha256': '47901a84bfc8ffa2f69dca618ab4de6eb7a151f7cc20fdebd4cb79425bcdb894', 'hunks': [{'before': '    @State private var horizontal=0.5,vertical=0.5,zoom=1.0\n', 'after': '    @State private var horizontal=0.5\n    @State private var vertical=0.5\n    @State private var zoom=1.0\n'}]}
CROP_PRESTATIC_CONTRACT_SHA256 = 'fe46945c81c4f224e514839b4de4d3a7bdeb9602d8a398bafba360173b2138fd'
CROP_PRESTATIC_ADMISSION_SHA256 = '460c0005da72cab8fabc467b95a9e36e1b2b4570854b9652c8f5c13154977d43'


def _crop_static_contract(contract, root=ROOT):
    row = contract['feature_batch_sources'].get(CROP_COMPILE_REPAIR_PATH)
    if row != CROP_COMPILE_REPAIR_ROW:
        raise ValueError('Unknown crop compiler repair inverse')
    support = contract['feature_batch_support_sha256']
    value = (Path(root) / CROP_COMPILE_REPAIR_PATH).read_bytes()
    if digest(value) != row['after_sha256'] or support.get(CROP_COMPILE_REPAIR_PATH) != row['after_sha256']:
        raise ValueError('Changed crop compiler repair current source/support')
    for hunk in reversed(row['hunks']):
        after = hunk['after'].encode(); before = hunk['before'].encode()
        if value.count(after) != 1:
            raise ValueError('Missing or repeated crop compiler repair hunk')
        value = value.replace(after, before, 1)
    if digest(value) != row['before_sha256']:
        raise ValueError('Complete original crop source not restored')
    del contract['feature_batch_sources'][CROP_COMPILE_REPAIR_PATH]
    support[CROP_COMPILE_REPAIR_PATH] = row['before_sha256']
    support[COMBINED_ADMISSION_PATH] = CROP_PRESTATIC_ADMISSION_SHA256
    restored = (json.dumps(contract, indent=2, ensure_ascii=False)+'\n').encode()
    if digest(restored) != CROP_PRESTATIC_CONTRACT_SHA256:
        raise ValueError('Complete frozen static contract not restored')
    return contract


# Finite creator-state layer over the exact reviewed fixed45 R3 source contract.
CREATOR_STATE_PRECONTRACT_SHA256 = '519006c2f95083423c186d289b8b2a1b6ef9c6327b5fd461718548b8e0fc40ce'
CREATOR_STATE_PREADMISSION_SHA256 = 'd1d7ad397a76f668f47bcc4243c23a397d560e90220b01bd99dd91a85bfe3163'
CREATOR_STATE_RAW_SHA256 = {'App/TemplateAuthoringMineView.swift': '070653140719b1dd37b8cf5b811c0a6cfef9c66eff13fa06d9a78b6634a4c38f',
 'Core/TemplateAuthoringShelf.swift': 'a9261782a98016cf474bbd9a2b2035fd6fbba6bf5ac9bb5682f85c95f4bbb13a',
 'Resources/Localizable.xcstrings': '8f552d5a3f34a86c19a370c411a08669dfb4440a15f3b3037cd635595b4ff995',
 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift': '7311d093a69f2291048f9f08110ef1425cd884ede1781abb28c037c1b50a2673',
 'Tests/ContractChecks/test_template_shelf_read_bridge.py': 'c6739456a84e353060b42225dae9b8c2a472d8f080bb831ccd7bb74c39afaec8',
 'Tests/ContractChecks/test_template_shelf_state_projection.py': '92a11a1874c3c442ff7bf76d62ae4e8331e0d7d589f6d55d919e9a4130180dc4',
 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift': '760c57eef41df4f73d89ea5143fd629c68d82ffe1c290a203006371c684e8ee6',
 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift': 'b2b199d73b7045d4c3de9ce7bc0ea41b10bfc233c6b9c180438fd415d5c99b87'}
CREATOR_STATE_CATALOG = 'Resources/Localizable.xcstrings'
CREATOR_STATE_OLD_CATALOG_SHA256 = '6e9a854e14c29ad90a8b4ed88735e5641d15efc53ca810fb49dc366d3509910a'
CREATOR_STATE_BLOCK_SHA256 = 'a45aae9b4db8fa346be67c9cf4f6b6ca4d8ffe54748cc466558d0031f7a56f8d'


# Exact compiler-only merchant leaf layer over the frozen creator13 contract.
MERCHANT_BUSINESS_COMPILE_PATH = 'App/MerchantBusinessEditor.swift'
MERCHANT_BUSINESS_COMPILE_HUNK = {'after': '            .onAppear { initializeEditorStateOnAppear() }\n'
          '        }\n'
          '    }\n'
          '    private func initializeEditorStateOnAppear() {\n'
          '        if case .aftercare(let row) = context.kind {\n'
          '            let allowedDecisions: [String]? = try? '
          'row.fields.mbStrings("allowedDecisions")\n'
          '            if let first = allowedDecisions?.first,\n'
          '               let value = MerchantAftercareDecision(rawValue: first) { decision = '
          'value }\n'
          '        }\n'
          '        if case .role(let row) = context.kind { role = row.fields.mbText("roleCode") ?? '
          '"" }\n'
          '        initializeReviewContent()\n'
          '    }\n'
          '    private func initializeReviewContent() {\n',
 'before': '            .onAppear {\n'
           '                if case .aftercare(let row) = context.kind, let first = try? '
           'row.fields.mbStrings("allowedDecisions").first, let value = '
           'MerchantAftercareDecision(rawValue: first) { decision = value }\n'
           '                if case .role(let row) = context.kind { role = '
           'row.fields.mbText("roleCode") ?? "" }\n'
           '                initializeReviewContent()\n'
           '            }\n'
           '        }\n'
           '    }\n'
           '    private func initializeReviewContent() {\n'}
MERCHANT_BUSINESS_PRE_SOURCE_SHA256 = '37e4fb670565770a72f1c1ad0e1c5b2ac4affc35669514597c80790d4e8f394d'
MERCHANT_BUSINESS_POST_SOURCE_SHA256 = '13ff93a1d1608d0fc10cbbb1e2aa31b6f7b5496ea37553e052d147ab6611aff0'
MERCHANT_BUSINESS_PRE_CONTRACT_SHA256 = '427074d1dc2ffa0c530cec669a0d490934fa266de7067b28de2d4d5fc0506e4a'
MERCHANT_BUSINESS_PRE_ADMISSION_SHA256 = '96232fe4bb8fa3fa376d1542b662508112521e253ae4f03f6ff33be5927a5e3c'
MERCHANT_BUSINESS_CURRENT_RAW_SHA256 = {'App/MerchantBusinessEditor.swift': '13ff93a1d1608d0fc10cbbb1e2aa31b6f7b5496ea37553e052d147ab6611aff0',
 'App/TemplateAuthoringMineView.swift': '070653140719b1dd37b8cf5b811c0a6cfef9c66eff13fa06d9a78b6634a4c38f',
 'Core/TemplateAuthoringShelf.swift': 'a9261782a98016cf474bbd9a2b2035fd6fbba6bf5ac9bb5682f85c95f4bbb13a',
 'Resources/Localizable.xcstrings': '8f552d5a3f34a86c19a370c411a08669dfb4440a15f3b3037cd635595b4ff995',
 'Tests/ContractChecks/test_merchant_review_draft_return.py': 'e5b7c6ce7d66037ed49dba6b32b59fcf213c57e24b6f8694285e7d612575d777',
 'Tests/ContractChecks/test_template_shelf_state_projection.py': '92a11a1874c3c442ff7bf76d62ae4e8331e0d7d589f6d55d919e9a4130180dc4',
 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift': 'b2b199d73b7045d4c3de9ce7bc0ea41b10bfc233c6b9c180438fd415d5c99b87',
 'tools/tests/creator_shelf_refresh_history.py': '55632e1d0235628b55478a6b50a5e5d369bf2c54d73f4d09ec33becf84b6d7e5',
 'tools/tests/creator_shelf_state_history.py': '63d498f92184bfdf2349849c683347adc5766e73878cc1f5e86790b68799d2e3',
 'tools/tests/test_creator_pending_synthetic_storage_history.py': '8d4b8e0bf04a7ce28622b416956af3628348bf3f86d5af5630fe04bb07e7e739',
 'tools/tests/test_creator_shelf_refresh_history.py': '26b98d87f9c465dd2e6cefbc31734e5925c13a86003a9e695a09f4b83ad36061',
 'tools/tests/test_creator_shelf_state_history.py': '28e14028204276d0277afb29064d0f2ad65bcb05e57aadf226b63d61e606c924'}


MERCHANT_BUSINESS_READER_PATH = 'Tests/ContractChecks/test_merchant_review_draft_return.py'
MERCHANT_BUSINESS_READER_PRE_SHA256 = 'e9f31299585059f9ce7f6e23002bd815471f7ba85e83707fe9fd571934dd1968'
MERCHANT_BUSINESS_READER_INVERSE_HUNKS = [('            lines=compiler_historical_read(path).decode().splitlines(keepends=True)\n',
  '            lines=read(path).decode().splitlines(keepends=True)\n'),
 ('\n'
  '# Compiler repair affects only this old fixed-offset historical input.\n'
  '# All other current-source tests continue to use read() above.\n'
  'def compiler_historical_read(path):\n'
  '    from Tests.ContractChecks import test_profile_read_failure_remote_admission as admission\n'
  "    data=(ROOT/'tools/run138_editor_readiness_contract.json').read_bytes()\n"
  '    admission._combined_profile_contract(data,ROOT)\n'
  '    value=(ROOT/path).read_bytes()\n'
  '    if path==admission.MERCHANT_BUSINESS_COMPILE_PATH:\n'
  '        hunk=admission.MERCHANT_BUSINESS_COMPILE_HUNK\n'
  "        after=hunk['after'].encode();before=hunk['before'].encode()\n"
  "        if value.count(after)!=1:raise ValueError('Missing unique merchant compiler span')\n"
  '        value=value.replace(after,before,1)\n'
  '        if hashlib.sha256(value).hexdigest()!=admission.MERCHANT_BUSINESS_PRE_SOURCE_SHA256:\n'
  "            raise ValueError('Unknown complete merchant compiler predecessor')\n"
  '    return value\n'
  '\n',
  '')]


CLUB_MERCHANT_PRECONTRACT_SHA256 = 'eb80d6bb10463819a30d41530cc00c909d94f6f79fd1108401b22031369b2053'
CLUB_MERCHANT_PREADMISSION_SHA256 = 'df08d6c30bcebd89e901e5ae3a5920b22142dbd8b2cf4a7dfa4c765be5917271'

def _club_bound_merchant_input(contract, root):
    # Only the actual authenticated club set or its exact reviewed merchant floor.
    current=(root/READINESS_PATH).read_bytes()
    current_contract=json.loads(current)
    if (json.dumps(current_contract,indent=2,ensure_ascii=False)+'\n').encode()!=current:
        raise ValueError('Noncanonical complete club current contract')
    module=(root/COMBINED_ADMISSION_PATH).read_bytes()
    slot=rb"^COMBINED_ADMISSION_FINGERPRINT = '[0-9a-f]{64}'$"
    normalized=re.sub(slot,b"COMBINED_ADMISSION_FINGERPRINT = '<SELF>'",module,flags=re.MULTILINE)
    if digest(normalized)!=COMBINED_ADMISSION_FINGERPRINT or current_contract['feature_batch_support_sha256'].get(COMBINED_ADMISSION_PATH)!=digest(module):
        raise ValueError('Changed complete club current admission')
    prior=_club_directory_contract(json.loads(current),root)
    value=(json.dumps(contract,indent=2,ensure_ascii=False)+'\n').encode()
    encoded=(json.dumps(prior,indent=2,ensure_ascii=False)+'\n').encode()
    if value not in (current,encoded):
        raise ValueError('Unknown mixed club/merchant input floor')
    return prior,current


def _merchant_business_compile_contract(contract, root=ROOT):
    from Tests.ContractChecks.test_category_roam_registration import profile_contract_inputs
    contract, root = profile_contract_inputs(contract, root, 'merchant')
    root=Path(root)
    contract,current_encoded=_club_bound_merchant_input(contract,root)
    encoded=(json.dumps(contract,indent=2,ensure_ascii=False)+'\n').encode()
    if digest(encoded)!=CLUB_MERCHANT_PRECONTRACT_SHA256:raise ValueError('Unknown current merchant compile contract bytes')
    runner=(root/'tools/run138_editor_readiness.py').read_bytes()
    pins=re.findall(rb"^CONTRACT_SHA256 = '([0-9a-f]{64})'$",runner,re.MULTILINE)
    if len(pins)!=1 or pins[0].decode()!=digest(current_encoded):raise ValueError('Changed merchant compile current pin')
    if digest(runner.replace(pins[0],ORIGINAL_READINESS_SHA256.encode(),1))!='cafa9858b24a18f3827ce5678701b1e32cf533e66d51dc43788b15a74d60a79f':raise ValueError('Changed merchant compile runner')
    module=(root/COMBINED_ADMISSION_PATH).read_bytes()
    slot=rb"^COMBINED_ADMISSION_FINGERPRINT = '[0-9a-f]{64}'$"
    normalized=re.sub(slot,b"COMBINED_ADMISSION_FINGERPRINT = '<SELF>'",module,flags=re.MULTILINE)
    support=contract['feature_batch_support_sha256']
    if digest(normalized)!=COMBINED_ADMISSION_FINGERPRINT or support.get(COMBINED_ADMISSION_PATH)!=CLUB_MERCHANT_PREADMISSION_SHA256:raise ValueError('Changed merchant compile admission')
    for name,expected in MERCHANT_BUSINESS_CURRENT_RAW_SHA256.items():
        value=(root/name).read_bytes()
        if name=='tools/tests/test_creator_shelf_state_history.py':
            from tools import club_customer_directory_admission as club
            value=club.restore_creator_history_test(value)
        if digest(value)!=expected:raise ValueError('Changed or mixed merchant compile group: '+name)
    reader=(root/MERCHANT_BUSINESS_READER_PATH).read_bytes()
    for after,before in MERCHANT_BUSINESS_READER_INVERSE_HUNKS:
        if reader.count(after.encode())!=1:raise ValueError('Unknown merchant historical reader adaptation')
        reader=reader.replace(after.encode(),before.encode(),1)
    if digest(reader)!=MERCHANT_BUSINESS_READER_PRE_SHA256:raise ValueError('Complete old merchant reader not restored')
    if support.get(MERCHANT_BUSINESS_READER_PATH)!=MERCHANT_BUSINESS_CURRENT_RAW_SHA256[MERCHANT_BUSINESS_READER_PATH]:raise ValueError('Changed merchant reader support')
    support[MERCHANT_BUSINESS_READER_PATH]=MERCHANT_BUSINESS_READER_PRE_SHA256
    row=contract['feature_batch_sources'][MERCHANT_BUSINESS_COMPILE_PATH]
    if row['after_sha256']!=MERCHANT_BUSINESS_POST_SOURCE_SHA256 or row['hunks'][-1]!=MERCHANT_BUSINESS_COMPILE_HUNK:raise ValueError('Unknown merchant compiler inverse')
    value=(root/MERCHANT_BUSINESS_COMPILE_PATH).read_bytes()
    after=MERCHANT_BUSINESS_COMPILE_HUNK['after'].encode();before=MERCHANT_BUSINESS_COMPILE_HUNK['before'].encode()
    if value.count(after)!=1 or digest(value.replace(after,before,1))!=MERCHANT_BUSINESS_PRE_SOURCE_SHA256:raise ValueError('Merchant compiler predecessor not restored')
    row['hunks'].pop();row['after_sha256']=MERCHANT_BUSINESS_PRE_SOURCE_SHA256
    support[COMBINED_ADMISSION_PATH]=MERCHANT_BUSINESS_PRE_ADMISSION_SHA256
    restored=(json.dumps(contract,indent=2,ensure_ascii=False)+'\n').encode()
    if digest(restored)!=MERCHANT_BUSINESS_PRE_CONTRACT_SHA256:raise ValueError('Complete creator13 floor not restored')
    return contract


CLUB_DIRECTORY_HELPER_SHA256 = '80b6fb95961ef598ea66aa02e0081938b5df2ae7860a3e3fad76e5c0fa0a2297'

def _club_directory_contract(contract, root=ROOT):
    from Tests.ContractChecks.test_category_roam_registration import profile_contract_inputs
    contract, root = profile_contract_inputs(contract, root, 'club')
    helper = Path(root) / 'tools/club_customer_directory_admission.py'
    if digest(helper.read_bytes()) != CLUB_DIRECTORY_HELPER_SHA256:
        raise ValueError('Unreviewed complete club helper input')
    from tools import club_customer_directory_admission as club
    return club.current_predecessor_contract(contract, root)


def _creator_state_contract(contract, root=ROOT):
    from Tests.ContractChecks.test_category_roam_registration import profile_contract_inputs
    contract, root = profile_contract_inputs(contract, root, 'creator')
    # The current full contract, runner and admission module are authenticated by
    # the caller before entering this historical-only layer. Never scan this view.
    root = Path(root)
    for name, expected in CREATOR_STATE_RAW_SHA256.items():
        if digest((root/name).read_bytes()) != expected:
            raise ValueError('Changed or mixed creator state input: ' + name)
    support = contract['feature_batch_support_sha256']
    if support.get(CREATOR_STATE_CATALOG) != CREATOR_STATE_RAW_SHA256[CREATOR_STATE_CATALOG]:
        raise ValueError('Unknown creator catalog support binding')
    value = (root/CREATOR_STATE_CATALOG).read_bytes()
    first = b'    "templateShelfState.market.feedback": {'
    last = b'    "templateStory.derivedSummary": {'
    if value.count(first) != 1 or value.count(last) != 1:
        raise ValueError('Missing or repeated creator catalog insertion boundary')
    start = value.index(first); end = value.index(last, start)
    block = value[start:end]
    if len(block) != 5730 or digest(block) != CREATOR_STATE_BLOCK_SHA256:
        raise ValueError('Unreviewed creator catalog insertion')
    if digest(value[:start]+value[end:]) != CREATOR_STATE_OLD_CATALOG_SHA256:
        raise ValueError('Creator catalog predecessor not restored exactly')
    support[CREATOR_STATE_CATALOG] = CREATOR_STATE_OLD_CATALOG_SHA256
    support[COMBINED_ADMISSION_PATH] = CREATOR_STATE_PREADMISSION_SHA256
    restored = (json.dumps(contract, indent=2, ensure_ascii=False)+'\n').encode()
    if digest(restored) != CREATOR_STATE_PRECONTRACT_SHA256:
        raise ValueError('Complete reviewed fixed45 R3 contract not restored')
    return contract


def _combined_profile_contract(data, root=ROOT):
    try:
        return _combined_profile_contract_checked(data, root)
    except (OSError, KeyError, TypeError, IndexError, UnicodeError) as error:
        raise ValueError('Incomplete or malformed combined admission input') from error


def _combined_profile_contract_checked(data, root=ROOT):
    from Tests.ContractChecks.test_category_roam_registration import profile_history_inputs
    data, root = profile_history_inputs(data, root, 'combined')
    """Exact combined current -> reviewed profile R2 contract, never current admission."""
    root = Path(root)
    runner = (root / 'tools/run138_editor_readiness.py').read_bytes()
    pins = re.findall(rb"^CONTRACT_SHA256 = '([0-9a-f]{64})'$", runner, re.MULTILINE)
    if len(pins) != 1 or digest(data) != pins[0].decode('ascii'):
        raise ValueError('Unknown complete current combined contract')
    # Runner changes only its pin; unrelated code changes cannot grant admission.
    old_runner = runner.replace(pins[0], ORIGINAL_READINESS_SHA256.encode(), 1)
    if digest(old_runner) != 'cafa9858b24a18f3827ce5678701b1e32cf533e66d51dc43788b15a74d60a79f':
        raise ValueError('Changed combined readiness runner')
    contract = json.loads(data)
    if (json.dumps(contract, indent=2, ensure_ascii=False)+'\n').encode() != data:
        raise ValueError('Noncanonical combined contract bytes')
    support = contract['feature_batch_support_sha256']
    module = (root / COMBINED_ADMISSION_PATH).read_bytes()
    slot = rb"^COMBINED_ADMISSION_FINGERPRINT = '[0-9a-f]{64}'$"
    slots = re.findall(rb"^COMBINED_ADMISSION_FINGERPRINT = '([0-9a-f]{64})'$", module, re.MULTILINE)
    if len(slots) != 1 or slots[0].decode('ascii') != COMBINED_ADMISSION_FINGERPRINT:
        raise ValueError('Changed combined admission identity slot')
    fingerprint = re.sub(slot, b"COMBINED_ADMISSION_FINGERPRINT = '<SELF>'", module, flags=re.MULTILINE)
    if digest(fingerprint) != COMBINED_ADMISSION_FINGERPRINT or digest(module) != support[COMBINED_ADMISSION_PATH]:
        raise ValueError('Changed combined admission source')
    for name, expected in COMBINED_RAW_SHA256.items():
        if digest((root/name).read_bytes()) != expected:
            raise ValueError('Changed combined raw input: ' + name)
        if name in support and support[name] != expected:
            raise ValueError('Changed combined support binding: ' + name)
    contract = _merchant_business_compile_contract(contract, root)
    contract = _creator_state_contract(contract, root)
    contract = _crop_static_contract(contract, root)
    contract = _static_observability_contract(contract, root)
    contract = _compile_repair_combined_contract(contract, root)
    support = contract['feature_batch_support_sha256']
    row = contract['feature_batch_sources'][MERCHANT_SOURCE_PATH]
    if row['after_sha256'] != COMBINED_RAW_SHA256[MERCHANT_SOURCE_PATH] or row['hunks'][-1] != MERCHANT_TAG_HUNK:
        raise ValueError('Unknown combined merchant inverse')
    value = (root / MERCHANT_SOURCE_PATH).read_bytes()
    after = MERCHANT_TAG_HUNK['after'].encode(); before = MERCHANT_TAG_HUNK['before'].encode()
    if value.count(after) != 1 or digest(value.replace(after,before,1)) != MERCHANT_PREIMAGE_SHA256:
        raise ValueError('Merchant source predecessor not restored exactly')
    row['hunks'].pop()
    row['after_sha256'] = MERCHANT_PREIMAGE_SHA256
    support.update(MERCHANT_SUPPORT_PREIMAGES)
    support[COMBINED_ADMISSION_PATH] = PROFILE_R2_ADMISSION_SHA256
    restored = (json.dumps(contract, indent=2, ensure_ascii=False)+'\n').encode()
    if digest(restored) != PROFILE_R2_CONTRACT_SHA256:
        raise ValueError('Complete reviewed profile R2 contract not restored')
    return restored

def historical_readiness_contract(data, root=ROOT):
    from Tests.ContractChecks.test_category_roam_registration import profile_history_inputs
    data, root = profile_history_inputs(data, root, 'history')
    """Historical line reader only; the current central gate still rejects old bytes."""
    if digest(data) == ORIGINAL_READINESS_SHA256:
        return data
    data = _combined_profile_contract(data, root)
    contract = json.loads(data)
    row = contract['feature_batch_sources'][raw.CORE]
    if len(row['hunks']) != 9 or row['after_sha256'] != raw.CURRENT_COORDINATOR_SHA256:
        raise ValueError('Not the bounded read-error contract increment')
    value = (Path(root)/raw.CORE).read_text()
    for hunk in reversed(row['hunks'][5:]):
        if value.count(hunk['after']) != 1:
            raise ValueError('Missing or repeated read-error inverse span')
        value = value.replace(hunk['after'], hunk['before'], 1)
    if digest(value.encode()) != raw.OLD_COORDINATOR_SHA256:
        raise ValueError('Original profile source not restored')
    row['after_sha256'] = raw.OLD_COORDINATOR_SHA256
    row['hunks'] = row['hunks'][:5]
    support = contract['feature_batch_support_sha256']
    support['Tests/ContractChecks/test_profile_avatar.py'] = '3be8c14b0d722350f6dde13542824f334e3a3bf66e3e4c687a536deeb51e81f0'
    support['Tests/ContractChecks/test_profile_reload_discard.py'] = '3da1b513c2fdcbafcfe98c6ddc9172cc453caca11954d140c51ed78c2f41da25'
    for path in ['tools/check_profile_read_failure_contract.py', 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py', raw.TESTS, SCANNER_PATH]:
        del support[path]
    original = (json.dumps(contract, indent=2, ensure_ascii=False)+'\n').encode()
    if digest(original) != ORIGINAL_READINESS_SHA256:
        raise ValueError('Complete original readiness contract not restored')
    return original

class ProfileReadFailureRemoteAdmission(unittest.TestCase):
    def test_public_discovery_includes_all_thirteen_raw_checks(self):
        self.assertEqual(unittest.defaultTestLoader.loadTestsFromTestCase(ProfileReadFailureContracts).countTestCases(), 13)
        self.assertEqual(raw.ROOT, ROOT)
        self.assertEqual(digest((ROOT/'tools/check_profile_read_failure_contract.py').read_bytes()),
                         'e492facdded0e76615721d90081b912738ba490e503aab61a7ed549a6b2a4b8a')

    def test_historical_readers_preserve_original_complete_bytes(self):
        for relative, end, replacements, expected in [
            ('Tests/ContractChecks/test_profile_reload_discard.py', "VIEW=ROOT/", [
                ('sha(historical_profile_input(path, (ROOT/path).read_bytes()))', 'sha((ROOT/path).read_bytes())')],
             '3da1b513c2fdcbafcfe98c6ddc9172cc453caca11954d140c51ed78c2f41da25'),
            ('Tests/ContractChecks/test_profile_avatar.py', 'PROTECTED = ', [
                ('value=historical_profile_input(path, (ROOT/path).read_bytes())', 'value=(ROOT/path).read_bytes()'),
                ('hashlib.sha256(historical_protected_input(path, (ROOT/path).read_bytes())).hexdigest()', 'hashlib.sha256((ROOT/path).read_bytes()).hexdigest()')],
             '3be8c14b0d722350f6dde13542824f334e3a3bf66e3e4c687a536deeb51e81f0')]:
            source = (ROOT/relative).read_text()
            start = source.index('ROOT=Path(__file__).resolve().parents[2]\n') + len('ROOT=Path(__file__).resolve().parents[2]\n')
            stop = source.index(end, start)
            self.assertTrue(source[start:stop].startswith('\n# Read-error admission'))
            source = source[:start] + source[stop:]
            for after, before in replacements:
                self.assertEqual(source.count(after), 1)
                source = source.replace(after, before, 1)
            self.assertEqual(digest(source.encode()), expected, relative)

    def test_nested_reload_pin_is_restored_independently_of_earlier_failures(self):
        avatar = load('Tests/ContractChecks/test_profile_avatar.py', 'profile_avatar_admission')
        relative = 'Tests/ContractChecks/test_profile_reload_discard.py'
        current = (ROOT/relative).read_bytes()
        restored = avatar.historical_protected_input(relative, current)
        self.assertEqual(digest(restored), '3da1b513c2fdcbafcfe98c6ddc9172cc453caca11954d140c51ed78c2f41da25')
        self.assertEqual(digest(restored), avatar.PROTECTED[relative])
        self.assertEqual(avatar.historical_reload_checker(restored), restored)
        for mutant in [current+b' ', current.replace(b'historical_profile_input(path, (ROOT/path).read_bytes())', b'(ROOT/path).read_bytes()', 1), current.replace(b'\n', b'\r\n')]:
            with self.assertRaises(ValueError):
                avatar.historical_reload_checker(mutant)

    def test_each_changed_protected_input_recovers_exact_original_bytes(self):
        avatar = load('Tests/ContractChecks/test_profile_avatar.py', 'avatar_frozen_inputs')
        for relative in ['Tests/CoreTests/ProfileEditTests.swift', 'Tests/ContractChecks/test_profile_reload_discard.py']:
            current = (ROOT/relative).read_bytes()
            restored = avatar.historical_protected_input(relative, current)
            self.assertEqual(digest(restored), avatar.PROTECTED[relative], relative)
            self.assertEqual(avatar.historical_protected_input(relative, restored), restored)
            for mutant in [current+b' ', b'\xef\xbb\xbf'+current, current.replace(b'\n', b'\r\n'), current+b'\xff']:
                with self.subTest(path=relative), self.assertRaises(ValueError):
                    avatar.historical_protected_input(relative, mutant)
        current = (ROOT/raw.TESTS).read_bytes()
        marker = avatar.CORE_TESTS_APPEND_MARKER
        original, suffix = current.split(marker, 1)
        for mutant in [current+marker, original+marker+suffix+b' ', original+b' '+marker+suffix, original+b'\n']:
            with self.assertRaises(ValueError):
                avatar.historical_core_tests(mutant)
        self.assertEqual(digest(original), raw.OLD_CORE_TESTS_SHA256)

    def test_historical_coordinator_boundaries_remain_narrow(self):
        data = (ROOT/raw.CORE).read_bytes()
        old = raw.validated_original_coordinator(data)
        for relative in ['Tests/ContractChecks/test_profile_avatar.py', 'Tests/ContractChecks/test_profile_reload_discard.py']:
            reader = load(relative, 'reader_'+Path(relative).stem)
            self.assertEqual(reader.historical_profile_input(raw.CORE, data), old)
            self.assertEqual(reader.historical_profile_input(raw.CORE, old), old)
            self.assertEqual(reader.historical_profile_input('unrelated', data), data)
            for name, mutant in raw.coordinator_byte_mutations(data):
                with self.subTest(reader=relative, mutation=name), self.assertRaises(ValueError):
                    reader.historical_profile_input(raw.CORE, mutant)

    def test_original_contract_floor_hunks_pins_and_algorithm_are_frozen(self):
        contract = json.loads(_combined_profile_contract((ROOT/READINESS_PATH).read_bytes(), ROOT))
        row = contract['feature_batch_sources'][raw.CORE]
        self.assertEqual(row['before_sha256'], 'c08da5dead9c78d7256fecf8853f4a9a4122a5cf3ad5cca4dec3cbce7a03982f')
        self.assertEqual(row['after_sha256'], raw.CURRENT_COORDINATOR_SHA256)
        self.assertEqual(len(row['hunks']), 9)
        value = (ROOT/raw.CORE).read_text()
        for hunk in reversed(row['hunks'][5:]):
            self.assertEqual(value.count(hunk['after']), 1)
            value = value.replace(hunk['after'], hunk['before'], 1)
        self.assertEqual(digest(value.encode()), raw.OLD_COORDINATOR_SHA256)
        # Recover the complete old contract, not a selected set of assertions.
        row['after_sha256'] = raw.OLD_COORDINATOR_SHA256
        row['hunks'] = row['hunks'][:5]
        support = contract['feature_batch_support_sha256']
        support['Tests/ContractChecks/test_profile_avatar.py'] = '3be8c14b0d722350f6dde13542824f334e3a3bf66e3e4c687a536deeb51e81f0'
        support['Tests/ContractChecks/test_profile_reload_discard.py'] = '3da1b513c2fdcbafcfe98c6ddc9172cc453caca11954d140c51ed78c2f41da25'
        for path in ['tools/check_profile_read_failure_contract.py', 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py', raw.TESTS, SCANNER_PATH]:
            del support[path]
        self.assertEqual(digest((json.dumps(contract, indent=2, ensure_ascii=False)+'\n').encode()), '11cc2e20ce328dcba2fcfbcb4425bf581908038c71d4f4c7eee15c1bbab1b2b6')
        self.assertEqual(digest((ROOT/'tools/run138_current_source_projection.py').read_bytes()), 'c0e6a5351bd024bdcbf8d1152bb4e8cb683cc5ff15e370627a14e229a1158727')
        from Tests.ContractChecks.test_category_roam_registration import uncached_readiness_source
        source = uncached_readiness_source((ROOT/'tools/run138_editor_readiness.py').read_bytes()).decode()
        current = digest((ROOT/'tools/run138_editor_readiness_contract.json').read_bytes())
        self.assertEqual(source.count("CONTRACT_SHA256 = '"+current+"'"), 1)
        original = source.replace("CONTRACT_SHA256 = '"+current+"'", "CONTRACT_SHA256 = '11cc2e20ce328dcba2fcfbcb4425bf581908038c71d4f4c7eee15c1bbab1b2b6'", 1)
        self.assertEqual(digest(original.encode()), 'cafa9858b24a18f3827ce5678701b1e32cf533e66d51dc43788b15a74d60a79f')

    def test_scanner_reader_inverse_recovers_complete_original_checker(self):
        source = (ROOT/SCANNER_PATH).read_text()
        for before, after in reversed(SCANNER_READER_HUNKS):
            self.assertEqual(source.count(after), 1)
            source = source.replace(after, before, 1)
        self.assertEqual(digest(source.encode()), 'c305a75379a5cb47e34314e997a7f49ea6ab9e5877887fe13465ba49f2df9f8c')
        self.assertEqual(len(re.findall(r'^    def test_', source, re.MULTILINE)), 9)

    def test_scanner_contract_reader_restores_old_lines_and_rejects_drift(self):
        current = (ROOT/READINESS_PATH).read_bytes()
        old = historical_readiness_contract(current)
        self.assertEqual(digest(old), ORIGINAL_READINESS_SHA256)
        self.assertEqual(historical_readiness_contract(old), old)
        self.assertEqual(digest(old.decode().splitlines()[4027].encode()),
                         'a808e190bda202c021e4cbada812e684d92e4e7ac6848d2016c944c3d3d494e4')
        for mutant in [current+b' ', b'\xef\xbb\xbf'+current, current+b'\xff',
                       current.replace(b'\n', b'\r\n'), current.replace(b'"hunks": [', b'"hunks": [ ', 1),
                       old+b'\n', b'{}\n']:
            with self.assertRaises(ValueError):
                historical_readiness_contract(mutant)
        # Old bytes remain historical-only; the real current contract gate rejects them.
        sys.path.insert(0, str(ROOT/'tools'))
        try:
            import run138_editor_readiness as planning
            self.assertNotEqual(digest(old), planning.CONTRACT_SHA256)
            self.assertEqual(digest(current), planning.CONTRACT_SHA256)
        finally:
            sys.path.pop(0)

    def test_actual_central_validators_and_current_rejection(self):
        sys.path.insert(0, str(ROOT/'tools'))
        try:
            import run138_current_source_projection as projection
            import run138_editor_readiness as planning
            projection.validate_feature_batch_sources(ROOT)
            projection.validate_entries(ROOT)
            data = (ROOT/raw.CORE).read_bytes()
            restored = projection.original_feature_batch_bytes(raw.CORE, data, ROOT)
            self.assertEqual(digest(restored), 'c08da5dead9c78d7256fecf8853f4a9a4122a5cf3ad5cca4dec3cbce7a03982f')
            for mutant in [raw.validated_original_coordinator(data), *[m for _, m in raw.coordinator_byte_mutations(data)]]:
                with self.assertRaises(ValueError):
                    projection.original_feature_batch_bytes(raw.CORE, mutant, ROOT)
            required = planning.required_followon_files(ROOT)
            self.assertTrue({'tools/check_profile_read_failure_contract.py', 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py', raw.TESTS} <= required)
        finally:
            sys.path.pop(0)

class ProfileMerchantCombinedAdmission(unittest.TestCase):
    def substituted(self, changed):
        original = Path.read_bytes
        def read(path):
            key = str(path)
            return changed[key] if key in changed else original(path)
        return patch.object(Path, 'read_bytes', read)

    def current(self):
        return (ROOT/READINESS_PATH).read_bytes()

    def test_complete_raw_group_and_two_exact_historical_floors(self):
        data=self.current()
        self.assertEqual(digest(_combined_profile_contract(data)), PROFILE_R2_CONTRACT_SHA256)
        self.assertEqual(digest(historical_readiness_contract(data)), ORIGINAL_READINESS_SHA256)
        merchant=load('Tests/ContractChecks/test_merchant_decor_tag_picker.py','combined_merchant_gate')
        self.assertEqual(merchant.historical_scanner_contract_bytes(ROOT),historical_readiness_contract(data))
        for name, expected in COMBINED_RAW_SHA256.items():
            self.assertEqual(digest((ROOT/name).read_bytes()),expected,name)
        self.assertEqual(digest((ROOT/SCANNER_PATH).read_bytes()),
                         'a5f5cd4f8670fb10405ab73fba1ac15700ace46a0c8dd4e8321e29e5da90cb30')

    def test_every_raw_input_drift_and_missing_file_rejected(self):
        data=self.current()
        for name in (*COMBINED_RAW_SHA256,COMBINED_ADMISSION_PATH):
            path=ROOT/name;raw=path.read_bytes()
            for value in [raw+b'\n',raw[:-1],b'\xef\xbb\xbf'+raw,raw.replace(b'\n',b'\r\n'),bytes([raw[0]^1])+raw[1:]]:
                with self.subTest(path=name),self.substituted({str(path):value}),self.assertRaises(ValueError):
                    _combined_profile_contract(data)
            original=Path.read_bytes
            def missing(p):
                if p==path:raise FileNotFoundError(name)
                return original(p)
            with patch.object(Path,'read_bytes',missing),self.assertRaises(ValueError):
                _combined_profile_contract(data)

    def test_mixed_base_products_or_support_bindings_cannot_be_admitted(self):
        data=self.current();contract=json.loads(data)
        legacy={raw.CORE:raw.OLD_COORDINATOR_SHA256,MERCHANT_SOURCE_PATH:MERCHANT_PREIMAGE_SHA256,
                **MERCHANT_SUPPORT_PREIMAGES,
                'Tests/ContractChecks/test_profile_avatar.py':'3be8c14b0d722350f6dde13542824f334e3a3bf66e3e4c687a536deeb51e81f0',
                'Tests/ContractChecks/test_profile_reload_discard.py':'3da1b513c2fdcbafcfe98c6ddc9172cc453caca11954d140c51ed78c2f41da25',
                COMBINED_ADMISSION_PATH:PROFILE_R2_ADMISSION_SHA256}
        for name, old in legacy.items():
            changed=json.loads(data)
            if name in changed['feature_batch_sources']:changed['feature_batch_sources'][name]['after_sha256']=old
            else:changed['feature_batch_support_sha256'][name]=old
            self.reject_repinned(changed)
        for name in ['tools/check_profile_read_failure_contract.py',COMBINED_ADMISSION_PATH,raw.TESTS,SCANNER_PATH]:
            changed=json.loads(data);del changed['feature_batch_support_sha256'][name];self.reject_repinned(changed)
        for name in [raw.CORE,MERCHANT_SOURCE_PATH]:
            changed=json.loads(data);changed['feature_batch_sources'][name]['hunks'].pop();self.reject_repinned(changed)

    def reject_repinned(self, changed):
        current=self.current();mutant=changed if isinstance(changed,bytes) else (json.dumps(changed,indent=2,ensure_ascii=False)+'\n').encode()
        runner=(ROOT/'tools/run138_editor_readiness.py').read_bytes()
        runner=runner.replace(digest(current).encode(),digest(mutant).encode(),1)
        with self.substituted({str(ROOT/READINESS_PATH):mutant,str(ROOT/'tools/run138_editor_readiness.py'):runner}),self.assertRaises(ValueError):
            _combined_profile_contract(mutant)

    def test_repinned_unrelated_fields_unknown_hunks_and_format_rejected(self):
        data=self.current()
        changed=json.loads(data);changed['startup_reserve_seconds']+=1;self.reject_repinned(changed)
        changed=json.loads(data);changed['feature_batch_sources'][MERCHANT_SOURCE_PATH]['hunks'][-1]['before']+='x';self.reject_repinned(changed)
        changed=json.loads(data);changed['feature_batch_sources'][raw.CORE]['hunks'][-1]['before']+='x';self.reject_repinned(changed)
        changed=json.loads(data);changed['feature_batch_support_sha256']['unrelated-new-path']='0'*64;self.reject_repinned(changed)
        for changed in [data+b'\n',data.replace(b'\n',b'\r\n'),b'\xef\xbb\xbf'+data,json.dumps(json.loads(data),ensure_ascii=False).encode()]:
            self.reject_repinned(changed)
        self.reject_repinned(_combined_profile_contract(data))
        self.reject_repinned(historical_readiness_contract(data))

    def test_repinned_adapter_drift_and_runner_changes_rejected(self):
        data=self.current()
        for name in [COMBINED_ADMISSION_PATH,'Tests/ContractChecks/test_merchant_decor_tag_picker.py',SCANNER_PATH]:
            path=ROOT/name;mutant=path.read_bytes()+b'\n'
            changed=json.loads(data);changed['feature_batch_support_sha256'][name]=digest(mutant)
            encoded=(json.dumps(changed,indent=2,ensure_ascii=False)+'\n').encode()
            runner=(ROOT/'tools/run138_editor_readiness.py').read_bytes().replace(digest(data).encode(),digest(encoded).encode(),1)
            with self.substituted({str(path):mutant,str(ROOT/READINESS_PATH):encoded,str(ROOT/'tools/run138_editor_readiness.py'):runner}),self.assertRaises(ValueError):
                _combined_profile_contract(encoded)
        modulepath=ROOT/COMBINED_ADMISSION_PATH
        mutant=modulepath.read_bytes().replace(COMBINED_ADMISSION_FINGERPRINT.encode(),b'0'*64,1)
        changed=json.loads(data);changed['feature_batch_support_sha256'][COMBINED_ADMISSION_PATH]=digest(mutant)
        encoded=(json.dumps(changed,indent=2,ensure_ascii=False)+'\n').encode()
        runner=(ROOT/'tools/run138_editor_readiness.py').read_bytes().replace(digest(data).encode(),digest(encoded).encode(),1)
        with self.substituted({str(modulepath):mutant,str(ROOT/READINESS_PATH):encoded,str(ROOT/'tools/run138_editor_readiness.py'):runner}),self.assertRaises(ValueError):
            _combined_profile_contract(encoded)
        runnerpath=ROOT/'tools/run138_editor_readiness.py'
        for mutant in [runnerpath.read_bytes()+b'\n',runnerpath.read_bytes().replace(digest(data).encode(),b'0'*64,1)]:
            with self.substituted({str(runnerpath):mutant}),self.assertRaises(ValueError):_combined_profile_contract(data)

    def test_raw_positive_gates_do_not_depend_on_historical_projection(self):
        merchant=load('Tests/ContractChecks/test_merchant_decor_tag_picker.py','combined_forward_merchant')
        suite=unittest.TestSuite([unittest.defaultTestLoader.loadTestsFromTestCase(ProfileReadFailureContracts),
                                unittest.defaultTestLoader.loadTestsFromTestCase(merchant.MerchantDecorTagPickerContracts)])
        with patch.dict(globals(),{'historical_readiness_contract':lambda *a,**k:(_ for _ in ()).throw(AssertionError('inverse forbidden')),
                                   '_combined_profile_contract':lambda *a,**k:(_ for _ in ()).throw(AssertionError('inverse forbidden'))}):
            result=unittest.TestResult();suite.run(result)
        self.assertEqual(result.testsRun,20)
        self.assertEqual(result.failures,[])
        self.assertEqual(result.errors,[])
        self.assertEqual(result.skipped,[])

class CompileRepairCombinedAdmission(unittest.TestCase):
    def test_exact_new_layer_preserves_all_three_complete_contract_floors(self):
        data=(ROOT/READINESS_PATH).read_bytes()
        restored=_compile_repair_combined_contract(_static_observability_contract(_crop_static_contract(_creator_state_contract(_merchant_business_compile_contract(json.loads(data))))))
        encoded=(json.dumps(restored,indent=2,ensure_ascii=False)+'\n').encode()
        self.assertEqual(digest(encoded),COMBINED_PRECOMPILE_SHA256)
        self.assertEqual(digest(_combined_profile_contract(data)),PROFILE_R2_CONTRACT_SHA256)
        self.assertEqual(digest(historical_readiness_contract(data)),ORIGINAL_READINESS_SHA256)
        source=(ROOT/COMPILE_REPAIR_PATH).read_text()
        hunk=COMPILE_REPAIR_ROW['hunks'][0]
        self.assertEqual(source.count(hunk['after']),1)
        old=source.replace(hunk['after'],hunk['before'],1)
        self.assertEqual(digest(old.encode()),COMPILE_REPAIR_ROW['before_sha256'])
        self.assertEqual(re.findall(r'func (test\w+)',source),re.findall(r'func (test\w+)',old))
        self.assertEqual(re.findall(r'XCTAssert\w+\(.*',source),re.findall(r'XCTAssert\w+\(.*',old))

    def test_old_new_mixed_order_and_repinned_incomplete_groups_fail(self):
        probe=ProfileMerchantCombinedAdmission()
        data=(ROOT/READINESS_PATH).read_bytes(); current=json.loads(data)
        # Wrong order: starting from the already projected combined/profile/original
        # contract cannot pass current admission even when its runner pin changes.
        combined=_compile_repair_combined_contract(_static_observability_contract(_crop_static_contract(_creator_state_contract(_merchant_business_compile_contract(json.loads(data))))))
        for value in [combined,_combined_profile_contract(data),historical_readiness_contract(data)]:
            probe.reject_repinned(value)
        for mode in ['missing-row','missing-support','old-support','old-module-support','extra-hunk','changed-hunk','other-field']:
            changed=json.loads(data)
            if mode=='missing-row':del changed['feature_batch_sources'][COMPILE_REPAIR_PATH]
            elif mode=='missing-support':del changed['feature_batch_support_sha256'][COMPILE_REPAIR_PATH]
            elif mode=='old-support':changed['feature_batch_support_sha256'][COMPILE_REPAIR_PATH]=COMPILE_REPAIR_ROW['before_sha256']
            elif mode=='old-module-support':changed['feature_batch_support_sha256'][COMBINED_ADMISSION_PATH]=COMBINED_PRECOMPILE_ADMISSION_SHA256
            elif mode=='extra-hunk':changed['feature_batch_sources'][COMPILE_REPAIR_PATH]['hunks']*=2
            elif mode=='changed-hunk':changed['feature_batch_sources'][COMPILE_REPAIR_PATH]['hunks'][0]['before']+=' '
            else:changed['startup_reserve_seconds']+=1
            with self.subTest(mode=mode):probe.reject_repinned(changed)
        path=ROOT/COMPILE_REPAIR_PATH; rawdata=path.read_bytes(); hunk=COMPILE_REPAIR_ROW['hunks'][0]
        for value in [rawdata+b'\n',rawdata.replace(hunk['after'].encode(),hunk['before'].encode(),1),rawdata+hunk['after'].encode()]:
            with probe.substituted({str(path):value}),self.assertRaises(ValueError):_combined_profile_contract(data)


class StaticObservabilityCombinedAdmission(unittest.TestCase):
    def current(self):
        return (ROOT/READINESS_PATH).read_bytes()

    def test_exact_static_layer_restores_complete_published_r5_and_all_old_floors(self):
        data = self.current()
        restored = _static_observability_contract(_crop_static_contract(_creator_state_contract(_merchant_business_compile_contract(json.loads(data)))))
        encoded = (json.dumps(restored, indent=2, ensure_ascii=False)+'\n').encode()
        self.assertEqual(digest(encoded), STATIC_OBSERVABILITY_PRECONTRACT_SHA256)
        self.assertEqual(restored['feature_batch_support_sha256'][COMBINED_ADMISSION_PATH],
                         STATIC_OBSERVABILITY_PREADMISSION_SHA256)
        for name, row in STATIC_OBSERVABILITY_SUPPORT.items():
            self.assertEqual(digest((ROOT/name).read_bytes()), row['after_sha256'])
            self.assertEqual(json.loads(data)['followon_support_sha256'][name], row['after_sha256'])
            self.assertEqual(restored['followon_support_sha256'][name], row['before_sha256'])
        combined = _compile_repair_combined_contract(restored)
        self.assertEqual(digest((json.dumps(combined, indent=2, ensure_ascii=False)+'\n').encode()),
                         COMBINED_PRECOMPILE_SHA256)
        self.assertEqual(digest(_combined_profile_contract(data)), PROFILE_R2_CONTRACT_SHA256)
        self.assertEqual(digest(historical_readiness_contract(data)), ORIGINAL_READINESS_SHA256)

    def test_each_static_raw_drift_or_missing_file_is_rejected(self):
        data = self.current(); probe = ProfileMerchantCombinedAdmission()
        for name in STATIC_OBSERVABILITY_SUPPORT:
            path = ROOT/name; value = path.read_bytes()
            for mutant in [value+b'\n', value[:-1], b'\xef\xbb\xbf'+value,
                           value.replace(b'\n', b'\r\n'), bytes([value[0]^1])+value[1:]]:
                with self.subTest(path=name), probe.substituted({str(path):mutant}), self.assertRaises(ValueError):
                    _combined_profile_contract(data)
            original = Path.read_bytes
            def missing(p):
                if p == path: raise FileNotFoundError(name)
                return original(p)
            with patch.object(Path, 'read_bytes', missing), self.assertRaises(ValueError):
                _combined_profile_contract(data)

    def test_repinned_static_old_new_mixed_supports_and_unknown_fields_rejected(self):
        data = self.current(); probe = ProfileMerchantCombinedAdmission()
        for name, row in STATIC_OBSERVABILITY_SUPPORT.items():
            for mode in ['missing', 'old', 'forged']:
                changed = json.loads(data)
                if mode == 'missing': del changed['followon_support_sha256'][name]
                else: changed['followon_support_sha256'][name] = row['before_sha256'] if mode == 'old' else '0'*64
                with self.subTest(path=name, mode=mode): probe.reject_repinned(changed)
        for mode in ['unknown-top', 'unknown-followon', 'unknown-feature', 'old-self', 'missing-self']:
            changed = json.loads(data)
            if mode == 'unknown-top': changed['unreviewed_static_field'] = True
            elif mode == 'unknown-followon': changed['followon_support_sha256']['tools/unreviewed_static.py'] = '0'*64
            elif mode == 'unknown-feature': changed['feature_batch_support_sha256']['tools/unreviewed_static.py'] = '0'*64
            elif mode == 'old-self': changed['feature_batch_support_sha256'][COMBINED_ADMISSION_PATH] = STATIC_OBSERVABILITY_PREADMISSION_SHA256
            else: del changed['feature_batch_support_sha256'][COMBINED_ADMISSION_PATH]
            with self.subTest(mode=mode): probe.reject_repinned(changed)
        probe.reject_repinned(_static_observability_contract(_crop_static_contract(_creator_state_contract(_merchant_business_compile_contract(json.loads(data))))))

    def test_repinned_new_static_raw_hashes_do_not_authorize_changed_sources(self):
        data = self.current(); probe = ProfileMerchantCombinedAdmission()
        for name in STATIC_OBSERVABILITY_SUPPORT:
            path = ROOT/name; mutant = path.read_bytes()+b'\n'
            changed = json.loads(data); changed['followon_support_sha256'][name] = digest(mutant)
            encoded = (json.dumps(changed, indent=2, ensure_ascii=False)+'\n').encode()
            runnerpath = ROOT/'tools/run138_editor_readiness.py'
            runner = runnerpath.read_bytes().replace(digest(data).encode(), digest(encoded).encode(), 1)
            with probe.substituted({str(path):mutant, str(ROOT/READINESS_PATH):encoded, str(runnerpath):runner}), self.assertRaises(ValueError):
                _combined_profile_contract(encoded)

    def test_static_preimages_and_self_preimage_are_bound_by_whole_r5_contract(self):
        data = self.current()
        for name, row in STATIC_OBSERVABILITY_SUPPORT.items():
            forged = dict(row, before_sha256='0'*64)
            with self.subTest(path=name), patch.dict(STATIC_OBSERVABILITY_SUPPORT, {name:forged}), self.assertRaisesRegex(ValueError, 'Complete published R5'):
                _static_observability_contract(_crop_static_contract(_creator_state_contract(_merchant_business_compile_contract(json.loads(data)))))
        with patch.dict(globals(), {'STATIC_OBSERVABILITY_PREADMISSION_SHA256':'0'*64}), self.assertRaisesRegex(ValueError, 'Complete published R5'):
            _static_observability_contract(_crop_static_contract(_creator_state_contract(_merchant_business_compile_contract(json.loads(data)))))


class CropStaticCombinedAdmission(unittest.TestCase):
    def test_exact_crop_layer_restores_frozen_static_and_all_old_floors(self):
        data = (ROOT/READINESS_PATH).read_bytes()
        restored = _crop_static_contract(_creator_state_contract(_merchant_business_compile_contract(json.loads(data))))
        encoded = (json.dumps(restored, indent=2, ensure_ascii=False)+'\n').encode()
        self.assertEqual(digest(encoded), CROP_PRESTATIC_CONTRACT_SHA256)
        self.assertNotIn(CROP_COMPILE_REPAIR_PATH, restored['feature_batch_sources'])
        self.assertEqual(restored['feature_batch_support_sha256'][CROP_COMPILE_REPAIR_PATH],
                         CROP_COMPILE_REPAIR_ROW['before_sha256'])
        self.assertEqual(restored['feature_batch_support_sha256'][COMBINED_ADMISSION_PATH],
                         CROP_PRESTATIC_ADMISSION_SHA256)
        published = _static_observability_contract(restored)
        self.assertEqual(digest((json.dumps(published, indent=2, ensure_ascii=False)+'\n').encode()),
                         STATIC_OBSERVABILITY_PRECONTRACT_SHA256)
        self.assertEqual(digest(_combined_profile_contract(data)), PROFILE_R2_CONTRACT_SHA256)
        self.assertEqual(digest(historical_readiness_contract(data)), ORIGINAL_READINESS_SHA256)
        value = (ROOT/CROP_COMPILE_REPAIR_PATH).read_bytes()
        hunk = CROP_COMPILE_REPAIR_ROW['hunks'][0]
        self.assertEqual(value.count(hunk['after'].encode()), 1)
        old = value.replace(hunk['after'].encode(), hunk['before'].encode(), 1)
        self.assertEqual(digest(old), CROP_COMPILE_REPAIR_ROW['before_sha256'])
        self.assertEqual(re.findall(rb'(horizontal|vertical|zoom)=([0-9.]+)', value),
                         re.findall(rb'(horizontal|vertical|zoom)=([0-9.]+)', old))

    def test_repinned_crop_mixed_groups_unknown_fields_and_wrong_order_rejected(self):
        data = (ROOT/READINESS_PATH).read_bytes(); probe = ProfileMerchantCombinedAdmission()
        for mode in ['missing-row', 'missing-support', 'old-support', 'old-self', 'duplicate-hunk', 'unknown-hunk', 'unrelated']:
            changed = json.loads(data)
            if mode == 'missing-row': del changed['feature_batch_sources'][CROP_COMPILE_REPAIR_PATH]
            elif mode == 'missing-support': del changed['feature_batch_support_sha256'][CROP_COMPILE_REPAIR_PATH]
            elif mode == 'old-support': changed['feature_batch_support_sha256'][CROP_COMPILE_REPAIR_PATH] = CROP_COMPILE_REPAIR_ROW['before_sha256']
            elif mode == 'old-self': changed['feature_batch_support_sha256'][COMBINED_ADMISSION_PATH] = CROP_PRESTATIC_ADMISSION_SHA256
            elif mode == 'duplicate-hunk': changed['feature_batch_sources'][CROP_COMPILE_REPAIR_PATH]['hunks'] *= 2
            elif mode == 'unknown-hunk': changed['feature_batch_sources'][CROP_COMPILE_REPAIR_PATH]['hunks'][0]['before'] += ' '
            else: changed['unreviewed_crop_field'] = True
            with self.subTest(mode=mode): probe.reject_repinned(changed)
        probe.reject_repinned(_crop_static_contract(_creator_state_contract(_merchant_business_compile_contract(json.loads(data)))))

    def test_crop_raw_drift_and_rehashed_mutations_remain_rejected(self):
        data = (ROOT/READINESS_PATH).read_bytes(); probe = ProfileMerchantCombinedAdmission()
        path = ROOT/CROP_COMPILE_REPAIR_PATH; value = path.read_bytes()
        hunk = CROP_COMPILE_REPAIR_ROW['hunks'][0]
        for mutant in [value+b'\n', value.replace(hunk['after'].encode(), hunk['before'].encode(), 1),
                       value+hunk['after'].encode(), b'\xef\xbb\xbf'+value]:
            with probe.substituted({str(path):mutant}), self.assertRaises(ValueError):
                _combined_profile_contract(data)
            changed = json.loads(data)
            changed['feature_batch_sources'][CROP_COMPILE_REPAIR_PATH]['after_sha256'] = digest(mutant)
            changed['feature_batch_support_sha256'][CROP_COMPILE_REPAIR_PATH] = digest(mutant)
            encoded = (json.dumps(changed, indent=2, ensure_ascii=False)+'\n').encode()
            runnerpath = ROOT/'tools/run138_editor_readiness.py'
            runner = runnerpath.read_bytes().replace(digest(data).encode(), digest(encoded).encode(), 1)
            with probe.substituted({str(path):mutant, str(ROOT/READINESS_PATH):encoded, str(runnerpath):runner}), self.assertRaises(ValueError):
                _combined_profile_contract(encoded)

    def test_crop_self_preimage_is_bound_by_complete_static_contract(self):
        data = (ROOT/READINESS_PATH).read_bytes()
        with patch.dict(globals(), {'CROP_PRESTATIC_ADMISSION_SHA256':'0'*64}), self.assertRaisesRegex(ValueError, 'Complete frozen static'):
            _crop_static_contract(_creator_state_contract(_merchant_business_compile_contract(json.loads(data))))


class CreatorStateCombinedAdmission(unittest.TestCase):
    def test_exact_creator_layer_preserves_every_preceding_complete_floor(self):
        data=(ROOT/READINESS_PATH).read_bytes()
        restored=_creator_state_contract(_merchant_business_compile_contract(json.loads(data)))
        encoded=(json.dumps(restored,indent=2,ensure_ascii=False)+'\n').encode()
        self.assertEqual(digest(encoded),CREATOR_STATE_PRECONTRACT_SHA256)
        self.assertEqual(restored['feature_batch_support_sha256'][COMBINED_ADMISSION_PATH],CREATOR_STATE_PREADMISSION_SHA256)
        self.assertEqual(restored['feature_batch_support_sha256'][CREATOR_STATE_CATALOG],CREATOR_STATE_OLD_CATALOG_SHA256)
        static=_crop_static_contract(restored)
        self.assertEqual(digest((json.dumps(static,indent=2,ensure_ascii=False)+'\n').encode()),CROP_PRESTATIC_CONTRACT_SHA256)
        published=_static_observability_contract(static)
        self.assertEqual(digest((json.dumps(published,indent=2,ensure_ascii=False)+'\n').encode()),STATIC_OBSERVABILITY_PRECONTRACT_SHA256)
        combined=_compile_repair_combined_contract(published)
        self.assertEqual(digest((json.dumps(combined,indent=2,ensure_ascii=False)+'\n').encode()),COMBINED_PRECOMPILE_SHA256)
        self.assertEqual(digest(_combined_profile_contract(data)),PROFILE_R2_CONTRACT_SHA256)
        self.assertEqual(digest(historical_readiness_contract(data)),ORIGINAL_READINESS_SHA256)

    def test_each_creator_raw_input_drift_or_missing_rejected(self):
        data=(ROOT/READINESS_PATH).read_bytes();probe=ProfileMerchantCombinedAdmission()
        for name in CREATOR_STATE_RAW_SHA256:
            path=ROOT/name;value=path.read_bytes()
            for mutant in [value+b'\n',value[:-1],b'\xef\xbb\xbf'+value,
                           value.replace(b'\n',b'\r\n'),bytes([value[0]^1])+value[1:]]:
                with self.subTest(path=name),probe.substituted({str(path):mutant}),self.assertRaises(ValueError):
                    _combined_profile_contract(data)
            original=Path.read_bytes
            def missing(p):
                if p==path:raise FileNotFoundError(name)
                return original(p)
            with patch.object(Path,'read_bytes',missing),self.assertRaises(ValueError):_combined_profile_contract(data)

    def test_repinned_mixed_creator_bindings_self_and_unknown_changes_rejected(self):
        data=(ROOT/READINESS_PATH).read_bytes();probe=ProfileMerchantCombinedAdmission()
        for mode in ['old-catalog','missing-catalog','forged-catalog','old-self','unknown-feature','unknown-top']:
            changed=json.loads(data);support=changed['feature_batch_support_sha256']
            if mode=='old-catalog':support[CREATOR_STATE_CATALOG]=CREATOR_STATE_OLD_CATALOG_SHA256
            elif mode=='missing-catalog':del support[CREATOR_STATE_CATALOG]
            elif mode=='forged-catalog':support[CREATOR_STATE_CATALOG]='0'*64
            elif mode=='old-self':support[COMBINED_ADMISSION_PATH]=CREATOR_STATE_PREADMISSION_SHA256
            elif mode=='unknown-feature':support['tools/unreviewed_creator.py']='0'*64
            else:changed['unreviewed_creator']=True
            with self.subTest(mode=mode):probe.reject_repinned(changed)
        probe.reject_repinned(_creator_state_contract(_merchant_business_compile_contract(json.loads(data))))
        for name in CREATOR_STATE_RAW_SHA256:
            path=ROOT/name;mutant=path.read_bytes()+b'\n';changed=json.loads(data)
            if name in changed['feature_batch_support_sha256']:
                changed['feature_batch_support_sha256'][name]=digest(mutant)
            else:changed['feature_batch_support_sha256'][name]=digest(mutant)
            encoded=(json.dumps(changed,indent=2,ensure_ascii=False)+'\n').encode()
            runnerpath=ROOT/'tools/run138_editor_readiness.py'
            runner=runnerpath.read_bytes().replace(digest(data).encode(),digest(encoded).encode(),1)
            with probe.substituted({str(path):mutant,str(ROOT/READINESS_PATH):encoded,str(runnerpath):runner}),self.assertRaises(ValueError):
                _combined_profile_contract(encoded)

    def test_catalog_inverse_bounds_and_whole_floor_cannot_be_relaxed(self):
        data=(ROOT/READINESS_PATH).read_bytes()
        for name in ['CREATOR_STATE_BLOCK_SHA256','CREATOR_STATE_OLD_CATALOG_SHA256','CREATOR_STATE_PREADMISSION_SHA256']:
            with patch.dict(globals(),{name:'0'*64}),self.assertRaises(ValueError):
                _creator_state_contract(_merchant_business_compile_contract(json.loads(data)))

    def test_raw_creator_positive_contract_is_independent_of_all_history(self):
        directory=str(ROOT/'Tests/ContractChecks');sys.path.insert(0,directory)
        try:
            import test_template_shelf_state_projection as state_gate
            state_gate.ROOT=ROOT
            with patch.dict(globals(),{'_creator_state_contract':lambda *a,**k:(_ for _ in ()).throw(AssertionError('inverse forbidden')),
                                       '_combined_profile_contract':lambda *a,**k:(_ for _ in ()).throw(AssertionError('inverse forbidden'))}):
                result=unittest.TestResult()
                unittest.defaultTestLoader.loadTestsFromTestCase(state_gate.TemplateShelfStateProjectionContracts).run(result)
            self.assertEqual(result.testsRun,4);self.assertEqual(result.failures,[]);self.assertEqual(result.errors,[]);self.assertEqual(result.skipped,[])
        finally:sys.path.pop(0)


class MerchantBusinessCompileAdmission(unittest.TestCase):
    def test_exact_current_group_and_complete_creator_floor(self):
        from tools import run138_current_source_projection as projection
        projection.validate_feature_batch_sources(ROOT)
        data=(ROOT/READINESS_PATH).read_bytes()
        restored=_merchant_business_compile_contract(json.loads(data))
        self.assertEqual(digest((json.dumps(restored,indent=2,ensure_ascii=False)+'\n').encode()),MERCHANT_BUSINESS_PRE_CONTRACT_SHA256)
        self.assertEqual(digest(historical_readiness_contract(data)),ORIGINAL_READINESS_SHA256)
        self.assertEqual(len(MERCHANT_BUSINESS_CURRENT_RAW_SHA256),12)

    def test_every_current_input_drift_and_absence_rejected(self):
        probe=ProfileMerchantCombinedAdmission();data=(ROOT/READINESS_PATH).read_bytes()
        names=[*MERCHANT_BUSINESS_CURRENT_RAW_SHA256,COMBINED_ADMISSION_PATH,READINESS_PATH,'tools/run138_editor_readiness.py']
        for name in names:
            path=ROOT/name;value=path.read_bytes()
            with self.subTest(path=name),probe.substituted({str(path):value+b'\n'}),self.assertRaises(ValueError):
                _combined_profile_contract((ROOT/READINESS_PATH).read_bytes())
            original=Path.read_bytes
            def missing(p):
                if p==path:raise FileNotFoundError(name)
                return original(p)
            with self.subTest(missing=name),patch.object(Path,'read_bytes',missing),self.assertRaises(ValueError):
                _combined_profile_contract(data)

    def test_repinned_old_new_mixed_rows_and_unknown_inverse_rejected(self):
        data=(ROOT/READINESS_PATH).read_bytes();probe=ProfileMerchantCombinedAdmission()
        for mode in ['old-source','missing-hunk','duplicate-hunk','forged-hunk','old-self','unknown-top']:
            changed=json.loads(data);row=changed['feature_batch_sources'][MERCHANT_BUSINESS_COMPILE_PATH]
            if mode=='old-source':row['after_sha256']=MERCHANT_BUSINESS_PRE_SOURCE_SHA256
            elif mode=='missing-hunk':row['hunks'].pop()
            elif mode=='duplicate-hunk':row['hunks'].append(MERCHANT_BUSINESS_COMPILE_HUNK)
            elif mode=='forged-hunk':row['hunks'][-1]['before']+='x'
            elif mode=='old-self':changed['feature_batch_support_sha256'][COMBINED_ADMISSION_PATH]=MERCHANT_BUSINESS_PRE_ADMISSION_SHA256
            else:changed['unknown_compile']=True
            with self.subTest(mode=mode):probe.reject_repinned(changed)
        probe.reject_repinned(_merchant_business_compile_contract(json.loads(data)))

    def test_compile_layer_constants_cannot_relax_preimage_or_group(self):
        data=(ROOT/READINESS_PATH).read_bytes()
        for name in ['MERCHANT_BUSINESS_PRE_SOURCE_SHA256','MERCHANT_BUSINESS_POST_SOURCE_SHA256','MERCHANT_BUSINESS_PRE_CONTRACT_SHA256','MERCHANT_BUSINESS_PRE_ADMISSION_SHA256']:
            with self.subTest(name=name),patch.dict(globals(),{name:'0'*64}),self.assertRaises(ValueError):
                _merchant_business_compile_contract(json.loads(data))
        changed=dict(MERCHANT_BUSINESS_CURRENT_RAW_SHA256);changed[MERCHANT_BUSINESS_COMPILE_PATH]=MERCHANT_BUSINESS_PRE_SOURCE_SHA256
        with patch.dict(globals(),{'MERCHANT_BUSINESS_CURRENT_RAW_SHA256':changed}),self.assertRaises(ValueError):
            _merchant_business_compile_contract(json.loads(data))


SCANNER_READER_HUNKS = [('ROOT = Path(__file__).resolve().parents[2]\n', "ROOT = Path(__file__).resolve().parents[2]\n\n# This adapter restores only the original line-bound historical contract input.\nimport importlib.util\n_profile_spec = importlib.util.spec_from_file_location(\n    'profile_read_failure_remote_admission',\n    ROOT / 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py')\n_profile_admission = importlib.util.module_from_spec(_profile_spec)\n_profile_spec.loader.exec_module(_profile_admission)\n"), ('raw = (ROOT / FILE_DIGEST_PATH).read_text()', "raw = _profile_admission.historical_readiness_contract(\n            (ROOT / FILE_DIGEST_PATH).read_bytes(), ROOT).decode('utf-8')")]

class ClubDirectoryCombinedAdmission(unittest.TestCase):
    def test_complete_club_creator_and_frozen_permission_chains(self):
        from tools import club_customer_directory_admission as club
        data=(ROOT/READINESS_PATH).read_bytes()
        restored=_club_directory_contract(json.loads(data))
        self.assertEqual(digest((json.dumps(restored,indent=2,ensure_ascii=False)+'\n').encode()),club.CLUB_PRECONTRACT_SHA256)
        self.assertEqual(digest(historical_readiness_contract(data)),ORIGINAL_READINESS_SHA256)
        self.assertEqual(digest(club.frozen_permission_contract(ROOT).encode()),club.FROZEN_PERMISSION_CONTRACT_SHA256)
        self.assertEqual(digest(club.historical_scan_contract(ROOT).encode()),ORIGINAL_READINESS_SHA256)

    def test_each_club_raw_input_rejects_drift_and_missing(self):
        from tools import club_customer_directory_admission as club
        data=(ROOT/READINESS_PATH).read_bytes();probe=ProfileMerchantCombinedAdmission()
        for name in (*club.CLUB_RAW_SHA256,club.HELPER_PATH,COMBINED_ADMISSION_PATH):
            path=ROOT/name;value=path.read_bytes()
            for mutant in [value+b'\n',value[:-1],b'\xef\xbb\xbf'+value,value.replace(b'\n',b'\r\n'),bytes([value[0]^1])+value[1:]]:
                with self.subTest(path=name),probe.substituted({str(path):mutant}),self.assertRaises(ValueError):
                    _combined_profile_contract(data)
            original=Path.read_bytes
            def missing(p):
                if p==path:raise FileNotFoundError(name)
                return original(p)
            with patch.object(Path,'read_bytes',missing),self.assertRaises(ValueError):
                _combined_profile_contract(data)

    def test_club_repinned_unknown_mixed_or_self_rows_rejected(self):
        from tools import club_customer_directory_admission as club
        data=(ROOT/READINESS_PATH).read_bytes();probe=ProfileMerchantCombinedAdmission()
        for mode in ['source','hunk','support','helper','self','pbx','unknown']:
            changed=json.loads(data)
            if mode=='source':changed['feature_batch_sources']['App/ClubGovernanceViews.swift']['after_sha256']='0'*64
            elif mode=='hunk':changed['feature_batch_sources']['App/ClubGovernanceViews.swift']['hunks'].pop()
            elif mode=='support':del changed['feature_batch_support_sha256'][club.CLUB_SUPPORT_PATHS[0]]
            elif mode=='helper':changed['feature_batch_support_sha256'][club.HELPER_PATH]=club.FROZEN16_HELPER_SHA256
            elif mode=='self':changed['feature_batch_support_sha256'][COMBINED_ADMISSION_PATH]=club.CLUB_PREADMISSION_SHA256
            elif mode=='pbx':changed['feature_batch_sources']['Questify.xcodeproj/project.pbxproj']['hunks'].pop()
            else:changed['unreviewed_club_input']=True
            probe.reject_repinned(changed)

    def test_raw_club_gate_does_not_use_historical_inverse(self):
        from tools import run138_current_source_projection as projection
        with patch.dict(globals(),{'_club_directory_contract':lambda *a,**k:(_ for _ in ()).throw(AssertionError('inverse forbidden')),
                                  'historical_readiness_contract':lambda *a,**k:(_ for _ in ()).throw(AssertionError('inverse forbidden'))}):
            projection.validate_feature_batch_sources(ROOT)
            projection.validate_entries(ROOT)


    def test_fresh_import_helper_and_contract_runner_repin_is_rejected(self):
        import types
        import tools as toolspackage
        from tools import club_customer_directory_admission as club
        data=(ROOT/READINESS_PATH).read_bytes();probe=ProfileMerchantCombinedAdmission()
        helperpath=ROOT/club.HELPER_PATH
        mutant=helperpath.read_bytes()+b'\n'
        changed=json.loads(data);changed['feature_batch_support_sha256'][club.HELPER_PATH]=digest(mutant)
        encoded=(json.dumps(changed,indent=2,ensure_ascii=False)+'\n').encode()
        runnerpath=ROOT/'tools/run138_editor_readiness.py'
        runner=runnerpath.read_bytes().replace(digest(data).encode(),digest(encoded).encode(),1)
        with probe.substituted({str(helperpath):mutant,str(ROOT/READINESS_PATH):encoded,str(runnerpath):runner}):
            fresh=types.ModuleType('tools.club_customer_directory_admission');fresh.__file__=str(helperpath)
            exec(compile(mutant,str(helperpath),'exec'),fresh.__dict__)
            self.assertEqual(fresh.HELPER_SHA256,digest(mutant))
            with patch.object(toolspackage,'club_customer_directory_admission',fresh),patch.dict(sys.modules,{'tools.club_customer_directory_admission':fresh}),self.assertRaisesRegex(ValueError,'Unreviewed complete club helper input'):
                historical_readiness_contract(encoded)


    def test_creator_history_direct_script_entry_resolves_club_helper(self):
        import os
        import subprocess
        environment=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',PYTHONPATH=str(ROOT))
        name='CreatorFixed45TestPreservation.test_original_reviewed_creator_history_test_restores_complete_bytes'
        result=subprocess.run([sys.executable,str(ROOT/'tools/tests/test_creator_shelf_state_history.py'),name],cwd=ROOT,env=environment,capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('Ran 1 test',result.stderr)
        self.assertIn('OK',result.stderr)


if __name__ == '__main__':
    unittest.main()
