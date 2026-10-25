# アプリアイコンの原版

- `src/*.svg` … レイヤー（1024×1024、角丸なし・効果なし。ハイライトや影はシステムが付ける）
- `spec.json` … 重ね方と背景（ライト・ダーク）

作り直すとき（[fresnel](https://github.com/kajisho5/fresnel) を使う）:

```sh
npx fresnel-icon@0.2.2 build spec.json -o ../../ZipPeek/Resources/AppIcon.icon
npx fresnel-icon@0.2.2 validate ../../ZipPeek/Resources/AppIcon.icon
```
