import Foundation

/// zipの中のファイル名を、別の文字コード（Shift_JIS）で書き直した新しいzipを作る。
/// 中身のデータはそのまま写すだけなので、暗号付きでも壊れない。
/// 7-Zipは名前を必ずUTF-8で書くため、「Windowsで文字化けしないzip」を作るときにこれを使う。
public enum ZipNameRewriter {
    public enum Failure: Error { case unsupported(String) }

    /// - Parameter encode: 名前を新しい文字コードのバイト列にする。nil を返した名前はUTF-8のまま残す
    /// - Returns: 書き直した件数
    @discardableResult
    public static func rewrite(_ input: URL, to output: URL, encode: (String) -> Data?) throws -> Int {
        let inHandle = try FileHandle(forReadingFrom: input)
        defer { try? inHandle.close() }
        let fileSize = try inHandle.seekToEnd()
        let reader = ZipDirectory.Reader(handle: inHandle, fileSize: fileSize)

        // 末尾の記録を読む（ZipDirectory と同じ探し方）
        let tailLength = min(fileSize, UInt64(65_535 + 22))
        let tailStart = fileSize - tailLength
        let tail = try reader.bytes(at: tailStart, count: Int(tailLength))
        var ep = tail.count - 22
        while ep >= 0, tail.u32(ep) != 0x0605_4b50 { ep -= 1 }
        guard ep >= 0 else { throw ZipReadError.notAZip }
        let eocdAbs = tailStart + UInt64(ep)
        var entryCount = UInt64(tail.u16(ep + 10))
        var cdSize = UInt64(tail.u32(ep + 12))
        var cdOffset = UInt64(tail.u32(ep + 16))
        let commentLen = Int(tail.u16(ep + 20))
        let comment = tail.subdata(in: (ep + 22)..<min(tail.count, ep + 22 + commentLen))
        var z64Abs: UInt64?
        if eocdAbs >= 20 {
            let loc = try reader.bytes(at: eocdAbs - 20, count: 20)
            if loc.u32(0) == 0x0706_4b50 {
                let off = loc.u64(8)
                let z = try reader.bytes(at: off, count: 56)
                guard z.u32(0) == 0x0606_4b50 else { throw ZipReadError.notAZip }
                z64Abs = off
                entryCount = z.u64(32); cdSize = z.u64(40); cdOffset = z.u64(48)
            }
        }
        let cd = try reader.bytes(at: cdOffset, count: Int(cdSize))

        struct Rec {
            var header: Data      // 46バイトの固定部分
            var name: Data
            var extra: Data
            var comment: Data
            var localOffset: UInt64
            var offsetInZip64Extra: Int? // extra の中で位置が書いてある場所
        }
        var recs: [Rec] = []
        var p = 0
        while p + 46 <= cd.count, recs.count < entryCount {
            guard cd.u32(p) == 0x0201_4b50 else { break }
            let nameLen = Int(cd.u16(p + 28)), extraLen = Int(cd.u16(p + 30)), cmtLen = Int(cd.u16(p + 32))
            let header = cd.subdata(in: p..<(p + 46))
            let name = cd.subdata(in: (p + 46)..<(p + 46 + nameLen))
            let extra = cd.subdata(in: (p + 46 + nameLen)..<(p + 46 + nameLen + extraLen))
            let cmt = cd.subdata(in: (p + 46 + nameLen + extraLen)..<(p + 46 + nameLen + extraLen + cmtLen))
            var offset = UInt64(cd.u32(p + 42))
            var offsetPos: Int?
            if offset == 0xFFFF_FFFF {
                // ZIP64追加情報の中の位置
                var e = 0
                while e + 4 <= extra.count {
                    let tag = extra.u16(e), len = Int(extra.u16(e + 2))
                    if tag == 0x0001 {
                        var q = e + 4
                        if cd.u32(p + 24) == 0xFFFF_FFFF { q += 8 }
                        if cd.u32(p + 20) == 0xFFFF_FFFF { q += 8 }
                        if q + 8 <= e + 4 + len { offset = extra.u64(q); offsetPos = q }
                    }
                    e += 4 + len
                }
            }
            recs.append(Rec(header: header, name: name, extra: extra, comment: cmt, localOffset: offset,
                            offsetInZip64Extra: offsetPos))
            p += 46 + nameLen + extraLen + cmtLen
        }

        // 各ファイルのデータの範囲 = 次のファイルの開始位置（または目次の開始位置）まで
        let order = recs.indices.sorted { recs[$0].localOffset < recs[$1].localOffset }
        var ends: [Int: UInt64] = [:]
        for (k, idx) in order.enumerated() {
            ends[idx] = k + 1 < order.count ? recs[order[k + 1]].localOffset : cdOffset
        }

        FileManager.default.createFile(atPath: output.path, contents: nil)
        let out = try FileHandle(forWritingTo: output)
        defer { try? out.close() }
        var written: UInt64 = 0
        func write(_ d: Data) throws { try out.write(contentsOf: d); written += UInt64(d.count) }

        var newCD = Data()
        var changed = 0
        var newOffsets: [Int: UInt64] = [:]

        for idx in order {
            let r = recs[idx]
            let utf8Name = String(data: r.name, encoding: .utf8)
            let isUTF8 = r.header.u16(8) & (1 << 11) != 0
            var newName = r.name
            var clearFlag = false
            if isUTF8, let s = utf8Name, !r.name.allSatisfy({ $0 < 0x80 }), let enc = encode(s) {
                newName = enc
                clearFlag = true
                changed += 1
            }
            // ローカルヘッダ
            let lh = try reader.bytes(at: r.localOffset, count: 30)
            guard lh.u32(0) == 0x0403_4b50 else { throw Failure.unsupported("local header") }
            let lNameLen = UInt64(lh.u16(26)), lExtraLen = Int(lh.u16(28))
            let lExtra = try reader.bytes(at: r.localOffset + 30 + lNameLen, count: lExtraLen)
            let dataStart = r.localOffset + 30 + lNameLen + UInt64(lExtraLen)
            guard let dataEnd = ends[idx], dataEnd >= dataStart else { throw Failure.unsupported("layout") }

            newOffsets[idx] = written
            var newLH = lh
            if clearFlag { newLH.put16(6, lh.u16(6) & ~UInt16(1 << 11)) }
            newLH.put16(26, UInt16(newName.count))
            try write(newLH); try write(newName); try write(lExtra)
            // データ本体はそのまま写す（巨大でも少しずつ）
            var pos = dataStart
            try inHandle.seek(toOffset: pos)
            while pos < dataEnd {
                let n = Int(min(UInt64(8 << 20), dataEnd - pos))
                guard let chunk = try inHandle.read(upToCount: n), !chunk.isEmpty else { throw ZipReadError.truncated }
                try write(chunk)
                pos += UInt64(chunk.count)
            }
        }

        let newCDOffset = written
        for idx in recs.indices {
            var r = recs[idx]
            let isUTF8 = r.header.u16(8) & (1 << 11) != 0
            var name = r.name
            var extra = r.extra
            if isUTF8, let s = String(data: r.name, encoding: .utf8), !r.name.allSatisfy({ $0 < 0x80 }), let enc = encode(s) {
                name = enc
                r.header.put16(8, r.header.u16(8) & ~UInt16(1 << 11))
                // 新しい道具向けに、UTF-8の名前も「Unicode名」として添えておく
                let u = Data(s.utf8)
                var x = Data()
                x.put16le(0x7075); x.put16le(UInt16(5 + u.count)); x.append(1); x.put32le(CRC32.checksum(enc)); x.append(u)
                extra.append(x)
            }
            let newOffset = newOffsets[idx] ?? 0
            if let pos = r.offsetInZip64Extra {
                extra.put64(pos, newOffset)
            } else {
                r.header.put32(42, UInt32(newOffset))
            }
            r.header.put16(28, UInt16(name.count))
            r.header.put16(30, UInt16(extra.count))
            newCD.append(r.header); newCD.append(name); newCD.append(extra); newCD.append(r.comment)
        }
        try write(newCD)
        let newCDSize = UInt64(newCD.count)

        if let z64Abs {
            var z = try reader.bytes(at: z64Abs, count: 56)
            z.put64(40, newCDSize); z.put64(48, newCDOffset)
            let newZ64 = written
            try write(z)
            var loc = Data(); loc.put32le(0x0706_4b50); loc.put32le(0); loc.put64le(newZ64); loc.put32le(1)
            try write(loc)
        }
        var eocd = try reader.bytes(at: eocdAbs, count: 22)
        if eocd.u32(12) != 0xFFFF_FFFF { eocd.put32(12, UInt32(min(newCDSize, 0xFFFF_FFFE))) }
        if eocd.u32(16) != 0xFFFF_FFFF { eocd.put32(16, UInt32(min(newCDOffset, 0xFFFF_FFFE))) }
        try write(eocd); try write(comment)
        return changed
    }
}

extension Data {
    mutating func put16(_ o: Int, _ v: UInt16) {
        let s = startIndex + o
        self[s] = UInt8(v & 0xFF); self[s + 1] = UInt8(v >> 8)
    }
    mutating func put32(_ o: Int, _ v: UInt32) { put16(o, UInt16(v & 0xFFFF)); put16(o + 2, UInt16(v >> 16)) }
    mutating func put64(_ o: Int, _ v: UInt64) { put32(o, UInt32(v & 0xFFFF_FFFF)); put32(o + 4, UInt32(v >> 32)) }
    mutating func put16le(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func put32le(_ v: UInt32) { put16le(UInt16(v & 0xFFFF)); put16le(UInt16(v >> 16)) }
    mutating func put64le(_ v: UInt64) { put32le(UInt32(v & 0xFFFF_FFFF)); put32le(UInt32(v >> 32)) }
}
