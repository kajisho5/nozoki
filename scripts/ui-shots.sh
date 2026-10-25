#!/bin/bash
# GitHubのMacでアプリを起動し、画面の写真を撮る（人が見て確かめるため）。
# 写真は shots/ に入る。失敗しても止めずに、撮れたものだけ残す。
set -u
APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT="$2"
mkdir -p "$OUT" samples
python3 scripts/make-sample-zips.py samples > /dev/null
ID=com.kajisho5.zippeek
BIN="$APP/Contents/MacOS/ZipPeek"

shot() { sleep "${2:-4}"; screencapture -x "$OUT/$1.png" && echo "撮影: $1"; }
quit() { osascript -e 'tell application id "com.kajisho5.zippeek" to quit' 2>/dev/null; sleep 1; pkill -x ZipPeek; sleep 1; }
reset() { defaults delete $ID 2>/dev/null; defaults write $ID onArchiveDrop -string browse; }

echo "== 画面の大きさ"; system_profiler SPDisplaysDataType | grep -i resolution || true

for LANG_CODE in ja en; do
  for LOOK in light dark; do
    reset
    # ライト／ダークはMacの設定に合わせる作りなので、撮影用にMac全体の設定を切り替える
    if [ $LOOK = dark ]; then defaults write -g AppleInterfaceStyle -string Dark; else defaults delete -g AppleInterfaceStyle 2>/dev/null; fi
    # 1) 最初の窓（スペースキー機能の案内つき）
    "$BIN" -AppleLanguages "($LANG_CODE)" &
    shot "$LANG_CODE-$LOOK-1-drop" 6
    # 2) 中身を見る窓（Windowsで作った日本語名のzip）
    open -a "$APP" samples/sample-win.zip
    shot "$LANG_CODE-$LOOK-2-browse" 5
    # 3) 設定
    osascript -e 'tell application id "com.kajisho5.zippeek" to activate' -e 'tell application "System Events" to keystroke "," using command down' 2>/dev/null
    shot "$LANG_CODE-$LOOK-3-settings" 3
    quit
  done
done

defaults delete -g AppleInterfaceStyle 2>/dev/null
# 4) 小窓（ガラス）
reset
defaults write $ID dropStyle -string compactGlass
"$BIN" -AppleLanguages "(ja)" &
shot "ja-light-4-compact" 6
quit

# 5) Finderのスペースキー（クイックルック）
pluginkit -a "$APP/Contents/PlugIns/ZipPeekPreview.appex" 2>/dev/null
qlmanage -r > /dev/null 2>&1
( qlmanage -p samples/sample-win.zip > "$OUT/qlmanage.log" 2>&1 & )
shot "quicklook" 6
pkill -x qlmanage

# 6) アイコンの各見た目（Xcode付属の Icon Composer の道具で描く）
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [ -x "$ICTOOL" ]; then
  "$ICTOOL" --help > "$OUT/ictool-help.txt" 2>&1
  for R in Default Dark ClearLight ClearDark TintedLight TintedDark; do
    "$ICTOOL" ZipPeek/Resources/AppIcon.icon --export-image --output-file "$OUT/icon-$R.png" \
      --platform macOS --rendition "$R" --width 512 --height 512 --scale 1 >> "$OUT/ictool.log" 2>&1 && echo "アイコン: $R"
  done
else
  echo "ictool が見つかりません: $ICTOOL"
fi
ls -la "$OUT"
