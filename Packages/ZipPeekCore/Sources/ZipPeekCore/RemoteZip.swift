import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ネットの先にある zip を、ダウンロードせずにのぞく。
/// zip は末尾に目次を持つので、「途中から読む」要求（HTTP の Range）で末尾と目次だけを取り寄せる。
/// 取り出すときも、選んだファイルの部分だけを取り寄せる
public final class RemoteZip: @unchecked Sendable {
    public enum Failure: LocalizedError, Equatable {
        case badURL, noRangeSupport, http(Int), network(String), encrypted, notZip

        public var errorDescription: String? {
            switch self {
            case .badURL: return tr("リンクの形が正しくありません。https:// で始まる、zip ファイルそのもののリンクを入れてください。", "That link isn’t valid. Enter a link that starts with https:// and points directly to a ZIP file.")
            case .noRangeSupport: return tr("このリンク先は、ファイルの一部だけを読む仕組みに対応していないため、のぞけません。普通にダウンロードしてください。", "This server doesn’t let apps read part of a file, so ZipPeek can’t look inside without downloading it.")
            case .http(let code): return tr("リンク先から読めませんでした（HTTP \(code)）。リンクの期限が切れていないか確かめてください。", "Couldn’t read from the link (HTTP \(code)). Check that the link hasn’t expired.")
            case .network(let m): return tr("通信できませんでした。", "Couldn’t connect.") + "\n" + m
            case .encrypted: return tr("パスワード付きのファイルは、リンクのままでは取り出せません。ダウンロードしてから開いてください。", "Password-protected files can’t be taken out from a link. Download the archive first.")
            case .notZip: return tr("リンクのままのぞけるのは zip だけです。", "Only ZIP archives can be opened from a link.")
            }
        }
    }

    public let url: URL
    public private(set) var size: UInt64 = 0
    public private(set) var entries: [ZipEntry] = []
    private var cd = Data()
    private let session: URLSession
    /// 取り寄せた量（画面の表示用）
    public private(set) var bytesFetched: UInt64 = 0

