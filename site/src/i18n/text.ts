// 配布ページの文言（英語が主、日本語は /ja/）。他社製品の名前は入れない。
// 確かめていない速さの数字（「◯GBでも◯秒」など）は書かない。
export const repo = 'https://github.com/kajisho5/zippeek';
export const site = 'https://kajisho5.github.io/zippeek';
export const sponsors = 'https://github.com/sponsors/kajisho5';

export const extractFormats = ['zip', '7z', 'rar', 'tar', 'gz', 'bz2', 'xz', 'zst', 'iso', 'lzh', 'cab', 'arj', 'cpio', 'wim', 'xar', 'rpm', 'deb'];
export const createFormats = ['zip', '7z'];

export type IconName = 'extract' | 'drop' | 'menu' | 'kana' | 'stack' | 'lock';

const en = {
  lang: 'en',
  path: '/',
  title: 'ZipPeek — Compress and extract on your Mac, and peek inside without extracting',
  description:
    'Free, open-source archiver for Mac. Press Space in Finder to see what’s in a ZIP, take out just the file you need, and read Japanese file names from Windows correctly.',
  nav: { features: 'Features', how: 'How it works', formats: 'Formats', faq: 'FAQ', download: 'Download', other: '日本語', otherHref: '/zippeek/ja/', skip: 'Skip to content' },
  hero: {
    eyebrow: 'Free · Open source · macOS 14+',
    title: ['Peek inside.', 'Take out only what you need.'],
    lead: 'Press Space in Finder to see what’s in a ZIP — without extracting it. Compress, extract, and stop fighting garbled Japanese file names.',
    download: 'Download for Mac',
    github: 'View on GitHub',
    meta: 'Apple silicon & Intel · Signed and notarized',
    shotAlt: 'The ZipPeek window showing a ZIP made on Japanese Windows. Its folders and file names are listed correctly, with an Extract All button in the toolbar.',
  },
  peek: {
    eyebrow: 'Space to peek',
    title: 'See inside without extracting anything.',
    body: 'Select a ZIP, 7z, rar or tar in Finder and press Space. Folders, file names and sizes appear in a Quick Look preview, with no temporary files.',
    chip: 'Built into Finder',
    shotAlt: 'Quick Look preview of a ZIP in Finder, listing two folders and their files with sizes and dates.',
  },
  features: {
    title: 'Everything an archiver should do',
    items: [
      { icon: 'extract', title: 'Double-click to look inside', body: 'Like on Windows: double-click a ZIP and its contents open. Drag files out to extract, drag files in to add, press Delete to remove.' },
      { icon: 'drop', title: 'Drop to go', body: 'Drop on the Dock icon: files are compressed, archives are extracted.' },
      { icon: 'menu', title: 'Right-click in Finder', body: 'Compress, Extract and Look Inside — no window needed.' },
      { icon: 'kana', title: 'No garbled names', body: 'Shift_JIS names from Windows are detected. Make ZIPs that open cleanly on Japanese Windows.' },
      { icon: 'stack', title: 'Many formats', body: 'zip, 7z, rar, tar, iso, lzh and more, powered by the bundled 7-Zip. The Space key works for 7z, rar and tar too.' },
      { icon: 'lock', title: 'Passwords & split', body: 'AES-256, hidden file names in 7z, and splitting into 2 GB or DVD-sized parts.' },
    ] as { icon: IconName; title: string; body: string }[],
  },
  how: {
    eyebrow: 'How it works',
    title: 'Why big archives open fast',
    lead: 'A ZIP keeps its table of contents at the very end. ZipPeek reads only that part — not the file data.',
    data: 'File data — not read',
    toc: 'Contents',
    tocNote: 'Read: the contents list only',
    result: 'The file list, without unpacking',
  },
  encoding: {
    eyebrow: 'No garbled names',
    title: 'Made on Windows? Still readable.',
    lead: 'Japanese Windows writes ZIP file names in Shift_JIS. Read the wrong way, they turn into nonsense.',
    without: 'Without detection',
    withZipPeek: 'ZipPeek (auto: Shift_JIS)',
  },
  mac: {
    title: 'Made for the Mac',
    lead: 'Standard toolbar and menus · VoiceOver · Reduce Motion · Liquid Glass on macOS 26 · light & dark follow your Mac',
    windowAlt: 'The ZipPeek drop window with Choose and Look Inside buttons and a guide to turning on the Space-key preview.',
    compactAlt: 'The compact glass drop target: a small rounded square with the ZipPeek icon and “Drop here”.',
    compactCaption: 'Compact glass drop target',
    styleTitle: 'Choose your style',
    styleBody: 'A standard window, or a tiny glass target that stays out of the way.',
  },
  formats: { title: 'Formats', extract: 'Extract', create: 'Create', note: 'Creating rar isn’t possible (only its developer may make rar archives); extracting works.' },
  install: {
    title: 'Install in a minute',
    steps: [
      { title: 'Download the dmg', body: 'From the latest release on GitHub.' },
      { title: 'Drag to Applications', body: 'Like any other Mac app.' },
      { title: 'Turn on double-click & Space', body: 'Launch ZipPeek once and press the buttons in the first window.' },
    ],
  },
  faq: {
    title: 'FAQ',
    items: [
      { q: 'Is it really free?', a: 'Yes. ZipPeek is open source under the MIT License.' },
      { q: 'Does it update itself?', a: 'Yes, from version 0.2. ZipPeek checks once a day, asks before updating, and installs only updates signed by the same developer. Version 0.1.0 can’t do this, so please download the latest version once.' },
      { q: 'Why do I need to turn on the Space-key preview?', a: 'macOS asks you to approve new Quick Look extensions once. ZipPeek shows whether it’s on and opens System Settings for you.' },
      { q: 'Does the Space key work for 7z and rar?', a: 'Yes, from version 0.3: zip, 7z, rar and tar (including .tar.gz). Other formats open in the ZipPeek window: right-click → Look Inside with ZipPeek.' },
      { q: 'Can I add or remove files inside a ZIP?', a: 'Yes, from version 0.3, for zip and 7z. Drag files into the ZipPeek window (or click Add Files…) to add them; select items and press Delete to remove them. ZipPeek asks before changing the archive. Password-protected and split archives can’t be changed.' },
      { q: 'My ZIP came from Windows and the names look broken.', a: 'ZipPeek detects Shift_JIS names automatically. If the guess is wrong, switch it with File Name Encoding in the toolbar.' },
      { q: 'Will ZIPs I make open on Windows?', a: 'Yes. For Japanese names, turn on “Japanese Windows–friendly names” when compressing.' },
      { q: 'Does ZipPeek send my files anywhere?', a: 'No. Everything happens on your Mac. There are no accounts and no analytics.' },
    ],
  },
  cta: { title: 'Peek before you unpack.', lead: 'Free and open source. macOS 14 or later.', download: 'Download for Mac' },
  support: { title: 'Support ZipPeek', body: 'ZipPeek is free and will stay free. If it saves you time, please consider sponsoring its development on GitHub — monthly or one-time, any amount helps.', button: 'Sponsor on GitHub' },
  footer: {
    links: [
      { label: 'GitHub', href: repo },
      { label: 'Sponsor', href: 'https://github.com/sponsors/kajisho5' },
      { label: 'Releases', href: `${repo}/releases` },
      { label: 'README', href: `${repo}#readme` },
      { label: '7-Zip license', href: 'https://www.7-zip.org/license.txt' },
    ],
    privacy: 'Privacy: ZipPeek works entirely on your Mac and never sends your files anywhere. This site uses no cookies or analytics.',
    credit: '© 2026 Shogo Kajiyama · MIT License · Compression powered by 7-Zip by Igor Pavlov (GNU LGPL)',
  },
};

