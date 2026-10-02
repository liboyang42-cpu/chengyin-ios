#!/usr/bin/env python3
"""Merge reviewed module keys into the catalog; run only after integrating this slice."""
import json
from pathlib import Path
import argparse
p=argparse.ArgumentParser(); p.add_argument('catalog',type=Path); args=p.parse_args()
source=Path(__file__).with_name('template-authoring-localizations.json')
entries=json.loads(source.read_text()); catalog=json.loads(args.catalog.read_text())
for key,langs in entries.items():
 catalog.setdefault('strings',{})[key]={'localizations':{lang:{'stringUnit':{'state':'translated','value':value}} for lang,value in langs.items()}}
args.catalog.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
