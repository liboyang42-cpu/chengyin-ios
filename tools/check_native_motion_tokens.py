#!/usr/bin/env python3
"""motion-1118: QuestifyMotionToken must mirror docs/motion-tokens.json (copy of the mini-program table)."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EASE_NAMES = {'out': 'easeOut', 'standard': 'easeStandard', 'accelerate': 'easeAccelerate',
              'emphasizedDecelerate': 'easeEmphasizedDecelerate', 'spring': 'easeSpring', 'pageRise': 'easePageRise'}


def problems(root=ROOT):
    spec = json.loads((root / 'docs/motion-tokens.json').read_text())
    swift = (root / 'App/QuestifyMotion.swift').read_text()
    body = swift.split('enum QuestifyMotionToken {', 1)
    if len(body) != 2:
        return ['QuestifyMotionToken missing']
    body = body[1]
    out = []
    for name, ms in spec['durationMs'].items():
        m = re.search(r'static let %s: Double = ([0-9.]+)\n' % re.escape(name), body)
        if not m or abs(float(m.group(1)) * 1000 - ms) > 1e-6:
            out.append('duration %s != %sms' % (name, ms))
    for name, pts in spec['easing'].items():
        m = re.search(r'static let %s = \(([^)]*)\)' % EASE_NAMES[name], body)
        if not m or [float(x) for x in m.group(1).split(',')] != [float(x) for x in pts]:
            out.append('easing %s != %s' % (name, pts))
    motion = swift.split('enum QuestifyMotion {', 1)[1].split('\n}', 1)[0]
    if re.search(r'duration: \d', motion):
        out.append('QuestifyMotion must read QuestifyMotionToken, not literal durations')
    return out


if __name__ == '__main__':
    found = problems()
    for line in found:
        print('FAIL', line)
    print('motion tokens: %s' % ('FAIL' if found else 'OK'))
    sys.exit(1 if found else 0)
