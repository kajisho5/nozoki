#!/usr/bin/env python3
"""コードの中の文言と、文字列カタログ（日本語訳）が食い違っていないか確かめる。
xcodebuild -exportLocalizations が書き出した XLIFF を読み、日本語訳のない文言があれば失敗にする。
使い方: python3 scripts/check-localizations.py <書き出し先フォルダ>"""
import pathlib, sys, xml.etree.ElementTree as ET

root = pathlib.Path(sys.argv[1])
xliffs = list(root.rglob("*.xliff"))
if not xliffs:
    sys.exit("XLIFF が見つかりません")
ns = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
missing = []
for x in xliffs:
    for f in ET.parse(x).getroot().findall("x:file", ns):
        orig = f.get("original", "")
        if "Localizable" not in orig:
            continue
        for tu in f.iter("{urn:oasis:names:tc:xliff:document:1.2}trans-unit"):
            target = tu.find("x:target", ns)
            if target is None or not (target.text or "").strip() or target.get("state") in ("new", "needs-translation"):
                missing.append(tu.get("id"))
print(f"日本語訳がない文言: {len(missing)} 件")
for m in missing:
    print("  ", m)
sys.exit(1 if missing else 0)