type Text = typeof en;

const ja: Text = {
  lang: 'ja',
  path: '/ja/',
  title: 'ZipPeek ─ Macの圧縮・解凍。展開せずに中身をのぞく',
  description:
    'Mac用の無料・オープンソースの圧縮・解凍アプリ。Finderでスペースキーを押せばzipの中身が見えて、必要な1ファイルだけ取り出せます。Windowsで作ったzipの日本語名も文字化けしません。',
  nav: { features: '機能', how: 'しくみ', formats: '対応形式', faq: 'よくある質問', download: 'ダウンロード', other: 'English', otherHref: '/zippeek/', skip: '本文へ移動' },
  hero: {
    eyebrow: '無料 ・ オープンソース ・ macOS 14 以降',
    title: ['展開せずに、のぞく。', '必要なものだけ取り出す。'],
    lead: 'Finderでスペースキーを押せば、zipの中身が見えます。圧縮も解凍も、Windowsで作ったzipの文字化けも、これひとつで。',
    download: 'Mac版をダウンロード',
    github: 'GitHubで見る',
    meta: 'Apple シリコン / Intel ・ Appleの公証済み',
    shotAlt: 'ZipPeekの中身を見る窓。日本語Windowsで作ったzipのフォルダとファイル名が正しく表示され、ツールバーに「すべて取り出す」ボタンがある。',
  },
  peek: {
    eyebrow: 'スペースキーでのぞく',
    title: '何も展開せずに、中が見える。',
    body: 'Finderでzip・7z・rar・tarを選んでスペースキー。フォルダ・ファイル名・大きさがクイックルックで一覧になります。一時ファイルも作りません。',
    chip: 'Finderにそのまま',
    shotAlt: 'Finderでzipを選んでスペースキーを押したときの表示。2つのフォルダと中のファイルが、大きさと日付つきで並んでいる。',
  },
  features: {
    title: '圧縮・解凍に必要なことは、ぜんぶ',
    items: [
      { icon: 'extract', title: 'ダブルクリックで中身を見る', body: 'Windowsと同じように、zipをダブルクリックすれば中身が開きます。ドラッグで取り出し、ドラッグで追加、deleteキーで削除。' },
      { icon: 'drop', title: 'ドラッグで、すぐ', body: 'Dockのアイコンに落とすだけ。ファイルは圧縮、圧縮ファイルは解凍。' },
      { icon: 'menu', title: 'Finderの右クリック', body: '「圧縮」「解凍」「中身を見る」。窓を開かずに使えます。' },
      { icon: 'kana', title: '文字化けしない', body: 'Windowsで作ったzip（Shift_JIS）を自動で判定。Windowsで化けないzipも作れます。' },
      { icon: 'stack', title: 'たくさんの形式', body: 'zip・7z・rar・tar・iso・lzh など。中身の処理に 7-Zip を同梱。7z・rar・tarもスペースキーでのぞけます。' },
      { icon: 'lock', title: 'パスワードと分割', body: 'AES-256。7zならファイル名も隠せます。2GBやDVDの大きさに分割も。' },
    ],
  },
  how: {
    eyebrow: 'しくみ',
    title: '大きなzipでも、すぐ開ける理由',
    lead: 'zipは末尾に「目次」を持っています。ZipPeekが読むのはそこだけ。ファイルの中身は読みません。',
    data: 'ファイルの中身 ─ 読まない',
    toc: '目次',
    tocNote: '読むのは目次だけ',
    result: '展開せずに一覧が出る',
  },
  encoding: {
    eyebrow: '文字化けしない',
    title: 'Windowsで作ったzipも、そのまま読める。',
    lead: '日本語のWindowsは、zipのファイル名をShift_JISで書きます。違う読み方をすると、意味のない文字になります。',
    without: '判定しないで読むと',
    withZipPeek: 'ZipPeek（自動判定：Shift_JIS）',
  },
  mac: {
    title: 'Macのために作りました',
    lead: '標準のツールバーとメニュー ・ 読み上げ（VoiceOver） ・ 視差効果を減らす ・ macOS 26ではLiquid Glass ・ ライト／ダークはMacに合わせて自動',
    windowAlt: 'ZipPeekのドラッグ先の窓。「選ぶ…」「中身を見る…」のボタンと、スペースキー機能をオンにする案内がある。',
    compactAlt: 'ガラスの小窓。ZipPeekのアイコンと「ここにドラッグ」の文字が入った小さな角丸の四角。',
    compactCaption: 'ガラスの小窓',
    styleTitle: '好きな形で',
    styleBody: '標準の窓か、じゃまにならない小さなガラスの窓か、設定で選べます。',
  },
  formats: { title: '対応形式', extract: '解凍', create: '作成', note: 'rar形式での圧縮はできません（rarの作成は開発元にしか許されていないため）。解凍はできます。' },
  install: {
    title: '1分で使えます',
    steps: [
      { title: 'dmgをダウンロード', body: 'GitHubの最新リリースから。' },
      { title: '「アプリケーション」へドラッグ', body: 'ほかのMacアプリと同じです。' },
      { title: 'ダブルクリックとスペースキーをオン', body: '一度起動して、最初の窓のボタンを押すだけ。' },
    ],
  },
  faq: {
    title: 'よくある質問',
    items: [
      { q: '本当に無料？', a: 'はい。MITライセンスのオープンソースです。' },
      { q: 'アップデートは自動？', a: '0.2 からは自動で知らせます。1日に1回確認し、入れる前に聞き、同じ開発者の署名があるときだけ入れ替えます。0.1.0 にはこの機能がないので、一度だけ最新版を入れ直してください。' },
      { q: 'スペースキーの機能をオンにする必要があるのはなぜ？', a: '新しいクイックルックの部品は、最初に1回だけMacの設定で許可が必要です。ZipPeekが状態を表示し、設定画面も開きます。' },
      { q: '7zやrarもスペースキーで見られる？', a: '0.3から見られます。zip・7z・rar・tar（.tar.gzなども）に対応。ほかの形式はZipPeekの窓で開けます（右クリック →「ZipPeekで中身を見る」）。' },
      { q: 'zipの中にファイルを足したり消したりできる？', a: '0.3から、zipと7zでできます。ZipPeekの窓にファイルをドラッグする（または「追加…」）と追加、選んでdeleteキーで削除。変更の前に必ず確認します。パスワード付きや分割された圧縮ファイルは変更できません。' },
      { q: 'Windowsから来たzipの名前が化けている', a: '自動で判定しますが、外れたときはツールバーの「ファイル名の文字コード」で切り替えてください。' },
      { q: '作ったzipはWindowsで開ける？', a: '開けます。日本語の名前があるときは、圧縮の設定で「Windowsで文字化けしない名前にする」をオンにしてください。' },
      { q: 'ファイルがどこかへ送られることは？', a: 'ありません。すべてMacの中だけで動きます。アカウントも利用状況の収集もありません。' },
    ],
  },
  cta: { title: '展開する前に、のぞこう。', lead: '無料・オープンソース。macOS 14 以降。', download: 'Mac版をダウンロード' },
  support: { title: '寄付のお願い', body: 'ZipPeek は無料で、これからも無料です。役に立ったら、GitHub Sponsors で開発を応援してもらえるとうれしいです。毎月でも1回だけでも、金額は自由です。', button: 'GitHub で寄付する' },
  footer: {
    links: [
      { label: 'GitHub', href: repo },
      { label: '寄付', href: 'https://github.com/sponsors/kajisho5' },
      { label: 'リリース', href: `${repo}/releases` },
      { label: '説明書（README）', href: `${repo}/blob/main/README.ja.md` },
      { label: '7-Zip のライセンス', href: 'https://www.7-zip.org/license.txt' },
    ],
    privacy: 'プライバシー：ZipPeekはすべてMacの中だけで動き、ファイルをどこにも送りません。このサイトはCookieや解析を使っていません。',
    credit: '© 2026 Shogo Kajiyama ・ MIT License ・ 圧縮・解凍の処理に 7-Zip（Igor Pavlov 作、GNU LGPL）を使用',
  },
};

export const text = { en, ja };
export type Lang = keyof typeof text;
export type { Text };
