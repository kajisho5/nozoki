import Foundation
@testable import ZipPeekCore

/// テスト用に、名前のバイト列やフラグを自由に決めたzipを手で組み立てる（無圧縮のみ）
struct ZipBuilder {
    struct Item {
        var rawName: Data
        var content: Data = Data()
        var utf8Flag = false
        var encryptedFlag = false
        var unicodeName: String?
        var madeByOS: UInt8 = 0
        var externalAttributes: UInt32 = 0
    }

    var items: [Item] = []
    /// true にすると、サイズと位置をZIP64の形式で書く
    var forceZIP64 = false
    var comment = Data()

    func build() -> Data {
        var out = Data()
        var central = Data()
        for item in items {
            let offset = UInt64(out.count)
            let crc = CRC32.checksum(item.content)
            var flags: UInt16 = 0
            if item.utf8Flag { flags |= 1 << 11 }
            if item.encryptedFlag { flags |= 1 }
            let size = UInt64(item.content.count)
            // 2026/09/12 14:02:00
            let dosDate: UInt16 = UInt16((2026 - 1980) << 9 | 9 << 5 | 12)
            let dosTime: UInt16 = UInt16(14 << 11 | 2 << 5 | 0)

            var extra = Data()
            if let u = item.unicodeName {
                let utf8 = Data(u.utf8)
                extra.le16(0x7075); extra.le16(UInt16(5 + utf8.count))
                extra.append(1); extra.le32(CRC32.checksum(item.rawName)); extra.append(utf8)
            }

            // ローカルヘッダ
            out.le32(0x0403_4b50); out.le16(forceZIP64 ? 45 : 20); out.le16(flags); out.le16(0)
            out.le16(dosTime); out.le16(dosDate); out.le32(crc)
            out.le32(UInt32(size)); out.le32(UInt32(size))
            out.le16(UInt16(item.rawName.count)); out.le16(0)
            out.append(item.rawName)
            out.append(item.content)

            var cdExtra = extra
            if forceZIP64 {
                cdExtra.le16(0x0001); cdExtra.le16(24)
                cdExtra.le64(size); cdExtra.le64(size); cdExtra.le64(offset)
            }
            central.le32(0x0201_4b50)
            central.le16(UInt16(item.madeByOS) << 8 | 45); central.le16(forceZIP64 ? 45 : 20)
            central.le16(flags); central.le16(0); central.le16(dosTime); central.le16(dosDate); central.le32(crc)
            central.le32(forceZIP64 ? 0xFFFF_FFFF : UInt32(size))
            central.le32(forceZIP64 ? 0xFFFF_FFFF : UInt32(size))
            central.le16(UInt16(item.rawName.count)); central.le16(UInt16(cdExtra.count)); central.le16(0)
            central.le16(0); central.le16(0); central.le32(item.externalAttributes)
            central.le32(forceZIP64 ? 0xFFFF_FFFF : UInt32(offset))
            central.append(item.rawName)
            central.append(cdExtra)
        }
        let cdOffset = UInt64(out.count)
        out.append(central)
        if forceZIP64 {
            let z64Pos = UInt64(out.count)
            out.le32(0x0606_4b50); out.le64(44); out.le16(45); out.le16(45); out.le32(0); out.le32(0)
            out.le64(UInt64(items.count)); out.le64(UInt64(items.count))
            out.le64(UInt64(central.count)); out.le64(cdOffset)
            out.le32(0x0706_4b50); out.le32(0); out.le64(z64Pos); out.le32(1)
        }
        out.le32(0x0605_4b50); out.le16(0); out.le16(0)
        out.le16(forceZIP64 ? 0xFFFF : UInt16(items.count)); out.le16(forceZIP64 ? 0xFFFF : UInt16(items.count))
        out.le32(forceZIP64 ? 0xFFFF_FFFF : UInt32(central.count))
        out.le32(forceZIP64 ? 0xFFFF_FFFF : UInt32(cdOffset))
        out.le16(UInt16(comment.count)); out.append(comment)
        return out
    }

    func write(to url: URL) throws {
        try build().write(to: url)
    }
}

extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) { le16(UInt16(v & 0xFFFF)); le16(UInt16(v >> 16)) }
    mutating func le64(_ v: UInt64) { le32(UInt32(v & 0xFFFF_FFFF)); le32(UInt32(v >> 32)) }
}

/// 架空のサンプル名だけを使う
enum Sample {
    /// 「撮影メモ.txt」をShift_JIS(CP932)で表したバイト列
    static let sjisMemo = Data([0x8E, 0x42, 0x89, 0x65, 0x83, 0x81, 0x83, 0x82]) + Data(".txt".utf8)
    /// 「素材/」をShift_JISで
    static let sjisFolder = Data([0x91, 0x66, 0x8D, 0xDE, 0x2F])
}
