import Foundation

/// サイズ表記。Finderと同じく1000単位（1 GB = 1,000,000,000 バイト）
public enum ByteFormat {
    public static func string(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        switch bytes {
        case ..<1_000:
            return "\(bytes) バイト"
        case ..<1_000_000:
            return "\(Int((b / 1_000).rounded())) KB"
        case ..<1_000_000_000:
            return one(b / 1_000_000) + " MB"
        case ..<1_000_000_000_000:
            return one(b / 1_000_000_000) + " GB"
        default:
            return one(b / 1_000_000_000_000) + " TB"
        }
    }

    static func one(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        if r >= 100 { return String(Int(r.rounded())) }
        return String(format: "%.1f", r)
    }
}
