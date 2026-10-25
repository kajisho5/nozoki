import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// OS に入っている libarchive を使う係。
/// - スペースキーの部品（サンドボックスの中では 7zz を起動できない）で、7z・rar・tar の目次を読む
/// - 7-Zip が扱えない zstd（.zst・.tar.zst）と lzip（.lz）の解凍、.tar.zst の作成
/// 公開のヘッダーファイルに頼らないよう、関数は名前で探して呼ぶ（無ければ「使えない」と返す）
public enum LibArchive {
    public enum Failure: LocalizedError, Equatable {
        case unavailable, open(String), read(String), write(String), tooSlow, cancelled
        public var errorDescription: String? {
            switch self {
            case .unavailable: return tr("この Mac では、この形式を扱えません。", "This Mac can’t handle this format.")
            case .open(let m), .read(let m), .write(let m):
                return m.isEmpty ? tr("中身を読めませんでした。", "Couldn’t read the contents.") : m
            case .tooSlow: return tr("大きすぎて、スペースキーでは一覧を作れません。ZipPeek で開いてください。", "This archive is too large to list with the Space key. Open it in ZipPeek.")
            case .cancelled: return tr("中止しました。", "Cancelled.")
            }
        }
    }

    /// libarchive に任せる拡張子（7-Zip が読めないもの）
    public static let extensions: Set<String> = ["zst", "tzst", "lz", "tlz"]

