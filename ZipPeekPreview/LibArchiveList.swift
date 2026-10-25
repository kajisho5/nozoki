import Foundation
import Darwin
import ZipPeekCore

/// 7z・rar・tar などの中身の一覧を、macOS に入っている libarchive で読む。
/// スペースキーの部品（クイックルック拡張）は、サンドボックスの決まりで別のプログラム（7zz）を起動できないため、
/// 部品の中だけで読む。ヘッダー（目次）だけを読み、ファイルの中身は書き出さない。
/// 公開のヘッダーファイルに頼らないよう、関数は名前で探して呼ぶ。
enum LibArchiveList {
    enum Failure: LocalizedError {
        case unavailable, open(String), read(String), tooSlow
        var errorDescription: String? {
            switch self {
            case .unavailable: tr("この Mac では、スペースキーでこの形式を読めません。ZipPeek で開いてください。", "This Mac can’t read this format with the Space key. Open it in ZipPeek.")
            case .open(let m), .read(let m): m.isEmpty ? tr("中身を読めませんでした。", "Couldn’t read the contents.") : m
            case .tooSlow: tr("大きすぎて、スペースキーでは一覧を作れません。ZipPeek で開いてください。", "This archive is too large to list with the Space key. Open it in ZipPeek.")
            }
        }
    }

    private typealias NewFn = @convention(c) () -> OpaquePointer?
    private typealias IntFn = @convention(c) (OpaquePointer?) -> Int32
    private typealias OpenFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int) -> Int32
    private typealias NextFn = @convention(c) (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>?) -> Int32
    private typealias StrFn = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
    private typealias I64Fn = @convention(c) (OpaquePointer?) -> Int64
    private typealias ModeFn = @convention(c) (OpaquePointer?) -> UInt16
    private typealias TimeFn = @convention(c) (OpaquePointer?) -> Int
    private typealias WStrFn = @convention(c) (OpaquePointer?) -> UnsafePointer<wchar_t>?

    nonisolated(unsafe) private static let lib: UnsafeMutableRawPointer? = dlopen("/usr/lib/libarchive.2.dylib", RTLD_NOW | RTLD_LOCAL)
    private static func fn<T>(_ name: String, _: T.Type) -> T? {
        guard let lib, let p = dlsym(lib, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    /// 目次を読んで、一覧の材料を返す。timeLimit 秒を超えたら（tar.gz の巨大なものなど）あきらめる
    static func entries(_ url: URL, timeLimit: TimeInterval = 4) throws -> [RawEntry] {
        guard let new = fn("archive_read_new", NewFn.self),
              let filters = fn("archive_read_support_filter_all", IntFn.self),
              let formats = fn("archive_read_support_format_all", IntFn.self),
              let open = fn("archive_read_open_filename", OpenFn.self),
              let next = fn("archive_read_next_header", NextFn.self),
              let skip = fn("archive_read_data_skip", IntFn.self),
              let free = fn("archive_read_free", IntFn.self),
              let errStr = fn("archive_error_string", StrFn.self),
              let pathUTF8 = fn("archive_entry_pathname_utf8", StrFn.self),
              let path = fn("archive_entry_pathname", StrFn.self),
              let pathW = fn("archive_entry_pathname_w", WStrFn.self),
              let size = fn("archive_entry_size", I64Fn.self),
              let fileType = fn("archive_entry_filetype", ModeFn.self),
              let mtime = fn("archive_entry_mtime", TimeFn.self),
              let mtimeSet = fn("archive_entry_mtime_is_set", IntFn.self)
        else { throw Failure.unavailable }
        let encrypted = fn("archive_entry_is_encrypted", IntFn.self)

        // 7z などは名前を UTF-16 で持つ。文字の変換に UTF-8 の決まり（ロケール）が要るので、この処理の間だけ切り替える
        var utf8Locale: locale_t?
        for name in ["en_US.UTF-8", "C.UTF-8", "UTF-8"] {
            if let l = newlocale(LC_CTYPE_MASK, name, nil) { utf8Locale = l; break }
        }
        let previous = utf8Locale.map { uselocale($0) }
        defer {
            if let previous { uselocale(previous) }
            if let utf8Locale { freelocale(utf8Locale) }
        }

        guard let a = new() else { throw Failure.unavailable }
        defer { _ = free(a) }
        _ = filters(a); _ = formats(a)
        func message() -> String { errStr(a).map { String(cString: $0) } ?? "" }
        guard open(a, url.path, 65536) == 0 else { throw Failure.open(message()) }

        let start = Date()
        var out: [RawEntry] = []
        var entry: OpaquePointer?
        var index = 0
        while true {
            let r = next(a, &entry)
            if r == 1 { break }                    // 終わり
            if r < -20 {  // 失敗・致命的
                let m = message()
                if m.localizedCaseInsensitiveContains("encrypt") || m.localizedCaseInsensitiveContains("passphrase") {
                    throw Failure.read(tr("ファイル名までパスワードで隠されています。ZipPeek で開いてパスワードを入れてください。",
                                          "The file names are protected by a password. Open it in ZipPeek and enter the password."))
                }
                throw Failure.read(m)
            }
            guard let e = entry else { break }
            // 名前は文字の種類（ロケール）に左右されない形で受け取る：ワイド文字 → UTF-8 → そのまま、の順
            var name = pathW(e).map { Self.string(wide: $0) } ?? ""
            if name.isEmpty { name = pathUTF8(e).map { String(cString: $0) } ?? "" }
            if name.isEmpty { name = path(e).map { String(cString: $0) } ?? "" }
            let isDir = (fileType(e) & 0o170000) == 0o040000 || name.hasSuffix("/")
            out.append(RawEntry(path: name, isDirectory: isDir, size: UInt64(max(0, size(e))), packedSize: 0,
                                modified: mtimeSet(e) != 0 ? Date(timeIntervalSince1970: TimeInterval(mtime(e))) : nil,
                                isEncrypted: (encrypted?(e) ?? 0) > 0, entryIndex: index))
            index += 1
            if Date().timeIntervalSince(start) > timeLimit { throw Failure.tooSlow }
            _ = skip(a)
        }
        return out
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
}
