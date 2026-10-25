#!/usr/bin/env python3
"""GitHubのMacで撮った画面写真（scripts/ui-shots.sh の shots/）から、配布ページとREADME用の画像を切り出す。
使い方: python3 scripts/site-shots.py <shotsフォルダ>
出力: site/public/shots/{en,ja}/{browse,quicklook,drop,compact}.png と docs/images/*.png（英語）"""
import os, sys
from PIL import Image, ImageDraw

src = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def bbox(img):
    # 黒い壁紙・上のメニューバー・下のDockを除いて、窓のある範囲を探す
    reg = img.crop((0, 31, img.width, 700)).convert('L').point(lambda v: 255 if v > 8 else 0)
    b = reg.getbbox()
    return (b[0], b[1] + 31, b[2], b[3] + 31)


def cut(name, box, dst, radius, top=0):
    path = os.path.join(src, name + '.png')
    if not os.path.exists(path):
        print('なし:', name)
        return
    img = Image.open(path).convert('RGBA')
    box = box or bbox(img)
    box = (box[0], box[1] + top, box[2], box[3])
    im = img.crop(box)
    mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius, fill=255)
    im.putalpha(mask)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    im.save(dst, optimize=True)
    print(dst, im.size)


for lang in ('en', 'ja'):
    out = os.path.join(root, 'site/public/shots', lang)
    cut(f'{lang}-light-2-browse', (12, 41, 1012, 681), f'{out}/browse.png', 26)
    cut(f'{lang}-light-1-drop', None, f'{out}/drop.png', 22)
    cut(f'{lang}-light-4-compact', None, f'{out}/compact.png', 60)
    # クイックルックは上の帯（qlmanage の確認用の表示）を除く
    cut(f'quicklook-{lang}', None, f'{out}/quicklook.png', 22, top=41)

docs = os.path.join(root, 'docs/images')
for n in ('browse', 'quicklook', 'drop', 'compact'):
    p = os.path.join(root, 'site/public/shots/en', n + '.png')
    if os.path.exists(p):
        Image.open(p).save(os.path.join(docs, n + '.png'), optimize=True)
