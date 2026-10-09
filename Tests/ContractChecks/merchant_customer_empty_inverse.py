"""Exact inverse for the additive customer-empty recovery layer; no test weakening."""
import hashlib

BASE_SHA256 = 'a5f8c2e225acada297e818142fb300a36d2a5e89c640be7b977ff82f2bcd3cd9'
POST_SHA256 = '551056768b2568c0c931fb3f21eb2e18320ee0ea2c5ff94a2f28baba26c54215'
HISTORICAL_SHA256 = {'ae07cfbd1250e1f9e9209c70d7bb84073ce21388c51fd25f04348f6773048af3', '9591a8fd9cebf903e7bf4b10c914e6fa3aa907b3823d48c737c89521a94e3b05', '2a4f0c0ba5164317d66542ae8d7da9baec4ba632fcb316f8344973c135c17cdd', 'f046c2d5705e65575c1c014f43e688e09a790dab51f2e84d32a441e5b4c7d5a6', '4f08ea22b3cb52a245e9147f057f8fa9d4c0b0297286a0c560db6fd9f3269353', 'a5f8c2e225acada297e818142fb300a36d2a5e89c640be7b977ff82f2bcd3cd9', '3fe571bd94ccc4813c7a89c6f7c1a8363343fbcfa623a4a3837fd0ec3f7bc1c1'}
BYTE_HUNKS = [(14390, b'    if case .customers(let filter) = query {\n            _keyword = State(initialValue: filter.keyword); _segment = State(initialValue: filter.segment)\n            _sourceType = State(initialValue: filter.sourceType ?? 0); _tagID = State(initialValue: filter.tagID ?? 0)\n            _sourceStart = State(initialValue: filter.sourceStart ?? ""); _sourceEnd = State(initialValue: filter.sourceEnd ?? "")\n        }\n    ', b''), (16828, b' if let recovery = MerchantCustomerEmptyRecovery(document: snapshot.document) {\n                    let draftMatches = recovery.matchesDraft(keyword: keyword, segment: segment, sourceType: sourceType,\n                                                             tagID: tagID, sourceStart: sourceStart, sourceEnd: sourceEnd)\n                    MerchantCustomerEmptyRecoverySection(recovery: recovery, canApply: !state.isBusy && state.failureKey == nil && query == snapshot.document.query && draftMatches,\n                                                         hasUnsubmittedFilters: !draftMatches) {\n                        guard state.isCurrent, !state.isBusy, state.failureKey == nil, state.snapshot == snapshot,\n                              query == snapshot.document.query,\n                              recovery.matchesDraft(keyword: keyword, segment: segment, sourceType: sourceType,\n                                                    tagID: tagID, sourceStart: sourceStart, sourceEnd: sourceEnd),\n                              let next = recovery.recoveredQuery else { return }\n                        keyword = next.keyword; segment = next.segment\n                        sourceType = next.sourceType ?? 0; tagID = next.tagID ?? 0\n                        sourceStart = next.sourceStart ?? ""; sourceEnd = next.sourceEnd ?? ""\n                        query = .customers(next); selection = []\n                        Task { await reload() }\n                    }\n                } else', b'')]

def before_customer_empty_source(source):
    raw = source.encode('utf-8')
    digest = hashlib.sha256(raw).hexdigest()
    if digest in HISTORICAL_SHA256:
        return source
    if digest != POST_SHA256:
        raise ValueError('Unknown customer-empty source or changed existing boundary')
    for offset, current, previous in reversed(BYTE_HUNKS):
        if raw[offset:offset + len(current)] != current:
            raise ValueError('Missing, moved or changed customer-empty hunk')
        raw = raw[:offset] + previous + raw[offset + len(current):]
    if hashlib.sha256(raw).hexdigest() != BASE_SHA256:
        raise ValueError('Changed source outside customer-empty recovery')
    return raw.decode('utf-8')
