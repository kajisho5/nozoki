#!/usr/bin/env python3
"""動作確認用のサンプルzipを作る（名前はすべて架空）。

- sample-mac.zip   : Macの標準圧縮と同じく、UTF-8の印なしで日本語名を書いたzip
- sample-win.zip   : 日本語Windowsで作ったのと同じく、Shift_JISで日本語名を書いたzip
"""
import os
import sys
import zipfile

out = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(out, exist_ok=True)

files = {
    "CAM_A/clip_0001.mov": b"\x00" * 2048,
    "CAM_A/clip_0002.mov": b"\x01" * 4096,
    "AUDIO/収録_架空バンド.wav": b"RIFF" + b"\x00" * 1000,
    "撮影メモ.txt": "これは架空のテスト用メモです。\n".encode("utf-8"),
}


def write_zip(path, encode):
    """名前を placeholder で書いてから、生バイトを差し替える（Pythonの zipfile は Shift_JIS を書けないため）"""
    names = {}
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for i, (name, data) in enumerate(files.items()):
            raw = encode(name)
            placeholder = ("p%d_" % i).encode() + b"x" * (len(raw) - len("p%d_" % i))
            assert len(placeholder) == len(raw)
            names[placeholder] = raw
            info = zipfile.ZipInfo(placeholder.decode("ascii"), date_time=(2026, 9, 12, 14, 2, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
    blob = open(path, "rb").read()
    for placeholder, raw in names.items():
        assert blob.count(placeholder) == 2, placeholder  # ローカルヘッダと目次の2か所
        blob = blob.replace(placeholder, raw)
    open(path, "wb").write(blob)


write_zip(os.path.join(out, "sample-mac.zip"), lambda s: s.encode("utf-8"))
write_zip(os.path.join(out, "sample-win.zip"), lambda s: s.encode("cp932"))
print("作成:", os.listdir(out))
