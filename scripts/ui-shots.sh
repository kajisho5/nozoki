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

# 先の試験（python の試験用サーバー）が出した「ローカルネットワーク」の確認が残っていると写真に写るので閉じる
swift scripts/ui-test.swift allow || true

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

# 8) 本物の操作で試す：Finder でダブルクリック／Finder から Dock のアイコンへドラッグ
T="swift scripts/ui-test.swift"
LOG="$OUT/ui-test.log"
$T trusted | tee -a "$LOG"
$T allow | tee -a "$LOG"   # 先の試験（python のサーバー）が出した確認が残っていたら閉じる
quit
defaults delete $ID 2>/dev/null; defaults write $ID hasSeenWelcome -bool true
rm -rf ~/Desktop/zp-click ~/Desktop/zp-drop; mkdir -p ~/Desktop/zp-click ~/Desktop/zp-drop
cp samples/sample-mac.zip ~/Desktop/zp-click/; cp samples/sample-win.zip ~/Desktop/zp-drop/

# 8a) Finder でダブルクリック → 中身を見る窓が開くはず
open ~/Desktop/zp-click; sleep 4
P=$($T pos com.apple.finder sample-mac.zip); echo "Finder の zip の位置: $P" | tee -a "$LOG"
if [ -n "$P" ] && [ "$P" != "見つからない" ]; then
  $T doubleclick $P; sleep 7
  shot "test-1-finder-doubleclick" 1
  $T windows com.kajisho5.zippeek | tee "$OUT/ui-test-windows-1.txt"
  if grep -q "sample-mac.zip" "$OUT/ui-test-windows-1.txt"; then echo "合格: ダブルクリックで中身を見る窓が開いた" | tee -a "$LOG"
  else echo "不合格: ダブルクリックで中身を見る窓が開かなかった" | tee -a "$LOG"; fi
  test ! -e ~/Desktop/zp-click/sample-mac && echo "合格: ダブルクリックでは解凍していない" | tee -a "$LOG"
fi
quit

# 8b) Finder から Dock のアイコンへドラッグ → すぐ解凍されるはず
open -a "$APP"; sleep 5
osascript -e 'tell application "Finder" to activate' 2>/dev/null || true
open ~/Desktop/zp-drop; sleep 4
F=$($T pos com.apple.finder sample-win.zip); D=$($T pos com.apple.dock ZipPeek)
echo "Finder の zip: $F / Dock の ZipPeek: $D" | tee -a "$LOG"
if [ -n "$F" ] && [ -n "$D" ] && [ "$F" != "見つからない" ] && [ "$D" != "見つからない" ]; then
  $T drag $F $D; sleep 8
  shot "test-2-dock-drop" 1
  ls -la ~/Desktop/zp-drop | tee -a "$LOG"
  if [ -d ~/Desktop/zp-drop/sample-win ]; then echo "合格: Dock へのドラッグで解凍した" | tee -a "$LOG"
  else echo "不合格: Dock へのドラッグで解凍されなかった" | tee -a "$LOG"; fi
  $T windows com.kajisho5.zippeek | tee "$OUT/ui-test-windows-2.txt"
  grep -q "sample-win.zip" "$OUT/ui-test-windows-2.txt" && echo "注意: ドラッグで中身を見る窓が開いた" | tee -a "$LOG"
fi
quit

# 9) 0.3.0 の機能：7z のスペースキー表示、窓へのドラッグで追加、選んで削除
Z="$APP/Contents/MacOS/7zz"
rm -rf ~/Desktop/zp-7z && mkdir -p ~/Desktop/zp-7z/架空の撮影/RAW
echo "架空の台本です" > ~/Desktop/zp-7z/架空の撮影/台本.txt
head -c 300000 /dev/urandom > ~/Desktop/zp-7z/架空の撮影/RAW/clip_0101.mov
(cd ~/Desktop/zp-7z && LC_ALL=en_US.UTF-8 "$Z" a -bso0 -bsp0 sample.7z 架空の撮影)
quit
osascript -e 'tell application "Finder" to close every window' 2>/dev/null || true
qlmanage -r > /dev/null 2>&1
( qlmanage -p ~/Desktop/zp-7z/sample.7z > "$OUT/qlmanage-7z.log" 2>&1 & )
shot "quicklook-7z" 6
shot "quicklook-7z-later" 10
pkill -x qlmanage
# うまく出ないときの手がかり（スペースキーの部品と 7-Zip の記録）
log show --last 2m --style compact --predicate 'process CONTAINS "ZipPeekPreview" OR process == "7zz" OR (process == "kernel" AND eventMessage CONTAINS "7zz") OR eventMessage CONTAINS "ZipPeekPreview"' \
  > "$OUT/quicklook-7z-log.txt" 2>&1 || true

