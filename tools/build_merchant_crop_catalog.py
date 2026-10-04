#!/usr/bin/env python3
"""Merge bounded merchant crop strings, preserving unrelated entries."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
entries = {
    'image.crop.logo': ('Crop logo · 1:1', '裁剪标志 · 1:1'),
    'image.crop.gallery': ('Crop gallery photo · 16:9', '裁剪相册照片 · 16:9'),
    'image.crop.cover': ('Crop cover · 5:3', '裁剪封面 · 5:3'),
    'image.crop.localOnly': ('Adjust the crop, then review before uploading. Nothing has been sent.', '调整裁剪后，再预览并确认上传。尚未发送任何内容。'),
    'image.crop.preview': ('Cropped photo preview', '裁剪照片预览'),
    'image.crop.horizontal': ('Horizontal position', '水平位置'),
    'image.crop.vertical': ('Vertical position', '垂直位置'),
    'image.crop.zoom': ('Zoom', '缩放'),
    'image.crop.confirm': ('Use crop and review upload', '使用裁剪并预览上传'),
}
fragment = {'sourceLanguage': 'en', 'strings': {key: {'localizations': {language: {'stringUnit': {'state': 'translated', 'value': value}} for language, value in zip(['en', 'zh-Hans'], values)}} for key, values in entries.items()}, 'version': '1.0'}
(root / 'Resources/MerchantImageCropLocalizations.fragment.json').write_text(json.dumps(fragment, ensure_ascii=False, indent=2) + '\n')
path = root / 'Resources/Localizable.xcstrings'
data = json.loads(path.read_text()); data['strings'].update(fragment['strings'])
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
print(f'PASS merged {len(entries)} merchant crop strings')
