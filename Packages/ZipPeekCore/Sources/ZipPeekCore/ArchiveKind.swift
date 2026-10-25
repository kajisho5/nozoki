import Foundation

/// 渡されたファイルが圧縮ファイルかどうか、分割の先頭はどれかを判断する
public enum ArchiveKind {
    /// 解凍の対象として扱う拡張子（7-Zipが読めるもののうち、よく使うもの）
    public static let archiveExtensions: Set<String> = [
        "zip", "zipx", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst", "tzst",
        "lz", "tlz", "lzma", "z", "iso", "lzh", "lha", "cab", "arj", "cpio", "wim", "xar", "pkg", "rpm", "deb",
        "001", "z01", "zx01", "apfs"
    ]

    public static func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if archiveExtensions.contains(ext) { return true }
        // 分割の2番目以降（.002 .z02 .part2.rar など）も圧縮ファイル扱い
        if ext.count == 3, ext.allSatisfy(\.isNumber) { return true }
        if ext.hasPrefix("z"), ext.count == 3, ext.dropFirst().allSatisfy(\.isNumber) { return true }
        return false
    }

    /// zip（自前で目次を読める形式）かどうか
    public static func isZip(_ url: URL) -> Bool {
        ["zip", "zipx"].contains(url.pathExtension.lowercased())
    }

    /// 分割の途中のファイルを渡されたら先頭のファイルに直す
    /// - 名前.7z.003 → 名前.7z.001
    /// - 名前.part3.rar → 名前.part1.rar（同じフォルダに有れば）
    /// - 名前.z02 → 名前.zip（同じフォルダに有れば）
    public static func firstVolume(of url: URL) -> URL {
        let fm = FileManager.default
        let ext = url.pathExtension.lowercased()
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent

        if ext.count == 3, ext.allSatisfy(\.isNumber), ext != "001" {
            let first = dir.appendingPathComponent(base + ".001")
            if fm.fileExists(atPath: first.path) { return first }
        }
        if ext.hasPrefix("z"), ext.count == 3, ext.dropFirst().allSatisfy(\.isNumber) {
            let zip = dir.appendingPathComponent(base + ".zip")
            if fm.fileExists(atPath: zip.path) { return zip }
        }
        if ext == "rar", let range = base.range(of: #"\.part\d+$"#, options: [.regularExpression, .caseInsensitive]) {
            let stem = base[..<range.lowerBound]
            for candidate in ["\(stem).part1.rar", "\(stem).part01.rar", "\(stem).part001.rar"] {
                let u = dir.appendingPathComponent(candidate)
                if fm.fileExists(atPath: u.path) { return u }
            }
        }
        return url
    }

    /// 解凍先のフォルダ名（拡張子を全部外す：名前.tar.gz → 名前、名前.7z.001 → 名前）
    public static func baseName(of url: URL) -> String {
        var name = url.lastPathComponent
        let strip = ["001", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst", "tzst", "lz", "tlz", "7z", "zip", "zipx", "rar"]
        var changed = true
        while changed {
            changed = false
            let ext = (name as NSString).pathExtension.lowercased()
            if !ext.isEmpty, strip.contains(ext) || (ext.count == 3 && ext.allSatisfy(\.isNumber)) {
                name = (name as NSString).deletingPathExtension
                changed = true
            }
        }
        if let r = name.range(of: #"\.part\d+$"#, options: [.regularExpression, .caseInsensitive]) {
            name.removeSubrange(r)
        }
        return name.isEmpty ? tr("解凍したファイル", "Extracted") : name
    }
}