quit
defaults delete $ID 2>/dev/null; defaults write $ID hasSeenWelcome -bool true
rm -rf ~/Desktop/zp-edit ~/Desktop/zp-src && mkdir -p ~/Desktop/zp-edit ~/Desktop/zp-src
cp samples/sample-mac.zip ~/Desktop/zp-edit/edit.zip
echo "追加のテスト" > ~/Desktop/zp-src/追加テスト.txt
osascript -e 'tell application "Finder" to close every window' 2>/dev/null || true
open -a "$APP" ~/Desktop/zp-edit/edit.zip; sleep 5
$T move com.kajisho5.zippeek 0 40 760 560
open ~/Desktop/zp-src; sleep 3
$T move com.apple.finder 790 120 480 360; sleep 1
F=$($T pos com.apple.finder 追加テスト.txt)
echo "追加するファイルの位置: $F" | tee -a "$LOG"
if [ -n "$F" ] && [ "$F" != "見つからない" ]; then
  # shellcheck disable=SC2086
  $T drag $F 380 330; sleep 3
  shot "test-3-add-confirm" 1
  A=$($T pos com.kajisho5.zippeek Add); [ "$A" = "見つからない" ] && A=$($T pos com.kajisho5.zippeek 追加); echo "「追加」ボタン: $A" | tee -a "$LOG"
  # shellcheck disable=SC2086
  [ -n "$A" ] && [ "$A" != "見つからない" ] && $T click $A
  sleep 6
  shot "test-4-added" 1
  if LC_ALL=en_US.UTF-8 "$Z" l -ba ~/Desktop/zp-edit/edit.zip | grep -q "追加テスト.txt"; then echo "合格: 窓へのドラッグで zip に追加できた" | tee -a "$LOG"
  else echo "不合格: 窓へのドラッグで zip に追加できなかった" | tee -a "$LOG"; fi
fi
R=$($T pos com.kajisho5.zippeek 撮影メモ.txt); echo "削除する行: $R" | tee -a "$LOG"
if [ -n "$R" ] && [ "$R" != "見つからない" ]; then
  # shellcheck disable=SC2086
  $T click $R; sleep 1
  $T key 51; sleep 2
  shot "test-5-delete-confirm" 1
  B=$($T pos com.kajisho5.zippeek Delete); [ "$B" = "見つからない" ] && B=$($T pos com.kajisho5.zippeek 削除); echo "「削除」ボタン: $B" | tee -a "$LOG"
  # shellcheck disable=SC2086
  [ -n "$B" ] && [ "$B" != "見つからない" ] && $T click $B
  sleep 6
  shot "test-6-deleted" 1
  if LC_ALL=en_US.UTF-8 "$Z" l -ba ~/Desktop/zp-edit/edit.zip | grep -q "撮影メモ.txt"; then echo "不合格: 削除できなかった" | tee -a "$LOG"
  else echo "合格: 選んで削除できた" | tee -a "$LOG"; fi
  LC_ALL=en_US.UTF-8 "$Z" l -ba ~/Desktop/zp-edit/edit.zip | tee -a "$LOG"
fi
quit

