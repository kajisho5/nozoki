#!/bin/bash
# ビルドしたアプリが「スペースキーで中身を見る」部品を正しく抱えているか確かめる
set -euo pipefail

APP="$1"
APPEX="$APP/Contents/PlugIns/NozokiPreview.appex"

echo "== 1. 本体と拡張があるか"
test -x "$APP/Contents/MacOS/nozoki"
test -d "$APPEX"
echo "OK"

echo "== 2. 拡張の設定（Finderのプレビューに差し込む設定になっているか）"
POINT=$(/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$APPEX/Contents/Info.plist")
DATA=$(/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionAttributes:QLIsDataBasedPreview" "$APPEX/Contents/Info.plist")
TYPES=$(/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionAttributes:QLSupportedContentTypes" "$APPEX/Contents/Info.plist")
echo "$POINT / data-based=$DATA"; echo "$TYPES"
[ "$POINT" = "com.apple.quicklook.preview" ]
[ "$DATA" = "true" ]
echo "$TYPES" | grep -q "public.zip-archive"

echo "== 3. 拡張がサンドボックス付きで署名されているか"
codesign -d --entitlements - "$APPEX" 2>/dev/null | tee /tmp/ent.txt
grep -q "com.apple.security.app-sandbox" /tmp/ent.txt
codesign --verify --deep --strict "$APP"
echo "OK"

echo "== 4. Macの仕組みに拡張として登録できるか"
pluginkit -a "$APPEX" || true
sleep 2
pluginkit -m -A -v -i com.kajisho5.nozoki.preview | tee /tmp/pk.txt
grep -q "com.kajisho5.nozoki.preview" /tmp/pk.txt

echo "== 5. 対応するmacOS"
/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist"
lipo -info "$APP/Contents/MacOS/nozoki"

echo "すべて確認できました"
