#!/usr/bin/env python3
"""Bilingual keys for the w2-10 growth/badge/object-card/stamp parity additions.

Writes Resources/W210GrowthBadgeStampLocalizations.fragment.json and merges the same
keys key-wise into Resources/Localizable.xcstrings (and growth.* into the growth doc
catalog). Re-running is idempotent; other keys and their order are untouched.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAIRS = {
    'growth.denied': ('This account cannot view growth records. Check its access and refresh.', '当前账号无法查看成长记录，请确认当前账号的查看权限'),
    'growth.badges.newlyLit': ('New badges lit', '新徽章已点亮'),
    'growth.board.meTag': ('Me', '我'),
    'growth.board.podium.first': ('First place', '第一名'),
    'growth.board.podium.second': ('Second place', '第二名'),
    'growth.board.podium.third': ('Third place', '第三名'),
    'badgeWall.summary %lld %lld %lld': ('%1$lld of %2$lld lit · %3$lld still waiting to be explored', '已点亮 %1$lld / %2$lld · 还有 %3$lld 枚等待探索'),
    'badgeWall.focus.onWall %@': ('“%@” is on your wall', '「%@」已在墙上'),
    'badgeWall.focus.locked %@': ('“%@” is not lit yet', '「%@」还没点亮'),
    'badgeWall.focus.elsewhere': ('This badge is not an identity card; it is recorded in the growth center', '这枚不是身份卡，记在成长中心'),
    'badgeWall.explore': ('Go explore', '去探索'),
    'badgeWall.threeD.open': ('View 3D badge', '查看 3D 徽章'),
    'objectCards.denied': ('This account cannot view this collection. Go back and open it again.', '当前账号无法查看，请返回后重新进入'),
    'objectCards.emptyAll': ('You have not collected anything yet', '还没有收过东西'),
    'objectCards.emptyHint': ('Photograph an item at a node you have played; once it passes review it is collected here', '在玩过的节点里拍一件东西，判过就收进这里'),
    'stampAlbum.total %lld': ('Stamps: %lld', '%lld 枚'),
    'stampAlbum.denied': ('This account cannot view this album. Go back and open it again.', '当前账号无法查看，请返回后重新进入'),
    'stampAlbum.openCamera': ('Open stamp camera', '打开集邮相机'),
}


def entry(en, zh):
    return {'extractionState': 'manual', 'localizations': {
        'en': {'stringUnit': {'state': 'translated', 'value': en}},
        'zh-Hans': {'stringUnit': {'state': 'translated', 'value': zh}}}}


def main():
    fragment = {key: entry(*PAIRS[key]) for key in sorted(PAIRS)}
    (ROOT / 'Resources/W210GrowthBadgeStampLocalizations.fragment.json').write_text(
        json.dumps(fragment, ensure_ascii=False, indent=2) + '\n')
    path = ROOT / 'Resources/Localizable.xcstrings'
    catalog = json.loads(path.read_text())
    for key, value in fragment.items():
        catalog['strings'][key] = value
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    growth_path = ROOT / 'docs/growth-center-localizations.json'
    growth = json.loads(growth_path.read_text())
    for key, (en, zh) in PAIRS.items():
        if key.startswith('growth.'):
            growth[key] = {'en': en, 'zh-Hans': zh}
    growth_path.write_text(json.dumps(growth, ensure_ascii=False, indent=2))
    print(f'{len(PAIRS)} bilingual keys merged')


if __name__ == '__main__':
    main()
