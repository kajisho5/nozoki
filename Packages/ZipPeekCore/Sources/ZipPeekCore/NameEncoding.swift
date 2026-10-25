import Foundation

/// ファイル名の文字コード
public enum NameEncoding: String, CaseIterable, Sendable, Identifiable {
    case utf8
    case shiftJIS
    case gbk
    case big5
    case korean
    case windowsLatin
    case cp437

    public var id: String { rawValue }

    /// 画面に出す名前
    public var label: String {
        switch self {
        case .utf8: return "UTF-8"
        case .shiftJIS: return tr("日本語（Shift_JIS）", "Japanese (Shift_JIS)")
        case .gbk: return tr("中国語 簡体字（GBK）", "Chinese Simplified (GBK)")
        case .big5: return tr("中国語 繁体字（Big5）", "Chinese Traditional (Big5)")
        case .korean: return tr("韓国語（CP949）", "Korean (CP949)")
        case .windowsLatin: return tr("西欧（Windows-1252）", "Western (Windows-1252)")
        case .cp437: return tr("CP437（英語版の古いWindows）", "CP437 (Western DOS)")
        }
    }

    /// Windows のコードページ（CFStringEncoding の値）。Mac では CoreFoundation の変換表を使う
    private var cfEncoding: UInt32? {
        switch self {
        case .utf8, .cp437: return nil
        case .shiftJIS: return 0x0420   // kCFStringEncodingDOSJapanese（CP932：①や㈱も読める）
        case .gbk: return 0x0421        // kCFStringEncodingDOSChineseSimplif（CP936）
        case .korean: return 0x0422     // kCFStringEncodingDOSKorean（CP949）
        case .big5: return 0x0423       // kCFStringEncodingDOSChineseTrad（CP950）
        case .windowsLatin: return 0x0500 // kCFStringEncodingWindowsLatin1（CP1252）
        }
    }

    /// Foundationで使う文字コード
    public var stringEncoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .cp437:
            #if canImport(Darwin)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0400)))
            #else
            return .isoLatin1
            #endif
        default:
            #if canImport(Darwin)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncoding!)))
            #else
            switch self {
            case .shiftJIS: return .shiftJIS
            case .windowsLatin: return .windowsCP1252
            default: return .utf8 // Linux では変換表が無い（テストは Mac で行う）
            }
            #endif
        }
    }

    /// 自動判定で試す順番。使う人の言語を優先する（日本語・英語の人は日本語の zip が多いので Shift_JIS が先）
    static var detectionOrder: [NameEncoding] {
        let lang = Locale.preferredLanguages.first?.lowercased() ?? "ja"
        if lang.hasPrefix("zh-hans") || lang == "zh-cn" || lang == "zh-sg" { return [.gbk, .big5, .shiftJIS, .korean] }
        if lang.hasPrefix("zh") { return [.big5, .gbk, .shiftJIS, .korean] }
        if lang.hasPrefix("ko") { return [.korean, .shiftJIS, .gbk, .big5] }
        return [.shiftJIS, .gbk, .korean, .big5]
    }

    func decode(_ data: Data) -> String? {
        if self == .cp437 {
            return CP437.decode(data)
        }
        return String(data: data, encoding: stringEncoding)
    }

    /// zipの中の名前の決め方
    /// - 「UTF-8です」の印が付いた名前、Unicode名の拡張がある名前はそれに従う
    /// - 印のない名前がすべてUTF-8として正しければUTF-8（Macの標準圧縮は印なしのUTF-8で書く）
    /// - そうでなく、使う人の言語に近い順（日本語・中国語・韓国語）に試して全部読めたものを使う
    /// - どれでもなければCP437
    public static func detect(_ entries: [ZipEntry]) -> NameEncoding {
        let legacy = entries.filter { !$0.isUTF8Flagged && $0.unicodeName == nil && !$0.rawName.isASCII }
        if legacy.isEmpty { return .utf8 }
        if legacy.allSatisfy({ String(data: $0.rawName, encoding: .utf8) != nil }) { return .utf8 }
        for candidate in detectionOrder where legacy.allSatisfy({ candidate.decode($0.rawName) != nil }) {
            #if !canImport(Darwin)
            if candidate != .shiftJIS { continue } // Linux では日本語以外の変換表が無い
            #endif
            return candidate
        }
        return .cp437
    }
}

extension ZipEntry {
    /// 指定の文字コードで名前を読む。読めない文字は「?」に置き換える
    public func name(using encoding: NameEncoding) -> String {
        if let u = unicodeName { return u }
        if isUTF8Flagged, let s = String(data: rawName, encoding: .utf8) { return s }
        if rawName.isASCII { return String(decoding: rawName, as: UTF8.self) }
        if let s = encoding.decode(rawName) { return s }
        return String(decoding: rawName, as: UTF8.self) // 壊れた部分は置換文字になる
    }
}

extension Data {
    var isASCII: Bool { allSatisfy { $0 < 0x80 } }
}

/// CP437（初期のDOS／英語版Windowsの文字表）。Linuxでも同じ結果になるよう自前で持つ
enum CP437 {
    static let upper: [UInt16] = [
        0x00C7, 0x00FC, 0x00E9, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E7, 0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x00EC, 0x00C4, 0x00C5,
        0x00C9, 0x00E6, 0x00C6, 0x00F4, 0x00F6, 0x00F2, 0x00FB, 0x00F9, 0x00FF, 0x00D6, 0x00DC, 0x00A2, 0x00A3, 0x00A5, 0x20A7, 0x0192,
        0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA, 0x00BF, 0x2310, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB,
        0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556, 0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510,
        0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F, 0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567,
        0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B, 0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,
        0x03B1, 0x00DF, 0x0393, 0x03C0, 0x03A3, 0x03C3, 0x00B5, 0x03C4, 0x03A6, 0x0398, 0x03A9, 0x03B4, 0x221E, 0x03C6, 0x03B5, 0x2229,
        0x2261, 0x00B1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00F7, 0x2248, 0x00B0, 0x2219, 0x00B7, 0x221A, 0x207F, 0x00B2, 0x25A0, 0x00A0
    ]

    static func decode(_ data: Data) -> String {
        var s = String.UnicodeScalarView()
        for b in data {
            if b < 0x80 {
                s.append(Unicode.Scalar(b))
            } else if let u = Unicode.Scalar(upper[Int(b) - 0x80]) {
                s.append(u)
            }
        }
        return String(s)
    }
}
