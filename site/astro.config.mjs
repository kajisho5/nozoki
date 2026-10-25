// 配布ページ。GitHub Pages（https://kajisho5.github.io/zippeek/）に置く
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://kajisho5.github.io',
  base: '/zippeek',
  // 以前の英語ページの場所（/en/）は英語のトップへ転送する
  redirects: { '/en': '/zippeek/' },
  i18n: {
    locales: ['en', 'ja'],
    defaultLocale: 'en',
    routing: { prefixDefaultLocale: false },
  },
});
