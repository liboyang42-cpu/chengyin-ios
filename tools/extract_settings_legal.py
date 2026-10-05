#!/usr/bin/env python3
"""Exact local-source extraction only. Does not approve, translate, or update legal text."""
import argparse, hashlib, json, pathlib, re

STRING = r"'((?:\\.|[^'\\])*)'"
def decode(value):
    # Source currently uses only newlines/backslashes/escaped quotes; reject unknown escapes.
    def replace(match):
        escape = match.group(1)
        if escape not in {'n', 'r', 't', "'", '\\'}:
            raise ValueError(f'Unsupported Dart escape: {escape}')
        return {'n':'\n', 'r':'\r', 't':'\t', "'":"'", '\\':'\\'}[escape]
    return re.sub(r'\\(.)', replace, value)

def extract(path):
    source = path.read_text()
    source = re.sub(r'//[^\n]*', '', source)
    docs = []
    for name, body in re.findall(r'LegalDocType\.(\w+):\s*LegalDoc\((.*?)(?=\n\s*LegalDocType\.|\n};)', source, re.S):
        def field(key):
            match = re.search(r'\b'+key+r':\s*'+STRING, body)
            return decode(match.group(1)) if match else None
        sections = [(decode(h), decode(p)) for h, p in re.findall(r'LegalSection\(\s*'+STRING+r',\s*'+STRING+r',?\s*\)', body, re.S)]
        docs.append(dict(type=name, title=field('title'), version=field('version'), effectiveDate=field('updatedAt'), intro=field('intro'), sections=sections))
    assert [d['type'] for d in docs] == ['userAgreement','privacyPolicy','cancellationNotice']
    assert [len(d['sections']) for d in docs] == [13, 0, 5]
    return docs

def render(docs):
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    out = ['// Generated verbatim from app-audit/lib/feature/legal/legal_docs.dart. Do not paraphrase.',
           '// CN source reference only: app privacy policy and US-market documents are missing.',
           'import Foundation', '', 'public enum SettingsSourceLegalCatalog {',
           '    public static func document(type: SettingsLegalType, market: RegionalMarket?) -> SettingsLegalAvailability {',
           '        guard let market else { return .missing(.missingMarket) }',
           '        guard market == .china else { return .missing(.regionalTextNotProvided) }',
           '        switch type {',
           '        case .userAgreement: return .sourceDocument(userAgreement)',
           '        case .cancellationNotice: return .sourceDocument(cancellationNotice)',
           '        case .privacyPolicy: return .missing(.pendingSourceText)', '        }', '    }']
    for doc in docs:
        if not doc['sections']: continue
        out += [f'    public static let {doc["type"]} = SettingsLegalDocument(',
                f'        type: .{doc["type"]}, title: {quote(doc["title"])}, version: {quote(doc["version"])},',
                f'        effectiveDate: {quote(doc["effectiveDate"])}, intro: {quote(doc["intro"])},',
                '        sections: [']
        for heading, body in doc['sections']:
            out.append(f'            .init(heading: {quote(heading)}, body: {quote(body)}),')
        out += ['        ])']
    out += ['}', '']
    return '\n'.join(out)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    expected = render(extract(args.source))
    if args.check:
        assert args.output.read_text() == expected, 'Legal text differs from local Dart source'
        print('PASS exact legal-source text and metadata parity: 13 + 5 sections; privacy remains missing')
    else: args.output.write_text(expected)
if __name__ == '__main__': main()
