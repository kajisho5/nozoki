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

shot() { sleep "${2:-4}"; screencapture -x -m "$OUT/$1.png" && echo "撮影: $1"; }
quit() { osascript -e 'tell application id "com.kajisho5.zippeek" to quit' 2>/dev/null; sleep 1; pkill -x ZipPeek; sleep 1; }
reset() { defaults delete $ID 2>/dev/null; defaults write $ID onArchiveDrop -string browse; }

echo "== 画面の大きさ"; system_profiler SPDisplaysDataType | grep -i resolution || true
# 高精細（2倍表示）の仮想ディスプレイを作り、そこを主画面にして撮る。写真がくっきりする
brew install displayplacer > /dev/null 2>&1 || true
if clang -fobjc-arc -framework Foundation -framework CoreGraphics scripts/hidpi-display.m -o /tmp/hidpi-display 2> "$OUT/hidpi-build.log"; then
  /tmp/hidpi-display > /tmp/hidpi-id.txt 2> "$OUT/hidpi-run.log" &
  sleep 4
  displayplacer list > "$OUT/displays.txt" 2>&1 || true
  VID=$(awk '/Persistent screen id:/ {id=$4} /Type: .*virtual|ZipPeek/ {print id; exit}' "$OUT/displays.txt")
  [ -n "$VID" ] || VID=$(awk '/Persistent screen id:/ {id=$4} /Scaling: on/ {print id; exit}' "$OUT/displays.txt")
  PID_MAIN=$(awk '/Persistent screen id:/ {print $4; exit}' "$OUT/displays.txt")
  echo "仮想ディスプレイ: ${VID:-見つからない}"
  if [ -n "$VID" ] && [ "$VID" != "$PID_MAIN" ]; then
    # 仮想ディスプレイを主画面（原点）にし、元の画面はその右に置く
    displayplacer "id:$VID res:1280x800 scaling:on origin:(0,0) degree:0" "id:$PID_MAIN origin:(1280,0) degree:0" \
      && echo "主画面を仮想ディスプレイに" || echo "配置の変更に失敗"
    sleep 3
    displayplacer list > "$OUT/displays-after.txt" 2>&1 || true
  fi
fi
system_profiler SPDisplaysDataType | grep -iE "resolution|retina|ui looks like|main display" || true

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
# 4) 小窓（ガラス）— 英語と日本語
for LANG_CODE in en ja; do
  reset
  defaults write $ID dropStyle -string compactGlass
  "$BIN" -AppleLanguages "($LANG_CODE)" &
  shot "$LANG_CODE-light-4-compact" 6
  quit
done

# 5) Finderのスペースキー（クイックルック）— Mac全体の言語を切り替えて英語・日本語で撮る
pluginkit -a "$APP/Contents/PlugIns/ZipPeekPreview.appex" 2>/dev/null
for LANG_CODE in en ja; do
  defaults write -g AppleLanguages -array "$LANG_CODE"
  killall cfprefsd 2>/dev/null || true
  qlmanage -r > /dev/null 2>&1
  ( qlmanage -p samples/sample-win.zip > "$OUT/qlmanage-$LANG_CODE.log" 2>&1 & )
  shot "quicklook-$LANG_CODE" 6
  pkill -x qlmanage
done
defaults delete -g AppleLanguages 2>/dev/null || true

# 7) ダブルクリックで開く：利用者と同じく「アプリケーション」に入れ、zip の既定のアプリを ZipPeek にして、Finder から開く
defaults delete $ID 2>/dev/null
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
sudo rm -rf /Applications/ZipPeek.app && sudo ditto "$APP" /Applications/ZipPeek.app
"$LSREG" -u "$APP" 2>/dev/null; "$LSREG" -f /Applications/ZipPeek.app
APP=/Applications/ZipPeek.app
cat > /tmp/setdef.swift <<'SWIFT'
import AppKit
import UniformTypeIdentifiers
let app = URL(fileURLWithPath: CommandLine.arguments[1])
let done = DispatchSemaphore(value: 0)
NSWorkspace.shared.setDefaultApplication(at: app, toOpen: .zip) { error in
    print(error.map { "既定のアプリの変更に失敗: \($0)" } ?? "既定のアプリを変更した")
    done.signal()
}
if done.wait(timeout: .now() + 30) == .timedOut { print("時間切れ（Mac の確認の画面が出ている可能性）") }
print("zip を開くアプリ: " + (NSWorkspace.shared.urlForApplication(toOpen: .zip)?.path ?? "なし"))
SWIFT
swift /tmp/setdef.swift "$APP" 2>&1 | tee "$OUT/default-app.log"
shot "default-app-prompt" 1
# Mac の確認画面の「“ZipPeek”を使用」を押す（利用者が押すのと同じ。画面中央の上のボタン）
cat > /tmp/click.swift <<'SWIFT'
import CoreGraphics
import Foundation
let p = CGPoint(x: Double(CommandLine.arguments[1])!, y: Double(CommandLine.arguments[2])!)
for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(150_000)
}
SWIFT
swift /tmp/click.swift 640 334 2>&1 | tee -a "$OUT/default-app.log"
sleep 3
cat > /tmp/getdef.swift <<'SWIFT'
import AppKit
import UniformTypeIdentifiers
print("zip を開くアプリ（押した後）: " + (NSWorkspace.shared.urlForApplication(toOpen: .zip)?.path ?? "なし"))
SWIFT
swift /tmp/getdef.swift 2>&1 | tee -a "$OUT/default-app.log"
shot "default-app-after" 1
# 注：この Mac ではスクリプトから Finder に「開く」をさせられない（ふつうのテキストでも失敗する）ため、
# Finder のダブルクリックそのものは試せない。下で「Dock 以外からの開く」を確かめる
# 「このアプリケーションで開く」と同じ開き方（送り主は Dock 以外）でも、中身を見る窓が開くか
defaults delete $ID 2>/dev/null
open -a "$APP" samples/sample-win.zip
shot "en-light-6-openwith" 6
quit

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
