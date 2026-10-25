import Foundation

/// ファイル名の文字コード
public enum NameEncoding: String, CaseIterable, Sendable, Identifiable {
    case utf8
    case shiftJIS
    case cp437

    public var id: String { rawValue }

    /// 画面に出す名前
    public var label: String {
        switch self {
        case .utf8: return "UTF-8"
        case .shiftJIS: return "Shift_JIS"
        case .cp437: return "CP437（英語版Windows）"
        }
    }

    /// Foundationで使う文字コード。Shift_JISはWindowsの拡張文字（①や㈱など）も読めるCP932を使う
    public var stringEncoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .shiftJIS:
            #if canImport(Darwin)
            // kCFStringEncodingDOSJapanese = 0x0420（0x0421 は簡体字中国語なので注意）
            let cp932 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0420))
            return String.Encoding(rawValue: cp932)
            #else
            return .shiftJIS
            #endif
        case .cp437:
            #if canImport(Darwin)
            let dosLatinUS = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0400))
            return String.Encoding(rawValue: dosLatinUS)
            #else
            return .isoLatin1
            #endif
        }
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
    /// - そうでなくShift_JISとして全部読めればShift_JIS（日本語Windowsで作ったzip）
    /// - どれでもなければCP437
    public static func detect(_ entries: [ZipEntry]) -> NameEncoding {
        let legacy = entries.filter { !$0.isUTF8Flagged && $0.unicodeName == nil && !$0.rawName.isASCII }
        if legacy.isEmpty { return .utf8 }
        if legacy.allSatisfy({ String(data: $0.rawName, encoding: .utf8) != nil }) { return .utf8 }
        if legacy.allSatisfy({ NameEncoding.shiftJIS.decode($0.rawName) != nil }) { return .shiftJIS }
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