    public static func handles(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    // MARK: - 関数の取り寄せ

    private typealias NewFn = @convention(c) () -> OpaquePointer?
    private typealias IntFn = @convention(c) (OpaquePointer?) -> Int32
    private typealias Int2Fn = @convention(c) (OpaquePointer?, Int32) -> Int32
    private typealias OpenFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int) -> Int32
    private typealias WOpenFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    private typealias NextFn = @convention(c) (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>?) -> Int32
    private typealias StrFn = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
    private typealias WStrFn = @convention(c) (OpaquePointer?) -> UnsafePointer<wchar_t>?
    private typealias I64Fn = @convention(c) (OpaquePointer?) -> Int64
    private typealias ModeFn = @convention(c) (OpaquePointer?) -> UInt32
    private typealias TimeFn = @convention(c) (OpaquePointer?) -> Int
    private typealias SetStrFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Void
    private typealias SetI64Fn = @convention(c) (OpaquePointer?, Int64) -> Void
    private typealias SetModeFn = @convention(c) (OpaquePointer?, UInt32) -> Void
    private typealias SetTimeFn = @convention(c) (OpaquePointer?, Int, Int) -> Void
    private typealias FreeEntryFn = @convention(c) (OpaquePointer?) -> Void
    private typealias ReadBlockFn = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UnsafeRawPointer?>?,
                                                    UnsafeMutablePointer<Int>?, UnsafeMutablePointer<Int64>?) -> Int32
    private typealias WriteBlockFn = @convention(c) (OpaquePointer?, UnsafeRawPointer?, Int, Int64) -> Int
    private typealias WriteDataFn = @convention(c) (OpaquePointer?, UnsafeRawPointer?, Int) -> Int
    private typealias HeaderFn = @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32

    #if canImport(Darwin)
    private static let path = "/usr/lib/libarchive.2.dylib"
    #else
    private static let path = "libarchive.so.13"
    #endif
    nonisolated(unsafe) private static let lib: UnsafeMutableRawPointer? = dlopen(path, RTLD_NOW | RTLD_LOCAL)

    private static func fn<T>(_ name: String, _: T.Type) -> T? {
        guard let lib, let p = dlsym(lib, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    /// 7z などは名前を UTF-16 で持つ。名前の変換に UTF-8 の決まり（ロケール）が要るので、処理の間だけ切り替える
    private static func withUTF8Locale<T>(_ body: () throws -> T) rethrows -> T {
        var loc: locale_t?
        for name in ["en_US.UTF-8", "C.UTF-8", "UTF-8"] {
            if let l = newlocale(LC_CTYPE_MASK, name, nil) { loc = l; break }
        }
        let previous = loc.map { uselocale($0) }
        defer {
            if let previous { uselocale(previous) }
            if let loc { freelocale(loc) }
        }
        return try body()
    }

    private static func string(wide p: UnsafePointer<wchar_t>) -> String {
        var scalars = String.UnicodeScalarView()
        var q = p
        while q.pointee != 0 {
            if let u = Unicode.Scalar(UInt32(bitPattern: Int32(q.pointee))) { scalars.append(u) }
            q += 1
        }
        return String(scalars)
    }

    /// 読み取りの準備（全部の形式・圧縮方式を受け付ける。zstd 単体の .zst のように「中身1つ」も読む）
    private struct Reader {
        let a: OpaquePointer
        let next: NextFn, skip: IntFn, free: IntFn, errStr: StrFn
        let pathUTF8: StrFn, pathC: StrFn, pathW: WStrFn
        let size: I64Fn, fileType: ModeFn, mtime: TimeFn, mtimeSet: IntFn, encrypted: IntFn?
        let readBlock: ReadBlockFn

        static func open(_ url: URL, raw: Bool) throws -> Reader {
            guard let new = fn("archive_read_new", NewFn.self),
                  let filters = fn("archive_read_support_filter_all", IntFn.self),
                  let formats = fn("archive_read_support_format_all", IntFn.self),
                  let rawFormat = fn("archive_read_support_format_raw", IntFn.self),
                  let open = fn("archive_read_open_filename", OpenFn.self),
                  let next = fn("archive_read_next_header", NextFn.self),
                  let skip = fn("archive_read_data_skip", IntFn.self),
                  let free = fn("archive_read_free", IntFn.self),
                  let errStr = fn("archive_error_string", StrFn.self),
                  let pathUTF8 = fn("archive_entry_pathname_utf8", StrFn.self),
                  let pathC = fn("archive_entry_pathname", StrFn.self),
                  let pathW = fn("archive_entry_pathname_w", WStrFn.self),
                  let size = fn("archive_entry_size", I64Fn.self),
                  let fileType = fn("archive_entry_filetype", ModeFn.self),
                  let mtime = fn("archive_entry_mtime", TimeFn.self),
                  let mtimeSet = fn("archive_entry_mtime_is_set", IntFn.self),
                  let readBlock = fn("archive_read_data_block", ReadBlockFn.self),
                  let a = new()
            else { throw Failure.unavailable }
            _ = filters(a); _ = formats(a)
            if raw { _ = rawFormat(a) }
            guard open(a, url.path, 65536) == 0 else {
                let m = errStr(a).map { String(cString: $0) } ?? ""
                _ = free(a)
                throw Failure.open(m)
            }
            return Reader(a: a, next: next, skip: skip, free: free, errStr: errStr, pathUTF8: pathUTF8, pathC: pathC,
                          pathW: pathW, size: size, fileType: fileType, mtime: mtime, mtimeSet: mtimeSet,
                          encrypted: fn("archive_entry_is_encrypted", IntFn.self), readBlock: readBlock)
        }

        var message: String { errStr(a).map { String(cString: $0) } ?? "" }

        func name(_ e: OpaquePointer) -> String {
            var n = pathW(e).map { LibArchive.string(wide: $0) } ?? ""
            if n.isEmpty { n = pathUTF8(e).map { String(cString: $0) } ?? "" }
            if n.isEmpty { n = pathC(e).map { String(cString: $0) } ?? "" }
            return n
        }

        func failure(_ code: Int32) -> Failure? {
            guard code < -20 else { return nil }  // -25 失敗、-30 致命的
            let m = message
            if m.localizedCaseInsensitiveContains("encrypt") || m.localizedCaseInsensitiveContains("passphrase") {
                return .read(tr("ファイル名までパスワードで隠されています。ZipPeek で開いてパスワードを入れてください。",
                                "The file names are protected by a password. Open it in ZipPeek and enter the password."))
            }
            return .read(m)
        }
    }

    // MARK: - 一覧

    /// 目次を読んで、一覧の材料を返す。timeLimit 秒を超えたら（tar.gz の巨大なものなど）あきらめる
    public static func entries(_ url: URL, timeLimit: TimeInterval = .infinity) throws -> [RawEntry] {
        try withUTF8Locale {
            let r = try Reader.open(url, raw: handles(url))
            defer { _ = r.free(r.a) }
            let start = Date()
            var out: [RawEntry] = []
            var entry: OpaquePointer?
            var index = 0
            while true {
                let code = r.next(r.a, &entry)
                if code == 1 { break }
                if let f = r.failure(code) { throw f }
                guard let e = entry else { break }
                var name = r.name(e)
                if name == "data" && handles(url) { name = rawName(for: url) } // 中身1つの .zst
                let isDir = (r.fileType(e) & 0o170000) == 0o040000 || name.hasSuffix("/")
                out.append(RawEntry(path: name, isDirectory: isDir, size: UInt64(max(0, r.size(e))), packedSize: 0,
                                    modified: r.mtimeSet(e) != 0 ? Date(timeIntervalSince1970: TimeInterval(r.mtime(e))) : nil,
                                    isEncrypted: (r.encrypted?(e) ?? 0) > 0, entryIndex: index, archivePath: name))
                index += 1
                if Date().timeIntervalSince(start) > timeLimit { throw Failure.tooSlow }
                _ = r.skip(r.a)
            }
            return out
        }
    }

    /// 中身1つの圧縮（名前.txt.zst）を解凍したときの名前
    static func rawName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        switch url.pathExtension.lowercased() {
        case "tzst", "tlz": return base + ".tar"
        default: return base
        }
    }

    // MARK: - 解凍

    /// destination（空のフォルダ）に解凍する。only を渡すとその道筋（と、その下）だけ
    public static func extract(_ url: URL, to destination: URL, only: Set<String>? = nil,
                               isCancelled: @escaping @Sendable () -> Bool = { false }) throws {
        try withUTF8Locale {
            let r = try Reader.open(url, raw: handles(url))
            defer { _ = r.free(r.a) }
            let fm = FileManager.default
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            var entry: OpaquePointer?
            while true {
                if isCancelled() { throw Failure.cancelled }
                let code = r.next(r.a, &entry)
                if code == 1 { break }
                if let f = r.failure(code) { throw f }
                guard let e = entry else { break }
                var name = r.name(e)
                if name == "data" && handles(url) { name = rawName(for: url) }
                let normalized = ArchiveListing.normalize(name)
                if let only, !only.contains(where: { normalized == $0 || normalized.hasPrefix($0 + "/") }) {
                    _ = r.skip(r.a); continue
                }
                let kind = r.fileType(e) & 0o170000
                let target = destination.appendingPathComponent(Extractor.safeRelativePath(normalized))
                if kind == 0o040000 || name.hasSuffix("/") {
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                    _ = r.skip(r.a); continue
                }
                guard kind == 0o100000 || kind == 0 else { _ = r.skip(r.a); continue } // 普通のファイルだけ（リンク等は作らない）
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard fm.createFile(atPath: target.path, contents: nil), let h = try? FileHandle(forWritingTo: target) else {
                    throw Failure.write(tr("「\(target.lastPathComponent)」を書き出せませんでした。", "Couldn’t write “\(target.lastPathComponent)”."))
                }
                defer { try? h.close() }
                var buf: UnsafeRawPointer?
                var len = 0
                var offset: Int64 = 0
                var written: Int64 = 0
                while true {
                    let c = r.readBlock(r.a, &buf, &len, &offset)
                    if c == 1 { break }
                    if let f = r.failure(c) { throw f }
                    if isCancelled() { throw Failure.cancelled }
                    if offset > written { try h.seek(toOffset: UInt64(offset)) } // 穴のあいたファイル
                    if let buf, len > 0 { try h.write(contentsOf: Data(bytes: buf, count: len)) }
                    written = offset + Int64(len)
                }
                if r.mtimeSet(e) != 0 {
                    try? fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: TimeInterval(r.mtime(e)))],
                                          ofItemAtPath: target.path)
                }
            }
        }
    }

    // MARK: - 作成（tar + zstd など）

    public enum Filter: String, Sendable { case zstd, gzip, bzip2, xz }

    /// inputs を tar にまとめ、filter で圧縮して output に書く
    public static func writeTar(_ inputs: [URL], to output: URL, filter: Filter, excludeMacFiles: Bool,
                                isCancelled: @escaping @Sendable () -> Bool = { false }) throws {
        try withUTF8Locale { try writeTarBody(inputs, to: output, filter: filter, excludeMacFiles: excludeMacFiles, isCancelled: isCancelled) }
    }

    private static func writeTarBody(_ inputs: [URL], to output: URL, filter: Filter, excludeMacFiles: Bool,
                                     isCancelled: @escaping @Sendable () -> Bool) throws {
        guard let new = fn("archive_write_new", NewFn.self),
              let addFilter = fn("archive_write_add_filter_\(filter.rawValue)", IntFn.self),
              let setFormat = fn("archive_write_set_format_pax_restricted", IntFn.self),
              let open = fn("archive_write_open_filename", WOpenFn.self),
              let header = fn("archive_write_header", HeaderFn.self),
              let writeData = fn("archive_write_data", WriteDataFn.self),
              let finishEntry = fn("archive_write_finish_entry", IntFn.self),
              let close = fn("archive_write_close", IntFn.self),
              let free = fn("archive_write_free", IntFn.self),
              let errStr = fn("archive_error_string", StrFn.self),
              let entryNew = fn("archive_entry_new", NewFn.self),
              let entryFree = fn("archive_entry_free", FreeEntryFn.self),
              let setPath = fn("archive_entry_set_pathname_utf8", SetStrFn.self) ?? fn("archive_entry_set_pathname", SetStrFn.self),
              let setSize = fn("archive_entry_set_size", SetI64Fn.self),
              let setType = fn("archive_entry_set_filetype", SetModeFn.self),
              let setPerm = fn("archive_entry_set_perm", SetModeFn.self),
              let setMtime = fn("archive_entry_set_mtime", SetTimeFn.self),
              let setLink = fn("archive_entry_set_symlink_utf8", SetStrFn.self) ?? fn("archive_entry_set_symlink", SetStrFn.self),
              let a = new()
        else { throw Failure.unavailable }
        defer { _ = free(a) }
        func message() -> String { errStr(a).map { String(cString: $0) } ?? "" }
        guard addFilter(a) == 0, setFormat(a) == 0 else { throw Failure.unavailable }
        guard open(a, output.path) == 0 else { throw Failure.write(message()) }

        let fm = FileManager.default
        func add(_ url: URL, as name: String) throws {
            if isCancelled() { throw Failure.cancelled }
            let base = url.lastPathComponent
            if excludeMacFiles, base == ".DS_Store" || base == "__MACOSX" || base.hasPrefix("._")
                || base == ".Spotlight-V100" || base == ".Trashes" || base == ".fseventsd" { return }
            let attrs = try fm.attributesOfItem(atPath: url.path)
            let type = attrs[.type] as? FileAttributeType
            guard let e = entryNew() else { throw Failure.unavailable }
            defer { entryFree(e) }
            setPath(e, name)
            setPerm(e, UInt32((attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644))
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            setMtime(e, Int(mtime), 0)
            switch type {
            case .typeDirectory?:
                setType(e, 0o040000); setSize(e, 0)
                guard header(a, e) == 0 else { throw Failure.write(message()) }
                for child in try fm.contentsOfDirectory(atPath: url.path).sorted() {
                    try add(url.appendingPathComponent(child), as: name + "/" + child)
                }
            case .typeSymbolicLink?:
                setType(e, 0o120000); setSize(e, 0)
                setLink(e, try fm.destinationOfSymbolicLink(atPath: url.path))
                guard header(a, e) == 0 else { throw Failure.write(message()) }
            default:
                setType(e, 0o100000)
                setSize(e, Int64((attrs[.size] as? NSNumber)?.int64Value ?? 0))
                guard header(a, e) == 0 else { throw Failure.write(message()) }
                let h = try FileHandle(forReadingFrom: url)
                defer { try? h.close() }
                while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty {
                    if isCancelled() { throw Failure.cancelled }
                    let n = chunk.withUnsafeBytes { writeData(a, $0.baseAddress, chunk.count) }
                    guard n == chunk.count else { throw Failure.write(message()) }
                }
            }
            _ = finishEntry(a)
        }
        for input in inputs { try add(input, as: ArchiveEdit.nfc(input.lastPathComponent)) }
        guard close(a) == 0 else { throw Failure.write(message()) }
    }

    /// この OS の libarchive が、その圧縮方式で書けるか
    public static func canWrite(_ filter: Filter) -> Bool {
        guard let new = fn("archive_write_new", NewFn.self), let free = fn("archive_write_free", IntFn.self),
              let add = fn("archive_write_add_filter_\(filter.rawValue)", IntFn.self), let a = new() else { return false }
        defer { _ = free(a) }
        return add(a) == 0
    }
}
