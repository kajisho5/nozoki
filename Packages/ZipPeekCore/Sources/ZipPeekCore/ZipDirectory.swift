import Foundation

/// zipの中の1件（目次＝セントラルディレクトリから読んだ生の情報）
public struct ZipEntry: Sendable, Hashable {
    /// 目次の中での並び順（0から）。取り出し時にこの番号で対象を特定する
    public let index: Int
    /// ファイル名の生バイト列（文字コード未確定）
    public let rawName: Data
    /// 「名前はUTF-8です」という印（一般目的フラグの11ビット目）
    public let isUTF8Flagged: Bool
    /// Info-ZIPの「Unicodeの名前」拡張に入っていたUTF-8名（あれば最優先）
    public let unicodeName: String?
    public let isEncrypted: Bool
    public let compressionMethod: UInt16
    public let size: UInt64
    public let packedSize: UInt64
    public let modified: Date?
    /// 作成OSの情報と外部属性から判断したフォルダかどうか（名前末尾の / でも判断）
    public let externalAttributes: UInt32
    public let madeByOS: UInt8
    /// この項目の本体（ローカルヘッダー）がzipの先頭から何バイト目にあるか
    public var localHeaderOffset: UInt64 = 0
    /// 目次の中で、この項目の記録が占める範囲（リンク先のzipから1件だけ取り出すときに使う）
    public var centralRecordRange: Range<Int> = 0..<0
    /// 本体の位置が ZIP64 の追加情報の中に書いてある場合の、記録の中での位置
    public var localOffsetFieldInZip64: Int?
    /// 本体の後ろに「データ記述子」が付くか（一般目的フラグの3ビット目）
    public var hasDataDescriptor: Bool = false
}

/// zipの中身を読む元（手元のファイル、またはネットの先のファイル）
public protocol ZipByteSource {
    var size: UInt64 { get }
    func bytes(at offset: UInt64, count: Int) throws -> Data
}

public enum ZipReadError: Error, Equatable, LocalizedError {
    case notFound
    case notAZip
    case truncated
    case unsupportedMultiDisk

    public var errorDescription: String? {
        switch self {
        case .notFound: return tr("ファイルが見つかりません。", "The file could not be found.")
        case .notAZip: return tr("zipファイルとして読めませんでした。壊れているか、zip以外の形式です。", "This file could not be read as a ZIP archive. It may be damaged or in another format.")
        case .truncated: return tr("zipの目次が途中で切れています。ダウンロードやコピーが途中で止まった可能性があります。", "The archive's table of contents is cut off. The download or copy may not have finished.")
        case .unsupportedMultiDisk: return tr("分割zip（.z01 などに分かれたもの）は、中身を見る窓ではまだ開けません。解凍はできます。", "Split ZIP archives (.z01 and so on) can't be browsed yet, but they can be extracted.")
        }
    }
}

/// zipの末尾にある目次だけを読む。中身のデータ本体は一切読まないので、巨大zipでもすぐ終わる
public enum ZipDirectory {

