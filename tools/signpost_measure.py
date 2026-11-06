#!/usr/bin/env python3
"""I10 before/after Points of Interest measurement for a real iPhone.

Records, exports and summarizes the static `Questify.Performance` signposts
declared in Core/NativePerformanceSignposts.swift. Cloud runs can only test the
parser with synthetic XML; recording needs macOS, Xcode and a connected device.
Traces and summaries are local evidence: do not commit them, and keep them apart
from synthetic UI-test screenshots.

  python3 tools/signpost_measure.py record --device <UDID> --output before.trace
  python3 tools/signpost_measure.py export --input before.trace --output before.xml
  python3 tools/signpost_measure.py summarize before.xml --label before > before.json
  python3 tools/signpost_measure.py compare before.json after.json
"""
import argparse
import json
import pathlib
import platform
import re
import statistics
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
SUBSYSTEM = 'Questify.Performance'


def catalog():
    """Read point names from the Swift source so the script cannot drift from it."""
    source = (ROOT / 'Core/NativePerformanceSignposts.swift').read_text()
    enum = source.split('public enum NativePerformancePoint', 1)[1].split('public enum Area', 1)[0]
    return re.findall(r'case \w+ = "([^"]+)"', enum)


def require_macos():
    if platform.system() != 'Darwin':
        raise SystemExit('xctrace needs macOS with Xcode and a connected, unlocked iPhone.')


def record(args):
    require_macos()
    command = ['xcrun', 'xctrace', 'record', '--template', args.template, '--device', args.device,
               '--time-limit', args.time_limit, '--output', args.output]
    command += ['--attach', args.attach] if args.attach else ['--all-processes']
    print('+ ' + ' '.join(command), file=sys.stderr)
    return subprocess.call(command)


def export(args):
    require_macos()
    toc = subprocess.run(['xcrun', 'xctrace', 'export', '--input', args.input, '--toc'],
                         check=True, capture_output=True, text=True).stdout
    schemas = sorted({table.get('schema') for table in ET.fromstring(toc).iter('table')
                      if 'signpost' in (table.get('schema') or '')})
    if not schemas:
        raise SystemExit('No signpost tables in this trace; record with a template that includes os_signpost.')
    root = ET.Element('signpost-export')
    for schema in schemas:
        xpath = f'/trace-toc/run[@number="{args.run}"]/data/table[@schema="{schema}"]'
        data = subprocess.run(['xcrun', 'xctrace', 'export', '--input', args.input, '--xpath', xpath],
                              check=True, capture_output=True, text=True).stdout
        if data.strip():
            root.append(ET.fromstring(data))
    pathlib.Path(args.output).write_bytes(ET.tostring(root))
    print(f'Exported {len(schemas)} signpost table(s): {", ".join(schemas)}', file=sys.stderr)
    return 0


def intervals(xml_text, names):
    """Yield (name, milliseconds) for completed Questify.Performance intervals.

    xctrace writes repeated values once with id= and later as ref=; resolve both.
    Column tags vary across Xcode versions, so match values, not element names.
    """
    root = ET.fromstring(xml_text)
    by_id = {}
    for element in root.iter():
        if element.get('id') is not None:
            by_id[element.get('id')] = element

    def resolve(element):
        target = by_id.get(element.get('ref'), element) if element.get('ref') is not None else element
        return target

    def texts(element):
        element = resolve(element)
        values = [element.get('fmt') or '', (element.text or '').strip()]
        for child in element:
            values += texts(child)
        return [value for value in values if value]

    for row in root.iter('row'):
        cells = [resolve(cell) for cell in row]
        values = [value for cell in cells for value in texts(cell)]
        if SUBSYSTEM not in values:
            continue
        name = next((value for value in values if value in names), None)
        duration = next((cell for cell in cells if cell.tag == 'duration'), None)
        if name is None or duration is None or not (duration.text or '').strip().isdigit():
            continue
        yield name, int(duration.text.strip()) / 1_000_000


def summarize_text(xml_texts, label):
    names = catalog()
    samples = {name: [] for name in names}
    for text in xml_texts:
        for name, milliseconds in intervals(text, set(names)):
            samples[name].append(milliseconds)
    points = {}
    for name, values in samples.items():
        values.sort()
        points[name] = {'count': len(values)} if not values else {
            'count': len(values),
            'median_ms': round(statistics.median(values), 3),
            'p95_ms': round(values[min(len(values) - 1, int(round(0.95 * (len(values) - 1))))], 3),
            'max_ms': round(values[-1], 3)}
    return {'label': label, 'subsystem': SUBSYSTEM, 'points': points,
            'note': 'Device evidence only when exported from a real-iPhone trace; record device, iOS and build.'}


def summarize(args):
    texts = [pathlib.Path(path).read_text() for path in args.exports]
    print(json.dumps(summarize_text(texts, args.label), indent=2, sort_keys=True))
    return 0


def compare_summaries(before, after):
    rows = []
    for name in catalog():
        a, b = before['points'].get(name, {}), after['points'].get(name, {})
        if not a.get('count') or not b.get('count'):
            rows.append((name, a.get('count', 0), b.get('count', 0), None, None))
            continue
        rows.append((name, a['count'], b['count'], a['median_ms'], b['median_ms']))
    return rows


def compare(args):
    before = json.loads(pathlib.Path(args.before).read_text())
    after = json.loads(pathlib.Path(args.after).read_text())
    print(f'{"point":28} {"n before":>8} {"n after":>8} {"median before":>14} {"median after":>13}')
    for name, n_before, n_after, m_before, m_after in compare_summaries(before, after):
        fmt = lambda value: '-' if value is None else f'{value:.3f}'
        print(f'{name:28} {n_before:>8} {n_after:>8} {fmt(m_before):>14} {fmt(m_after):>13}')
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    p = commands.add_parser('record'); p.set_defaults(run=record)
    p.add_argument('--device', required=True); p.add_argument('--output', required=True)
    p.add_argument('--template', default='Logging'); p.add_argument('--time-limit', default='90s')
    p.add_argument('--attach', default='Questify')
    p = commands.add_parser('export'); p.set_defaults(run=export)
    p.add_argument('--input', required=True); p.add_argument('--output', required=True)
    p.add_argument('--run', default='1')
    p = commands.add_parser('summarize'); p.set_defaults(run=summarize)
    p.add_argument('exports', nargs='+'); p.add_argument('--label', required=True)
    p = commands.add_parser('compare'); p.set_defaults(run=compare)
    p.add_argument('before'); p.add_argument('after')
    args = parser.parse_args(argv)
    return args.run(args)


if __name__ == '__main__':
    sys.exit(main())
