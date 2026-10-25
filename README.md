<p align="center"><img src="docs/icon.png" width="128" alt="ZipPeek icon"></p>

<h1 align="center">ZipPeek</h1>

<p align="center">
Macの圧縮・解凍。そして、展開せずにのぞく。<br>
Compress and extract on your Mac — and peek inside without extracting.
</p>

<p align="center"><a href="#日本語">日本語</a> ・ <a href="#english">English</a></p>

---

## 日本語

### できること

- **ドラッグで、すぐ**：Dockのアイコンや窓にファイルを落とすと圧縮、圧縮ファイルを落とすと解凍。Finderの右クリック（「ZipPeekで圧縮／解凍／中身を見る」）からも使えます
- **展開せずにのぞく**：Finderでzipを選んでスペースキーを押すと、中身の一覧が出ます。zipの末尾にある「目次」だけを読むので、30GBでも一瞬です
- **1ファイルだけ取り出す**：中身を見る窓で選んで「取り出す」。デスクトップへのドラッグでも書き出せます
- **たくさんの形式**：zip・7z・rar・tar・gz・bz2・xz・zst・iso・lzh・cab など（中身の処理に [7-Zip](https://www.7-zip.org/) を同梱）
- **圧縮の設定**：zip・7z、パスワード（AES-256）、分割、圧縮率、Mac専用の隠しファイルを入れない
- **文字化けしない**：日本語Windowsで作ったzip（Shift_JIS）の名前を自動判定。逆に、Windowsで文字化けしないzipも作れます
- **見た目**：ライト／ダーク、標準の窓／ガラスの小窓を設定で切り替え（macOS 26以降はLiquid Glass）
- **日本語・英語**：Macの言語設定に合わせて切り替わります

### 入れ方

1. [リリース](https://github.com/kajisho5/zippeek/releases) から `ZipPeek-*.dmg` をダウンロード
2. dmgを開き、ZipPeek を「アプリケーション」フォルダへドラッグ
3. ZipPeek を一度起動し、表示される案内に沿って「スペースキーで中身を見る」機能をオン

zipをダブルクリックしたときは、これまでどおりMacの標準の解凍が動きます。ZipPeekで開きたいときは、右クリック →「このアプリケーションで開く」→ ZipPeek。

### 動作環境

macOS 14（Sonoma）以降、Apple シリコン / Intel

### できないこと

- rar形式での圧縮（rarの作成は開発元以外には許されていないため。解凍はできます）
- 圧縮ファイルの中身の書き換え

---

## English

### Features

- **Drop to go**: drop files on the Dock icon or the window to compress, drop archives to extract. Also available from Finder's right-click menu (Compress / Extract / Look Inside with ZipPeek).
- **Peek without extracting**: select a ZIP in Finder and press Space to see what's inside. Only the archive's table of contents is read, so even 30 GB archives open instantly.
- **Take out just one file**: pick files in the browser window and extract them, or drag them to the Desktop.
- **Many formats**: zip, 7z, rar, tar, gz, bz2, xz, zst, iso, lzh, cab and more (powered by the bundled [7-Zip](https://www.7-zip.org/)).
- **Compression options**: zip or 7z, AES-256 passwords, splitting, compression level, leave out Mac-only hidden files.
- **No garbled names**: Japanese file names from Windows (Shift_JIS) are detected automatically, and you can create ZIPs that open cleanly on Japanese Windows.
- **Your look**: light / dark, standard window or compact glass drop target (Liquid Glass on macOS 26+).
- **Japanese and English**, following your Mac's language.

### Install

1. Download `ZipPeek-*.dmg` from [Releases](https://github.com/kajisho5/zippeek/releases)
2. Open it and drag ZipPeek into Applications
3. Launch ZipPeek once and follow the prompt to turn on "Press Space to look inside"

### Requirements

macOS 14 (Sonoma) or later, Apple silicon or Intel.

---

## 開発 / Development

Macが無くても開発できるよう、Xcodeのプロジェクトは `project.yml` から [XcodeGen](https://github.com/yonaskolb/XcodeGen) で作ります。

```sh
bash scripts/fetch-7zip.sh   # 7-Zip 26.05 を取得（版と指紋は固定）
brew install xcodegen
xcodegen generate
open ZipPeek.xcodeproj
```

| 場所 / Path | 中身 / Contents |
| --- | --- |
| `Packages/ZipPeekCore` | 目次の読み取り・文字コード判定・圧縮・解凍（テスト付き） / archive engine with tests |
| `ZipPeek/` | アプリ本体（SwiftUI） / the app |
| `ZipPeekPreview/` | Finderのスペースキー用の拡張 / Quick Look extension |
| `site/` | 配布ページ / website |

テスト / Tests: `cd Packages/ZipPeekCore && ZIPPEEK_7ZZ=../../Vendor/7zip/7zz swift test`

## ライセンス / License

ZipPeek: MIT License

同梱 / Bundled:
- [7-Zip](https://www.7-zip.org/) 26.05 by Igor Pavlov — GNU LGPL + BSD 3-clause + unRAR restriction（[Vendor/7zip/License.txt](Vendor/7zip/License.txt)）
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 0.9.20 — MIT