    public static func read(url: URL) throws -> [ZipEntry] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw ZipReadError.notFound }
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        let reader = Reader(handle: handle, fileSize: fileSize)
        return try read(reader).entries
    }

    /// 目次を読む。目次そのもの（cd）も返す
    public static func read(_ r: ZipByteSource) throws -> (entries: [ZipEntry], cd: Data) {
        // 1) 末尾の「目次の終わり」記録（EOCD）を探す。後ろにコメントが最大65535バイト付くことがある
        let tailLength = min(r.size, UInt64(65_535 + 22))
        let tailStart = r.size - tailLength
        let tail = try r.bytes(at: tailStart, count: Int(tailLength))
        guard tail.count >= 22 else { throw ZipReadError.notAZip }
        var eocdPos: Int?
        var i = tail.count - 22
        while i >= 0 {
            if tail.u32(i) == 0x0605_4b50 { eocdPos = i; break }
            i -= 1
        }
        guard let ep = eocdPos else { throw ZipReadError.notAZip }

        let diskNumber = tail.u16(ep + 4)
        let cdDisk = tail.u16(ep + 6)
        var entryCount = UInt64(tail.u16(ep + 10))
        var cdSize = UInt64(tail.u32(ep + 12))
        var cdOffset = UInt64(tail.u32(ep + 16))

        // 2) 4GBを超えるzip（ZIP64）は、EOCDの手前に本当の値が書いてある
        let eocdAbsolute = tailStart + UInt64(ep)
        if eocdAbsolute >= 20 {
            let loc = try r.bytes(at: eocdAbsolute - 20, count: 20)
            if loc.u32(0) == 0x0706_4b50 {
                let z64Offset = loc.u64(8)
                let z64 = try r.bytes(at: z64Offset, count: 56)
                guard z64.u32(0) == 0x0606_4b50 else { throw ZipReadError.notAZip }
                entryCount = z64.u64(32)
                cdSize = z64.u64(40)
                cdOffset = z64.u64(48)
            } else if diskNumber != 0 || cdDisk != 0 {
                throw ZipReadError.unsupportedMultiDisk
            }
        }

        guard cdOffset <= r.size, cdSize <= r.size - cdOffset else { throw ZipReadError.truncated }
        // 目次は件数が多くても数十MB程度なので一度に読む
        let cd = try r.bytes(at: cdOffset, count: Int(cdSize))
        var entries: [ZipEntry] = []
        entries.reserveCapacity(Int(min(entryCount, 1_000_000)))
        var p = 0
        var index = 0
        while p + 46 <= cd.count, UInt64(index) < entryCount {
            guard cd.u32(p) == 0x0201_4b50 else { break }
            let madeBy = cd.u16(p + 4)
            let flags = cd.u16(p + 8)
            let method = cd.u16(p + 10)
            let dosTime = cd.u16(p + 12)
            let dosDate = cd.u16(p + 14)
            var packed = UInt64(cd.u32(p + 20))
            var size = UInt64(cd.u32(p + 24))
            let nameLen = Int(cd.u16(p + 28))
            let extraLen = Int(cd.u16(p + 30))
            let commentLen = Int(cd.u16(p + 32))
            let extAttr = cd.u32(p + 38)
            let nameStart = p + 46
            let extraStart = nameStart + nameLen
            let next = extraStart + extraLen + commentLen
            guard next <= cd.count else { throw ZipReadError.truncated }
            let rawName = cd.subdata(in: nameStart..<extraStart)
            var localOffset = UInt64(cd.u32(p + 42))
            var offsetField: Int?

            var unicodeName: String?
            var e = extraStart
            let extraEnd = extraStart + extraLen
            while e + 4 <= extraEnd {
                let tag = cd.u16(e)
                let len = Int(cd.u16(e + 2))
                let body = e + 4
                guard body + len <= extraEnd else { break }
                if tag == 0x0001 {
                    // ZIP64の追加情報：0xFFFFFFFFになっている項目だけが順に入っている
                    var q = body
                    if size == 0xFFFF_FFFF, q + 8 <= body + len { size = cd.u64(q); q += 8 }
                    if packed == 0xFFFF_FFFF, q + 8 <= body + len { packed = cd.u64(q); q += 8 }
                    if localOffset == 0xFFFF_FFFF, q + 8 <= body + len { localOffset = cd.u64(q); offsetField = q - p; q += 8 }
                } else if tag == 0x7075, len >= 5 {
                    // Info-ZIPのUnicode名：版(1) + 元の名前のCRC(4) + UTF-8名
                    let utf8 = cd.subdata(in: (body + 5)..<(body + len))
                    let expectedCRC = cd.u32(body + 1)
                    if CRC32.checksum(rawName) == expectedCRC, let s = String(data: utf8, encoding: .utf8) {
                        unicodeName = s
                    }
                }
                e = body + len
            }

            entries.append(ZipEntry(
                index: index,
                rawName: rawName,
                isUTF8Flagged: flags & (1 << 11) != 0,
                unicodeName: unicodeName,
                isEncrypted: flags & 1 != 0,
                compressionMethod: method,
                size: size,
                packedSize: packed,
                modified: DOSDate.date(date: dosDate, time: dosTime),
                externalAttributes: extAttr,
                madeByOS: UInt8(madeBy >> 8),
                localHeaderOffset: localOffset,
                centralRecordRange: p..<next,
                localOffsetFieldInZip64: offsetField,
                hasDataDescriptor: flags & (1 << 3) != 0
            ))
            index += 1
            p = next
        }
        if entries.isEmpty && entryCount > 0 { throw ZipReadError.truncated }
        return (entries, cd)
    }

    struct Reader: ZipByteSource {
        let handle: FileHandle
        let fileSize: UInt64
        var size: UInt64 { fileSize }

        func bytes(at offset: UInt64, count: Int) throws -> Data {
            guard offset + UInt64(count) <= fileSize else { throw ZipReadError.truncated }
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: count) ?? Data()
            guard data.count == count else { throw ZipReadError.truncated }
            return data
        }
    }
}

extension ZipEntry {
    /// 名前の末尾が / か、Windows/Unix の属性でフォルダと分かるもの
    public var looksLikeDirectory: Bool {
        if rawName.last == 0x2F || rawName.last == 0x5C { return true }
        switch madeByOS {
        case 0: return externalAttributes & 0x10 != 0           // MS-DOS / Windows
        case 3, 19: return (externalAttributes >> 16) & 0xF000 == 0x4000 // Unix / macOS
        default: return false
        }
    }
}

enum DOSDate {
    /// zipの日付（DOS形式）は時差の情報を持たないので、見ている人の地域の時刻として扱う
    static func date(date: UInt16, time: UInt16) -> Date? {
        if date == 0 { return nil }
        var c = DateComponents()
        c.year = Int((date >> 9) & 0x7F) + 1980
        c.month = Int((date >> 5) & 0x0F)
        c.day = Int(date & 0x1F)
        c.hour = Int((time >> 11) & 0x1F)
        c.minute = Int((time >> 5) & 0x3F)
        c.second = Int(time & 0x1F) * 2
        guard (1...12).contains(c.month ?? 0), (1...31).contains(c.day ?? 0) else { return nil }
        return Calendar(identifier: .gregorian).date(from: c)
    }
}

/// zipで使われるCRC-32（Unicode名の照合用）
public enum CRC32 {
    static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}

extension Data {
    @inline(__always) func u16(_ o: Int) -> UInt16 {
        let s = startIndex + o
        return UInt16(self[s]) | UInt16(self[s + 1]) << 8
    }
    @inline(__always) func u32(_ o: Int) -> UInt32 {
        UInt32(u16(o)) | UInt32(u16(o + 2)) << 16
    }
    @inline(__always) func u64(_ o: Int) -> UInt64 {
        UInt64(u32(o)) | UInt64(u32(o + 4)) << 32
    }
}
