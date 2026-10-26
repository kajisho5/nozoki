# ZipPeekMount

圧縮ファイルを Finder にドライブとしてつなぐ部品（Apple の FSKit、macOS 26 以降）。読み取り専用。
中のファイルは、開かれたときにそのファイルだけ取り出す。

- アプリの「その他」→「ドライブとして開く」は `/sbin/mount -F -t zippeek <圧縮ファイル> <つなぐ場所>` を実行する。
- Apple の決まりで、使う人が最初に一度「システム設定 → 一般 → ログイン項目と機能拡張 → ZipPeek の ⓘ → FSKit Modules」をオンにする。
- 配布版の署名には Developer ID 用プロファイルが要る（runway の mac-notarize の `profiles` 入力で自動で作って埋め込む）。
  権限（FSKit Module）は App Store Connect API では有効にできないので、Apple Developer の Identifiers で
  com.kajisho5.zippeek.mount に有効にしてある。