# 10) 0.4.0 の機能：リンクのままのぞく、中の zip を開く、壊れていないかの確認、中で名前変更
T="swift scripts/ui-test.swift"
LOG="$OUT/ui-test.log"
quit
defaults delete $ID 2>/dev/null; defaults write $ID hasSeenWelcome -bool true
osascript -e 'tell application "Finder" to close every window' 2>/dev/null || true
rm -rf ~/zp-web && mkdir -p ~/zp-web && cp samples/sample-mac.zip ~/zp-web/web-sample.zip
python3 scripts/range-server.py ~/zp-web 8765 > /dev/null 2>&1 &
SERVER=$!
sleep 3
$T allow | tee -a "$LOG"
printf 'http://127.0.0.1:8765/web-sample.zip' | pbcopy
open -a "$APP"; sleep 5
$T press $ID "Look Inside a Link…" "リンクのままのぞく…" | tee -a "$LOG"
shot "test-7-link-dialog" 2
$T press $ID "Look Inside" "中身を見る" | tee -a "$LOG"
sleep 5
$T windows $ID | tee "$OUT/ui-test-windows-3.txt"
if grep -q "web-sample.zip" "$OUT/ui-test-windows-3.txt"; then echo "合格: リンクのまま zip の中身を開けた" | tee -a "$LOG"
else echo "不合格: リンクのまま開けなかった" | tee -a "$LOG"; fi
shot "test-8-link-window" 1
kill $SERVER 2>/dev/null
quit

# 中の zip を開く（ダブルクリック）
rm -rf ~/Desktop/zp-nest && mkdir -p ~/Desktop/zp-nest
(cd samples && "$Z" a -bso0 -bsp0 ~/Desktop/zp-nest/outer.zip sample-mac.zip)
open -a "$APP" ~/Desktop/zp-nest/outer.zip; sleep 5
$T move $ID 0 40 900 600
P=$($T pos $ID sample-mac.zip); echo "中の zip の行: $P" | tee -a "$LOG"
if [ -n "$P" ] && [ "$P" != "見つからない" ]; then
  # shellcheck disable=SC2086
  $T doubleclick $P; sleep 6
  $T windows $ID | tee "$OUT/ui-test-windows-4.txt"
  if grep -q "^sample-mac.zip" "$OUT/ui-test-windows-4.txt"; then echo "合格: 中の zip を、別の窓で開けた" | tee -a "$LOG"
  else echo "不合格: 中の zip が開かなかった" | tee -a "$LOG"; fi
  shot "test-9-nested" 1
fi
quit

# 壊れていないかの確認と、中で名前変更
rm -rf ~/Desktop/zp-tool && mkdir -p ~/Desktop/zp-tool && cp samples/sample-mac.zip ~/Desktop/zp-tool/tool.zip
open -a "$APP" ~/Desktop/zp-tool/tool.zip; sleep 5
$T move $ID 0 40 900 600
$T dump $ID > "$OUT/ax-tool-window.txt" 2>&1
$T press $ID "More" "その他" | tee -a "$LOG"; sleep 1
$T press $ID "Check for Damage" "壊れていないか確かめる" | tee -a "$LOG"
sleep 6
shot "test-10-verify" 1
if $T has $ID "No Problems Found" "問題は見つかりませんでした" > /dev/null; then echo "合格: 壊れていないかの確認で「問題なし」と出た" | tee -a "$LOG"
else echo "不合格: 確認の結果が出なかった" | tee -a "$LOG"; fi
$T key 36; sleep 1   # return で閉じる
R=$($T pos $ID 撮影メモ.txt); echo "名前を変える行: $R" | tee -a "$LOG"
if [ -n "$R" ] && [ "$R" != "見つからない" ]; then
  # shellcheck disable=SC2086
  $T click $R; sleep 1
  $T press $ID "More" "その他" | tee -a "$LOG"; sleep 1
  $T dump $ID > "$OUT/ax-more-menu.txt" 2>&1
  $T press $ID "Rename…" "名前を変更…" | tee -a "$LOG"; sleep 2
  $T dump $ID > "$OUT/ax-rename.txt" 2>&1
  $T set $ID "台本.txt" "New name" "新しい名前" | tee -a "$LOG"; sleep 1
  shot "test-11-rename" 1
  $T press $ID "Rename" "名前を変更" | tee -a "$LOG"; sleep 6
  if LC_ALL=en_US.UTF-8 "$Z" l -ba ~/Desktop/zp-tool/tool.zip | grep -q "台本.txt"; then echo "合格: 中で名前を変えられた" | tee -a "$LOG"
  else echo "不合格: 名前が変わらなかった" | tee -a "$LOG"; fi
  LC_ALL=en_US.UTF-8 "$Z" l -ba ~/Desktop/zp-tool/tool.zip | tee -a "$LOG"