    public init(url: URL, session: URLSession = .shared) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host != nil else {
            throw Failure.badURL
        }
        self.url = url
        self.session = session
    }

    /// 末尾と目次を読む（通信が起きるので、画面の処理とは別の作業列で呼ぶ）
    public func load() throws {
        // まず末尾を取り寄せ、ついでにファイル全体の大きさを知る
        let tailWant = 65_535 + 22
        let (tail, total) = try fetch(range: "bytes=-\(tailWant)")
        size = total
        let source = Source(owner: self, tail: tail, tailStart: total - UInt64(tail.count))
        do {
            let r = try ZipDirectory.read(source)
            entries = r.entries
            cd = r.cd
        } catch ZipReadError.notAZip {
            throw Failure.notZip
        }
    }

    /// 1件を destination フォルダに取り出す。書き出したファイルを返す
    public func extract(_ entry: ZipEntry, as relativePath: String, into destination: URL,
                        isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> URL {
        guard !entry.isEncrypted else { throw Failure.encrypted }
        // ローカルヘッダー（30バイト＋名前＋追加情報）の長さを知る
        let (head, _) = try fetch(range: "bytes=\(entry.localHeaderOffset)-\(entry.localHeaderOffset + 29)")
        guard head.count == 30, head.u32(0) == 0x0403_4b50 else { throw ZipReadError.truncated }
        let headerLen = 30 + UInt64(head.u16(26)) + UInt64(head.u16(28))
        var end = entry.localHeaderOffset + headerLen + entry.packedSize
        if entry.hasDataDescriptor { end += 24 }
        end = min(end, size) - 1
        if isCancelled() { throw SevenZipError.cancelled }
        let (body, _) = try fetch(range: "bytes=\(entry.localHeaderOffset)-\(end)")

        // 取り寄せた部分に目次を付けて「1件だけの zip」を作り、いつもの取り出し処理に渡す
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("zippeek-remote-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: work) }
        try Self.singleEntryZip(local: body, record: cd.subdata(in: entry.centralRecordRange),
                                zip64OffsetField: entry.localOffsetFieldInZip64).write(to: work)
        let job = Extractor.Job(entryIndex: 0, name: (relativePath as NSString).lastPathComponent, size: entry.size,
                                isEncrypted: false, relativePath: relativePath)
        let written = try Extractor(zipURL: work).extract([job], into: destination, isCancelled: isCancelled)
        guard let out = written.first else { throw ZipReadError.truncated }
        return out
    }

    /// 本体（ローカルヘッダーから）＋その項目の目次の記録＋目次の終わり、で1件だけの zip を組み立てる
    static func singleEntryZip(local: Data, record: Data, zip64OffsetField: Int?) -> Data {
        var rec = record
        // 本体はこの zip の先頭にあるので、位置を 0 に書き換える
        if let f = zip64OffsetField {
            for i in 0..<8 { rec[rec.startIndex + f + i] = 0 }
        } else {
            for i in 0..<4 { rec[rec.startIndex + 42 + i] = 0 }
        }
        var out = local
        let cdOffset = UInt64(out.count)
        out.append(rec)
        func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
        func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        func le64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xFF) } }
        let needs64 = cdOffset >= 0xFFFF_FFFF
        if needs64 {
            let z64At = UInt64(out.count)
            out.append(contentsOf: le32(0x0606_4b50) + le64(44) + le16(45) + le16(45) + le32(0) + le32(0)
                       + le64(1) + le64(1) + le64(UInt64(rec.count)) + le64(cdOffset))
            out.append(contentsOf: le32(0x0706_4b50) + le32(0) + le64(z64At) + le32(1))
        }
        out.append(contentsOf: le32(0x0605_4b50) + le16(0) + le16(0) + le16(1) + le16(1)
                   + le32(UInt32(rec.count)) + le32(needs64 ? 0xFFFF_FFFF : UInt32(cdOffset)) + le16(0))
        return out
    }

    // MARK: - 通信

    /// Range 付きで取り寄せる。返り値は（中身, ファイル全体の大きさ）
    func fetch(range: String) throws -> (Data, UInt64) {
        var req = URLRequest(url: url)
        req.setValue(range, forHTTPHeaderField: "Range")
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding") // 途中から読むので、通信の圧縮はしない
        req.timeoutInterval = 60
        let box = ResultBox()
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: req) { data, response, error in
            box.data = data; box.response = response; box.error = error
            sem.signal()
        }.resume()
        sem.wait()
        if let e = box.error { throw Failure.network(e.localizedDescription) }
        guard let http = box.response as? HTTPURLResponse, let data = box.data else { throw Failure.network("") }
        if http.statusCode == 200 { throw Failure.noRangeSupport }
        guard http.statusCode == 206 else { throw Failure.http(http.statusCode) }
        // Content-Range: bytes 100-199/12345
        guard let cr = http.value(forHTTPHeaderField: "Content-Range"), let slash = cr.lastIndex(of: "/"),
              let total = UInt64(cr[cr.index(after: slash)...]) else { throw Failure.noRangeSupport }
        bytesFetched += UInt64(data.count)
        return (data, total)
    }

    private final class ResultBox: @unchecked Sendable {
        var data: Data?
        var response: URLResponse?
        var error: Error?
    }

    /// 目次を読むための読み元。末尾はすでに手元にあるので、それ以外だけ取り寄せる
    private struct Source: ZipByteSource {
        let owner: RemoteZip
        let tail: Data
        let tailStart: UInt64
        var size: UInt64 { owner.size }

        func bytes(at offset: UInt64, count: Int) throws -> Data {
            guard offset + UInt64(count) <= size else { throw ZipReadError.truncated }
            if offset >= tailStart {
                let s = Int(offset - tailStart)
                return tail.subdata(in: s..<(s + count))
            }
            if count == 0 { return Data() }
            let (d, _) = try owner.fetch(range: "bytes=\(offset)-\(offset + UInt64(count) - 1)")
            guard d.count == count else { throw ZipReadError.truncated }
            return d
        }
    }
}
