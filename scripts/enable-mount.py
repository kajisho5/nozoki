#!/usr/bin/env python3
"""試作の「ドライブとしてつなぐ」部品（ZipPeekMount）を project.yml に足す。xcodegen generate の前に実行する。"""
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
p = root / "project.yml"
s = p.read_text(encoding="utf-8")
if "ZipPeekMount:" in s:
    print("すでに入っている")
    raise SystemExit
dep = "      - target: ZipPeekPreview\n        embed: true\n"
assert dep in s
s = s.replace(dep, dep + "      - target: ZipPeekMount\n        embed: true\n", 1)
target = (root / "ZipPeekMount" / "target.yml").read_text(encoding="utf-8").split("\n", 1)[1]
s = s.rstrip("\n") + "\n\n" + target
p.write_text(s, encoding="utf-8")
print("ZipPeekMount を足した")
