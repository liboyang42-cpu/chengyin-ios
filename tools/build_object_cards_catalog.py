#!/usr/bin/env python3
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
PAIRS = {
 'objects.title': ('Object cards', '物件卡'), 'objects.item': ('Object details', '物件详情'),
 'objects.login': ('Sign in to view your object cards', '登录后查看你的物件卡'),
 'objects.disabled': ('Object card reads are not enabled in this build', '此版本尚未启用物件卡读取'),
 'objects.limit': ('Showing up to the latest 40 cards per category', '每个分类最多显示最新40张物件卡'),
 'objects.loading': ('Loading', '加载中'), 'objects.failed': ('Could not load your cards', '无法加载物件卡'),
 'objects.filterFailed': ('Could not change the filter. Your previous cards are still shown.', '切换分类失败，仍显示上次加载的物件卡'),
 'objects.retry': ('Retry', '重试'), 'objects.total': ('Total in this category', '此分类总数'),
 'objects.empty': ('No cards in this category', '此分类暂无物件卡'),
 'objects.generating': ('Image generation is in progress', '图像正在生成中'),
 'objects.sessionChanged': ('Sign in again to reopen this item', '请重新登录后打开此物件'),
 'objects.framesHint': ('Swipe or use the buttons to view the available photo angles', '左右滑动或使用按钮查看已有照片角度'),
 'objects.previous': ('Previous angle', '上一个角度'), 'objects.next': ('Next angle', '下一个角度'),
 'objects.information': ('Information', '信息'), 'objects.name': ('Name', '名称'),
 'objects.category': ('Category', '分类'), 'objects.place': ('Place', '地点'),
 'objects.style': ('Card style', '卡片样式'), 'objects.plain': ('Plain', '普通'), 'objects.foil': ('Foil', '闪卡'),
 'objects.status': ('Generation status', '生成状态'), 'objects.source': ('Source image host', '来源图片域名'),
 'objects.mediaDisabled': ('Image loading is not enabled', '尚未启用图片加载'),
 'objects.mediaFailed': ('Image unavailable', '图片暂不可用'), 'objects.noImage': ('No preview image', '暂无预览图片'),
 'objects.enamel': ('Enamel style', '珐琅样式'), 'objects.glow': ('Glow style', '发光样式'),
 'objects.staticPreview': ('Static badge preview', '静态徽章预览'),
 'objects.offline': ('Synthetic offline example', '离线合成示例'),
}
for i, pair in enumerate(zip(['All','Electronics','Clothing','Shoes and bags','Food and drinks','Books and stationery','Toys and ornaments','Household items','Other'], ['全部','电子产品','服饰','鞋包','食物饮料','书籍文具','玩具摆件','日用杂物','其他'])):
    PAIRS[f'objects.category.{i}'] = pair
for i, pair in enumerate(zip(['Explore','Create','Organize','Connect','Co-create'], ['探索','创造','组织','连接','共创'])):
    PAIRS[f'objects.track.{i}'] = pair
for i, pair in enumerate(zip(['Common','Rare','Epic','Legendary','Mythic'], ['普通','稀有','史诗','传说','神话'])):
    PAIRS[f'objects.rarity.{i}'] = pair
catalog = {'sourceLanguage':'en', 'strings':{k:{'localizations':{lang:{'stringUnit':{'state':'translated','value':v}} for lang,v in zip(['en','zh-Hans'], values)}} for k, values in sorted(PAIRS.items())}, 'version':'1.0'}
path=ROOT/'Resources/ObjectCardLocalizations.fragment.json'
path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n')
print(f'{len(PAIRS)} bilingual keys written')
