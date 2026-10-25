#!/bin/bash
# 公式の 7-Zip（Mac用コンソール版）を取ってきて Vendor/7zip/ に置く。
# 版とファイルの指紋（SHA-256）は固定。勝手に新しい版にはしない。
# 出典: https://7-zip.org/download.html → https://github.com/ip7z/7zip/releases
set -euo pipefail

VERSION="26.05"
FILE="7z2605-mac.tar.xz"
SHA256="12ef6830317743cfd3f0ab1724bde43fcc270d8b6d8564f8c12c2a2b7f993570"
URL="https://github.com/ip7z/7zip/releases/download/${VERSION}/${FILE}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/7zip"
mkdir -p "$DEST"

if [ -x "$DEST/7zz" ] && [ -f "$DEST/.version" ] && [ "$(cat "$DEST/.version")" = "$VERSION" ]; then
  echo "7-Zip $VERSION は取得済み"
  exit 0
fi

TMP="$(mktemp -d)"
curl -fsSL -o "$TMP/$FILE" "$URL"
echo "$SHA256  $TMP/$FILE" | shasum -a 256 -c -
tar -xf "$TMP/$FILE" -C "$TMP"
cp "$TMP/7zz" "$DEST/7zz"
chmod +x "$DEST/7zz"
cp "$TMP/License.txt" "$DEST/License.txt"
echo "$VERSION" > "$DEST/.version"
rm -rf "$TMP"
echo "7-Zip $VERSION を Vendor/7zip に置きました"
"$DEST/7zz" i | head -1 || true
