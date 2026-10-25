#!/bin/bash
# ビルドしたアプリが「スペースキーで中身を見る」部品を正しく抱えているか確かめる
set -euo pipefail

APP="$1"
APPEX="$APP/Contents/PlugIns/ZipPeekPreview.appex"

echo "== 1. 本体と拡張があるか"
test -x "$APP/Contents/MacOS/ZipPeek"
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
pluginkit -m -A -v -i com.kajisho5.zippeek.preview | tee /tmp/pk.txt
grep -q "com.kajisho5.zippeek.preview" /tmp/pk.txt

echo "== 5. 7-Zip が同梱され、動くか"
test -x "$APP/Contents/MacOS/7zz"
"$APP/Contents/MacOS/7zz" i | head -1
test -f "$APP/Contents/Resources/7-Zip/License.txt"
codesign --verify --strict "$APP/Contents/MacOS/7zz"
# スペースキーの部品には 7zz を入れない（サンドボックスの中では起動できないため、libarchive で読む）
test ! -e "$APPEX/Contents/MacOS/7zz"
echo "OK"

echo "== 6. 右クリック（サービス）と言語"
/usr/libexec/PlistBuddy -c "Print :NSServices" "$APP/Contents/Info.plist" | grep -E "NSMessage" 
test "$(/usr/libexec/PlistBuddy -c "Print :NSServices" "$APP/Contents/Info.plist" | grep -c NSMessage)" = "3"
/usr/libexec/PlistBuddy -c "Print :CFBundleLocalizations" "$APP/Contents/Info.plist"
test -f "$APP/Contents/Resources/en.lproj/ServicesMenu.strings"
test -f "$APP/Contents/Resources/ja.lproj/ServicesMenu.strings"
echo "OK"

echo "== 7. 対応するmacOS"
/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist"
lipo -info "$APP/Contents/MacOS/ZipPeek"

echo "== 8. アプリアイコン（Icon Composer形式から作られたか。古いmacOS用のicnsもあるか）"
test -f "$APP/Contents/Resources/Assets.car"
test -f "$APP/Contents/Resources/AppIcon.icns"
test ! -e "$APP/Contents/Resources/AppIcon.icon"
/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$APP/Contents/Info.plist"
echo "OK"

echo "== 9. 日本語の訳（文字列カタログ）が入っているか"
LOC="$APP/Contents/Resources/ja.lproj/Localizable.strings"
test -f "$LOC"
plutil -p "$LOC" | grep -F '"Extract All" => "すべて取り出す"'
plutil -p "$LOC" | grep -F '"Compress %lld items" => "%lld 個の項目を圧縮"'
echo "OK"

echo "== 10. アプリの版番号が project.yml と同じか（アップデートの比較に使うため）"
WANT=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\}.*/\1/p' project.yml | head -1)
GOT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
GOT_EXT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APPEX/Contents/Info.plist")
echo "project.yml: $WANT / アプリ: $GOT / 拡張: $GOT_EXT"
[ "$GOT" = "$WANT" ] && [ "$GOT_EXT" = "$WANT" ]
echo "OK"

echo "すべて確認できました"
