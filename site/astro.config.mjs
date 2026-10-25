// 配布ページ。GitHub Pages（https://kajisho5.github.io/zippeek/）に置く
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://kajisho5.github.io',
  base: '/zippeek',
  i18n: {
    locales: ['ja', 'en'],
    defaultLocale: 'ja',
    routing: { prefixDefaultLocale: false },
  },
});
