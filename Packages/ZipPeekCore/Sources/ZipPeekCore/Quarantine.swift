import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// ネットから来た印（com.apple.quarantine）を、解凍したものにも付ける。
/// 付けないと、ダウンロードした zip の中のアプリが Mac の安全確認（Gatekeeper）を通らずに開けてしまう
public enum Quarantine {
    static let name = "com.apple.quarantine"

    /// archive に印があれば、その値を items（フォルダは中まで）に付ける
    public static func propagate(from archive: URL, to items: [URL]) {
        #if os(macOS)
        guard let value = read(archive) else { return }
        let fm = FileManager.default
        for item in items {
            write(value, to: item)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue,
                  let e = fm.enumerator(at: item, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in e { write(value, to: url) }
        }
        #endif
    }

    /// 印の中身（なければ nil）
    public static func read(_ url: URL) -> Data? {
        #if os(macOS)
        let size = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var buf = Data(count: size)
        let got = buf.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        return got == size ? buf : nil
        #else
        return nil
        #endif
    }

    static func write(_ value: Data, to url: URL) {
        #if os(macOS)
        _ = value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) }
        #endif
    }
}
