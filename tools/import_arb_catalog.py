#!/usr/bin/env python3
"""Transfer explicitly selected, literal ARB strings into an Apple String Catalog.

No network or translation service. ICU plurals/select/placeholders are queued for
manual semantic conversion, never flattened into misleading literal text.
The output is a candidate, not automatic approval of wording or UI layout.
"""
import argparse, json, pathlib, re
import os
import tempfile

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON key: {key!r}')
        result[key] = value
    return result

def reject_constant(value):
    raise ValueError(f'non-JSON numeric constant: {value}')

def read_json(path):
    return json.loads(pathlib.Path(path).read_text(encoding='utf-8'),
                      object_pairs_hook=unique_object, parse_constant=reject_constant)

def read_arb(path):
    data=read_json(path)
    if not isinstance(data,dict): raise ValueError('ARB root must be an object')
    return data

def convert(english,chinese,keys):
    if not isinstance(keys, list) or any(not isinstance(key, str) or not key.strip()
                                        or key.startswith('@') for key in keys):
        raise ValueError('Select only non-metadata string keys')
    strings={}; review=[]
    for key in sorted(set(keys)):
        en,zh=english.get(key),chinese.get(key)
        metadata=[english.get('@'+key,{}),chinese.get('@'+key,{})]
        if any(not isinstance(m, dict) for m in metadata):
            raise ValueError(f'{key}: metadata must be an object')
        if any('placeholders' in m and not isinstance(m['placeholders'], dict) for m in metadata):
            raise ValueError(f'{key}: placeholders must be an object')
        if not all(isinstance(v,str) and v.strip() for v in [en,zh]):
            review.append({'key':key,'reason':'missing-or-empty-locale'});continue
        if any(isinstance(m,dict) and m.get('placeholders') for m in metadata) or any(re.search(r'[{}]',v) for v in [en,zh]):
            review.append({'key':key,'reason':'ICU-or-placeholder-semantic-review'});continue
        # Apple formatting uses percent placeholders; keep these out of the literal path.
        if any('%' in v for v in [en,zh]):
            review.append({'key':key,'reason':'percent-format-semantic-review'});continue
        strings[key]={'extractionState':'manual','localizations':{locale:{'stringUnit':{'state':'needs_review','value':value}} for locale,value in [('en',en),('zh-Hans',zh)]}}
    return {'sourceLanguage':'en','strings':strings,'version':'1.0'},review

def write_candidates(outputs):
    """Stage complete JSON before exclusive publication; rollback our own files on failure.

    The pair is not a filesystem transaction: a process crash can leave one candidate.
    Ordinary write/publication failures are cleaned up, without overwriting another
    writer. Staged hard links keep inode identities alive until cleanup completes.
    """
    encoded = [(pathlib.Path(path), (json.dumps(data, ensure_ascii=False, indent=2,
                 allow_nan=False) + '\n').encode('utf-8')) for path, data in outputs]
    if len({path.resolve() for path, _ in encoded}) != len(encoded):
        raise ValueError('Outputs must be distinct')
    staged = []
    published = []
    try:
        for path, payload in encoded:
            if path.exists() or path.is_symlink():
                raise FileExistsError(f'Output already exists: {path}')
            path.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(prefix='.arb-candidate-', dir=path.parent,
                                             delete=False) as stream:
                temporary = pathlib.Path(stream.name)
                staged.append((path, temporary))
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
        for path, temporary in staged:
            # Same-directory hard link is atomic and refuses existing files/symlinks.
            os.link(temporary, path)
            published.append((path, temporary.stat()))
    except BaseException:
        for path, identity in reversed(published):
            try:
                current = path.lstat()
                if (current.st_dev, current.st_ino) == (identity.st_dev, identity.st_ino):
                    path.unlink()
            except FileNotFoundError:
                pass
        raise
    finally:
        for _, temporary in staged:
            temporary.unlink(missing_ok=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--en',required=True,type=pathlib.Path)
    parser.add_argument('--zh',required=True,type=pathlib.Path)
    parser.add_argument('--keys',required=True,type=pathlib.Path,help='JSON array of reviewed keys selected for a migration slice')
    parser.add_argument('--output',required=True,type=pathlib.Path)
    parser.add_argument('--review-output',required=True,type=pathlib.Path)
    args=parser.parse_args()
    keys=read_json(args.keys)
    if not isinstance(keys,list): raise ValueError('Keys must be a JSON array')
    if args.output.resolve()==args.review_output.resolve(): raise ValueError('Outputs must be distinct')
    inputs={p.resolve() for p in [args.en,args.zh,args.keys]}
    if any(p.resolve() in inputs for p in [args.output,args.review_output]): raise ValueError('Output must not overwrite input')
    for p in [args.output,args.review_output]:
        if p.exists() or p.is_symlink(): raise ValueError(f'Output already exists: {p}; choose a new candidate path')
    catalog,review=convert(read_arb(args.en),read_arb(args.zh),keys)
    write_candidates([(args.output,catalog),(args.review_output,review)])
    print(f'{len(catalog["strings"])} candidate strings, {len(review)} queued for semantic review; no app resource changed')
if __name__=='__main__': main()
