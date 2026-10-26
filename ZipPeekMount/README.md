# ZipPeekMount（試作・未同梱）

圧縮ファイルを Finder にドライブとしてつなぐ部品（Apple の FSKit、macOS 26 以降）。読み取り専用。
アプリにはまだ入れていない。理由：

- FSKit の部品には Apple の特別な権限（com.apple.developer.fskit.fsmodule）が要り、配布用の署名（Developer ID）では
  その権限を書いた「プロファイル」を部品に埋め込む必要がある。今の署名の仕組み（runway）はプロファイルを扱っていない。
- 本物の Mac（GitHub のテスト機）で、署名なしの試作をシステム設定でオンにしようとしたが、スイッチが切り替わらなかった
  （「Module com.kajisho5.zippeek.mount is disabled!」）。

入れるときは project.yml に次を戻す：
```yaml
# ZipPeek の dependencies に
      - target: ZipPeekMount
        embed: true
# targets に

  ZipPeekMount:
    type: extensionkit-extension
    platform: macOS
    deploymentTarget: "26.0"
    sources:
      - path: ZipPeekMount
    dependencies:
      - package: ZipPeekCore
      - sdk: FSKit.framework
    settings:
      base:
        PRODUCT_NAME: ZipPeekMount
        PRODUCT_BUNDLE_IDENTIFIER: com.kajisho5.zippeek.mount
        CODE_SIGN_ENTITLEMENTS: ZipPeekMount/ZipPeekMount.entitlements
        SKIP_INSTALL: YES
    info:
      path: ZipPeekMount/Info.plist
      properties:
        CFBundleDisplayName: ZipPeek
        CFBundleName: ZipPeekMount
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        CFBundleDevelopmentRegion: en
        LSMinimumSystemVersion: "26.0"
        EXAppExtensionAttributes:
          EXExtensionPointIdentifier: com.apple.fskit.fsmodule
          FSShortName: zippeek
          FSSupportsBlockResources: false
          FSSupportsPathURLs: true
          FSRequiresSecurityScopedPathURLResources: true
          FSMediaTypes: {}
          FSPersonalities: {}
          FSActivateOptionSyntax:
            shortOptions: "o:"
```
