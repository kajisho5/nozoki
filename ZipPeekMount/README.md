# ZipPeekMount（試作・未同梱）

圧縮ファイルを Finder にドライブとしてつなぐ部品（Apple の FSKit、macOS 26 以降）。読み取り専用。
アプリにはまだ入れていない。理由：

- FSKit の部品には Apple の特別な権限（com.apple.developer.fskit.fsmodule）が要り、配布用の署名（Developer ID）では
  その権限を書いた「プロファイル」を部品に埋め込む必要がある。今の署名の仕組み（runway）はプロファイルを扱っていない。
- 本物の Mac（GitHub のテスト機）で、署名なしの試作をシステム設定でオンにしようとしたが、スイッチが切り替わらなかった
  （「Module com.kajisho5.zippeek.mount is disabled!」）。

入れるときは `python3 scripts/enable-mount.py` を実行してから `xcodegen generate`（project.yml に部品を足す）。
