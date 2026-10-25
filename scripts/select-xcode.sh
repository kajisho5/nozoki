#!/bin/bash
# GitHubのMacに入っているXcodeのうち、正式版（beta/RCでない）の一番新しいものを選ぶ
set -euo pipefail

echo "入っているXcode:"
ls -d /Applications/Xcode*.app || true

pick=$(ls -d /Applications/Xcode_*.app 2>/dev/null \
  | grep -viE 'beta|rc|release_candidate' \
  | sed -E 's#^/Applications/Xcode_([0-9.]+)\.app$#\1 &#' \
  | grep -E '^[0-9]' \
  | sort -V | tail -1 | cut -d' ' -f2)

if [ -z "${pick:-}" ]; then
  pick=/Applications/Xcode.app
fi

echo "使うXcode: $pick"
sudo xcode-select -s "$pick/Contents/Developer"
xcodebuild -version
swift --version
