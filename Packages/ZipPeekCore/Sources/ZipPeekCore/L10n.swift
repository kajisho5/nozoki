import Foundation

/// 日本語と英語の出し分け。Macの言語設定の一番上が日本語なら日本語、それ以外は英語
public enum L10n {
    /// テストや設定から切り替えられるようにする（nil = Macの設定に従う）
    nonisolated(unsafe) public static var override: Bool?

    public static var isJapanese: Bool {
        if let o = override { return o }
        let first = Locale.preferredLanguages.first ?? "en"
        return first.hasPrefix("ja")
    }
}

/// 日本語と英語を並べて書き、表示時に選ぶ
@inline(__always)
public func tr(_ ja: String, _ en: String) -> String {
    L10n.isJapanese ? ja : en
}