fi
quit

# 11) 試し：ドライブとしてつなぐ部品（ZipPeekMount）は、入っているときだけ試す
if [ -d "$APP/Contents/Extensions/ZipPeekMount.appex" ]; then
F="$OUT/fskit.txt"
# FSKit の部品は「システム設定 → 一般 → ログイン項目と機能拡張 → ファイルシステム拡張」で使う人が一度オンにする。
# その画面を開いて、部品の一覧を記録する（自動でオンにする手順を探すため）
open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"; sleep 6
shot "fskit-settings-1" 1
$T dump com.apple.systempreferences > "$OUT/ax-settings-1.txt" 2>&1
# 「機能拡張」の一覧で ZipPeek の行の ⓘ を押し、出てきた画面でファイルシステム拡張をオンにする
$T pressafter com.apple.systempreferences "ZipPeek" AXButton | tee -a "$LOG"; sleep 3
shot "fskit-settings-2" 1
$T dump com.apple.systempreferences > "$OUT/ax-settings-2.txt" 2>&1
# スイッチは本物のクリックでないと切り替わらないので、位置を調べてクリックする
SW=$($T pressafter com.apple.systempreferences "FSKit Modules" AXCheckBox pos); echo "ファイルシステム拡張のスイッチ: $SW" | tee -a "$LOG"
# shellcheck disable=SC2086
[ -n "$SW" ] && [ "$SW" != "見つからない" ] && $T click $SW
sleep 3
$T allow | tee -a "$LOG"   # 確認が出たら許可
sleep 2
shot "fskit-settings-3" 1
$T dump com.apple.systempreferences > "$OUT/ax-settings-3.txt" 2>&1
$T press com.apple.systempreferences "Done" "完了" | tee -a "$LOG"; sleep 1
{
  echo "== 部品の登録"
  pluginkit -m -A -v -p com.apple.fskit.fsmodule 2>&1
  pluginkit -e use -i com.kajisho5.zippeek.mount 2>&1 && echo "有効にした"
  pluginkit -m -A -v -i com.kajisho5.zippeek.mount 2>&1
  codesign -d --entitlements - "$APP/Contents/Extensions/ZipPeekMount.appex" 2>&1
  echo "== つなぐ"
  rm -rf ~/zp-mnt && mkdir -p ~/zp-mnt && cp samples/sample-mac.zip ~/zp-mount-src.zip
  mount -t zippeek ~/zp-mount-src.zip ~/zp-mnt 2>&1; echo "終了コード $?"
  mount | grep -i zippeek
  ls -laR ~/zp-mnt 2>&1 | head -40
  cat ~/zp-mnt/撮影メモ.txt 2>&1 | head -5
  umount ~/zp-mnt 2>&1
} > "$F" 2>&1
if grep -q "架空" "$F"; then echo "合格: ドライブとしてつないで中身を読めた" | tee -a "$LOG"; else echo "未達: ドライブとしてつなげなかった（記録は fskit.txt）" | tee -a "$LOG"; fi
log show --last 4m --style compact --predicate 'process CONTAINS "ZipPeekMount" OR process == "fskitd" OR process == "fskit_agent" OR eventMessage CONTAINS "zippeek.mount"' > "$OUT/fskit-log.txt" 2>&1 || true

fi

# 落ちたときの記録（あれば）
mkdir -p "$OUT/crash"
cp ~/Library/Logs/DiagnosticReports/ZipPeek* "$OUT/crash/" 2>/dev/null || true
ls "$OUT/crash"

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
