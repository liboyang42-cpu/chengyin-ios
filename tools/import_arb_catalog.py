#!/usr/bin/env python3
"""Transfer explicitly selected, literal ARB strings into an Apple String Catalog.

No network or translation service. ICU plurals/select/placeholders are queued for
manual semantic conversion, never flattened into misleading literal text.
The output is a candidate, not automatic approval of wording or UI layout.
"""
import argparse, json, pathlib, re

def read_arb(path):
    data=json.loads(pathlib.Path(path).read_text(encoding='utf-8'))
    if not isinstance(data,dict): raise ValueError('ARB root must be an object')
    return data

def convert(english,chinese,keys):
    strings={}; review=[]
    for key in sorted(set(keys)):
        if not isinstance(key,str) or not key or key.startswith('@'):
            raise ValueError('Select only non-metadata string keys')
        en,zh=english.get(key),chinese.get(key)
        metadata=[english.get('@'+key,{}),chinese.get('@'+key,{})]
        if not all(isinstance(v,str) and v.strip() for v in [en,zh]):
            review.append({'key':key,'reason':'missing-or-empty-locale'});continue
        if any(isinstance(m,dict) and m.get('placeholders') for m in metadata) or any(re.search(r'[{}]',v) for v in [en,zh]):
            review.append({'key':key,'reason':'ICU-or-placeholder-semantic-review'});continue
        # Apple formatting uses percent placeholders; keep these out of the literal path.
        if any('%' in v for v in [en,zh]):
            review.append({'key':key,'reason':'percent-format-semantic-review'});continue
        strings[key]={'extractionState':'manual','localizations':{locale:{'stringUnit':{'state':'needs_review','value':value}} for locale,value in [('en',en),('zh-Hans',zh)]}}
    return {'sourceLanguage':'en','strings':strings,'version':'1.0'},review

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--en',required=True,type=pathlib.Path)
    parser.add_argument('--zh',required=True,type=pathlib.Path)
    parser.add_argument('--keys',required=True,type=pathlib.Path,help='JSON array of reviewed keys selected for a migration slice')
    parser.add_argument('--output',required=True,type=pathlib.Path)
    parser.add_argument('--review-output',required=True,type=pathlib.Path)
    args=parser.parse_args()
    keys=json.loads(args.keys.read_text())
    if not isinstance(keys,list): raise ValueError('Keys must be a JSON array')
    if args.output.resolve()==args.review_output.resolve(): raise ValueError('Outputs must be distinct')
    inputs={p.resolve() for p in [args.en,args.zh,args.keys]}
    if any(p.resolve() in inputs for p in [args.output,args.review_output]): raise ValueError('Output must not overwrite input')
    for p in [args.output,args.review_output]:
        if p.exists(): raise ValueError(f'Output already exists: {p}; choose a new candidate path')
    catalog,review=convert(read_arb(args.en),read_arb(args.zh),keys)
    for p,data in [(args.output,catalog),(args.review_output,review)]:
        p.parent.mkdir(parents=True,exist_ok=True)
        with p.open('x',encoding='utf-8') as f: json.dump(data,f,ensure_ascii=False,indent=2);f.write('\n')
    print(f'{len(catalog["strings"])} candidate strings, {len(review)} queued for semantic review; no app resource changed')
if __name__=='__main__': main()
