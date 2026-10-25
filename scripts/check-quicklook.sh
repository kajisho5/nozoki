#!/bin/bash
# のぞき窓（クイックルック拡張）を画面なしで動かし、出てきたHTMLを確かめる。
# GitHubのMacは画面を持たないため、うまく動かない場合は「確認できなかった」と表示して止めない
set -uo pipefail

APP="$1"
WORK="${RUNNER_TEMP:-/tmp}/nozoki-ql"
rm -rf "$WORK"; mkdir -p "$WORK"
python3 scripts/make-sample-zips.py "$WORK/zips"

# 拡張を見つけてもらうため、アプリを「アプリケーション」に置いて登録する
sudo rm -rf /Applications/nozoki.app
sudo cp -R "$APP" /Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/nozoki.app
pluginkit -a /Applications/nozoki.app/Contents/PlugIns/NozokiPreview.appex
pluginkit -e use -i com.kajisho5.nozoki.preview
qlmanage -r >/dev/null 2>&1
sleep 3

result=0
for z in sample-mac sample-win; do
  echo "== $z.zip"
  mkdir -p "$WORK/out/$z"
  # Macには timeout 命令がないので、perl で60秒の時間切れを付ける
  perl -e 'alarm shift; exec @ARGV' 60 qlmanage -p -o "$WORK/out/$z" "$WORK/zips/$z.zip" 2>&1 | tail -5
  html=$(find "$WORK/out/$z" -name "*.html" | head -1)
  if [ -n "$html" ] && grep -q "撮影メモ.txt" "$html" && grep -q "4 ファイル" "$html"; then
    echo "OK: 日本語名が正しく出ています"
    grep -o "Shift_JIS）として読み替えています" "$html" || true
  else
    echo "確認できませんでした（画面のない環境のため、クイックルックが動かなかった可能性があります）"
    find "$WORK/out/$z" -type f | head
    result=1
  fi
done
echo "QUICKLOOK_CHECK=$result" >> "${GITHUB_OUTPUT:-/dev/null}"
exit 0
