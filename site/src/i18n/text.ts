// 配布ページの文言（日本語・英語）。他社製品の名前は入れない
export const text = {
  ja: {
    lang: 'ja',
    title: 'ZipPeek ─ Macの圧縮・解凍',
    description: 'Macの圧縮・解凍。そして、展開せずにのぞく。無料・オープンソース。',
    tagline: 'Macの圧縮・解凍。そして、展開せずにのぞく。',
    download: '最新版をダウンロード',
    meta1: '無料 ・ オープンソース（MIT）',
    meta2: 'macOS 14 以降 ・ Apple シリコン / Intel',
    features: [
      { title: 'ドラッグで、すぐ', body: 'Dockのアイコンに落とすだけで圧縮も解凍も。Finderの右クリックからも使えます。' },
      { title: '展開せずにのぞく', body: 'Finderでスペースキーを押すと中身を表示。30GBのzipでも一瞬。必要な1ファイルだけ取り出せます。' },
      { title: '文字化けしない', body: 'Windowsで作ったzipも正しい日本語で。Windowsで文字化けしないzipも作れます。' },
    ],
    more: [
      'パスワード（AES-256）・分割・圧縮率を選べる',
      'Mac専用の隠しファイル（.DS_Store など）を入れない',
      'ライト／ダークはMacの設定に自動で合わせる。ガラスの小窓にも切り替え',
      '日本語・英語',
    ],
    shot: 'screen-ja.png',
    shotAlt: '中身を見る窓。Windowsで作ったzipの日本語のファイル名が正しく表示されている',
    formatsTitle: '解凍できる形式',
    createTitle: '作れる形式',
    install: [
      'dmgを開いて、ZipPeek を「アプリケーション」へドラッグ',
      '一度起動して、案内に沿って「スペースキーで中身を見る」をオン',
    ],
    installTitle: '入れ方',
    footerGitHub: 'GitHub',
    footerReleases: '更新履歴',
    footerLicense: '7-Zip のライセンス',
    credit: '圧縮・解凍の中身に 7-Zip（Igor Pavlov 作、GNU LGPL）を使っています。',
    switchLabel: 'English',
    switchHref: '/zippeek/en/',
  },
  en: {
    lang: 'en',
    title: 'ZipPeek — Compress and extract on your Mac',
    description: 'Compress and extract on your Mac — and peek inside without extracting. Free and open source.',
    tagline: 'Compress and extract on your Mac — and peek inside without extracting.',
    download: 'Download the latest version',
    meta1: 'Free · Open source (MIT)',
    meta2: 'macOS 14 or later · Apple silicon / Intel',
    features: [
      { title: 'Drop to go', body: 'Drop files on the Dock icon to compress or extract. It’s in Finder’s right-click menu too.' },
      { title: 'Peek without extracting', body: 'Press Space in Finder to see what’s inside — instantly, even for 30 GB. Take out just the file you need.' },
      { title: 'No garbled names', body: 'Japanese file names from Windows show correctly, and you can make ZIPs that open cleanly on Japanese Windows.' },
    ],
    more: [
      'Passwords (AES-256), splitting and compression levels',
      'Leaves out Mac-only hidden files like .DS_Store',
      'Follows your Mac’s light or dark setting; optional compact glass drop target',
      'Japanese and English',
    ],
    shot: 'screen-en.png',
    shotAlt: 'The browser window showing a ZIP made on Japanese Windows, with its file names displayed correctly',
    formatsTitle: 'Extracts',
    createTitle: 'Creates',
    install: [
      'Open the dmg and drag ZipPeek into Applications',
      'Launch it once and follow the prompt to turn on “Press Space to look inside”',
    ],
    installTitle: 'Install',
    footerGitHub: 'GitHub',
    footerReleases: 'Releases',
    footerLicense: '7-Zip license',
    credit: 'Compression is powered by 7-Zip by Igor Pavlov (GNU LGPL).',
    switchLabel: '日本語',
    switchHref: '/zippeek/',
  },
} as const;

export type Lang = keyof typeof text;

export const formats = ['zip', '7z', 'rar', 'tar', 'gz', 'bz2', 'xz', 'zst', 'iso', 'lzh', 'cab', 'arj', 'cpio', 'wim', 'xar', 'rpm', 'deb'];
export const creates = ['zip', '7z'];
export const repo = 'https://github.com/kajisho5/zippeek';
