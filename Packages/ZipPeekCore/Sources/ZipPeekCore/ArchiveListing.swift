import Foundation

/// 画面に並べる1行（ファイルまたはフォルダ）
public struct ArchiveItem: Identifiable, Hashable, Sendable {
    /// フォルダは "d:パス"、ファイルは "f:パス"
    public let id: String
    /// 表示用のパス（区切りは / 、末尾の / なし）
    public let path: String
    public let name: String
    public let isFolder: Bool
    public let size: UInt64
    public let packedSize: UInt64
    public let modified: Date?
    public let isEncrypted: Bool
    /// zipなら目次の番号（ZIPFoundationで取り出すとき使う）。フォルダは nil
    public let entryIndex: Int?
    /// 圧縮ファイルの中に書かれているままのパス（7-Zipで取り出すとき使う）
    public let archivePath: String?
    /// フォルダなら配下のファイル数
    public let fileCount: Int

    /// 拡張子（小文字）
    public var fileExtension: String {
        guard !isFolder, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }

    /// 親フォルダのパス（最上位なら ""）
    public var parentPath: String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }
}

/// サイドバー用のフォルダの木
public struct FolderNode: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let fileCount: Int
    public let totalSize: UInt64
    /// 子フォルダがない場合は nil（SwiftUIの階層表示がそのまま使える形）
    public let children: [FolderNode]?
}

public struct ArchiveSummary: Sendable, Equatable {
    public let fileCount: Int
    public let folderCount: Int
    public let totalSize: UInt64
    public let packedSize: UInt64
    public let encryptedCount: Int
}

/// 形式に関係ない「中の1件」。zipの目次や7-Zipの一覧からこれを作る
public struct RawEntry: Sendable, Hashable {
    public var path: String
    public var isDirectory: Bool
    public var size: UInt64
    public var packedSize: UInt64
    public var modified: Date?
    public var isEncrypted: Bool
    public var entryIndex: Int?
    public var archivePath: String?

    public init(path: String, isDirectory: Bool, size: UInt64, packedSize: UInt64, modified: Date?,
                isEncrypted: Bool, entryIndex: Int? = nil, archivePath: String? = nil) {
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.packedSize = packedSize
        self.modified = modified
        self.isEncrypted = isEncrypted
        self.entryIndex = entryIndex
        self.archivePath = archivePath
    }
}

/// 目次の読み取り結果を、画面で使いやすい形にまとめたもの
public struct ArchiveListing: Sendable {
    /// どの仕組みで読んだか（取り出し方が変わる）
    public enum Source: Sendable, Equatable {
        /// 自前でzipの目次を読んだ（ZIPFoundationで取り出せる）
        case zip
        /// 7-Zipで一覧を取った（7-Zipで取り出す）
        case sevenZip
    }

    public let source: Source
    /// zipのときだけ入る（文字コードの切り替えに使う）
    public let entries: [ZipEntry]
    public let encoding: NameEncoding
    public let detectedEncoding: NameEncoding
    public let root: FolderNode
    public let summary: ArchiveSummary
    private let childrenByFolder: [String: [ArchiveItem]]
    public let allFiles: [ArchiveItem]
    /// 文字コードの指定で名前が変わる（Windowsで作ったzipなど）かどうか
    public let hasLegacyNames: Bool

    /// zipを開いて目次を読む。encoding が nil なら自動判定
    public static func load(url: URL, encoding: NameEncoding? = nil) throws -> ArchiveListing {
        let entries = try ZipDirectory.read(url: url)
        return build(entries: entries, encoding: encoding)
    }

    /// zipの目次から作る
    public static func build(entries: [ZipEntry], encoding forced: NameEncoding? = nil) -> ArchiveListing {
        let detected = NameEncoding.detect(entries)
        let encoding = forced ?? detected
        let legacy = entries.contains { !$0.isUTF8Flagged && $0.unicodeName == nil && !$0.rawName.isASCII }
        let raw = entries.map { e in
            RawEntry(path: e.name(using: encoding), isDirectory: e.looksLikeDirectory, size: e.size,
                     packedSize: e.packedSize, modified: e.modified, isEncrypted: e.isEncrypted, entryIndex: e.index)
        }
        return build(raw: raw, source: .zip, entries: entries, encoding: encoding, detected: detected, legacy: legacy)
    }

    /// 7-Zipの一覧などから作る
    public static func build(raw: [RawEntry]) -> ArchiveListing {
        build(raw: raw, source: .sevenZip, entries: [], encoding: .utf8, detected: .utf8, legacy: false)
    }

    static func build(raw: [RawEntry], source: Source, entries: [ZipEntry], encoding: NameEncoding,
                      detected: NameEncoding, legacy: Bool) -> ArchiveListing {
        final class Folder {
            let name: String
            let path: String
            var folders: [String: Folder] = [:]
            var files: [ArchiveItem] = []
            var explicitDate: Date?
            init(name: String, path: String) { self.name = name; self.path = path }
        }
        let rootFolder = Folder(name: "", path: "")

        func folder(for components: [Substring]) -> Folder {
            var current = rootFolder
            var path = ""
            for c in components {
                path = path.isEmpty ? String(c) : path + "/" + c
                if let f = current.folders[String(c)] {
                    current = f
                } else {
                    let f = Folder(name: String(c), path: path)
                    current.folders[String(c)] = f
                    current = f
                }
            }
            return current
        }

        var encryptedCount = 0
        for entry in raw {
            let path = Self.normalize(entry.path)
            if path.isEmpty || Self.isHiddenJunk(path) { continue }
            let parts = path.split(separator: "/")
            if entry.isDirectory {
                folder(for: parts).explicitDate = entry.modified
                continue
            }
            guard let fileName = parts.last else { continue }
            let parent = folder(for: Array(parts.dropLast()))
            if entry.isEncrypted { encryptedCount += 1 }
            parent.files.append(ArchiveItem(
                id: "f:" + path, path: path, name: String(fileName), isFolder: false,
                size: entry.size, packedSize: entry.packedSize, modified: entry.modified,
                isEncrypted: entry.isEncrypted, entryIndex: entry.entryIndex,
                archivePath: entry.archivePath ?? entry.path, fileCount: 0))
        }

        var childrenByFolder: [String: [ArchiveItem]] = [:]
        var allFiles: [ArchiveItem] = []
        var folderCount = 0

        func finish(_ f: Folder) -> (node: FolderNode, item: ArchiveItem?, count: Int, size: UInt64, packed: UInt64, latest: Date?) {
            var rows: [ArchiveItem] = []
            var childNodes: [FolderNode] = []
            var count = f.files.count
            var size = f.files.reduce(UInt64(0)) { $0 + $1.size }
            var packed = f.files.reduce(UInt64(0)) { $0 + $1.packedSize }
            var latest = f.files.compactMap(\.modified).max()
            for sub in f.folders.values.sorted(by: { Self.nameOrder($0.name, $1.name) }) {
                let r = finish(sub)
                childNodes.append(r.node)
                if let item = r.item { rows.append(item) }
                count += r.count; size += r.size; packed += r.packed
                if let d = r.latest { latest = max(latest ?? d, d) }
            }
            let files = f.files.sorted { Self.nameOrder($0.name, $1.name) }
            rows.append(contentsOf: files)
            allFiles.append(contentsOf: files)
            childrenByFolder[f.path] = rows
            let node = FolderNode(name: f.name, path: f.path, fileCount: count, totalSize: size,
                                  children: childNodes.isEmpty ? nil : childNodes)
            var item: ArchiveItem?
            if !f.path.isEmpty {
                folderCount += 1
                item = ArchiveItem(id: "d:" + f.path, path: f.path, name: f.name, isFolder: true,
                                   size: size, packedSize: packed, modified: f.explicitDate ?? latest,
                                   isEncrypted: false, entryIndex: nil, archivePath: nil, fileCount: count)
            }
            return (node, item, count, size, packed, latest)
        }

        let r = finish(rootFolder)
        let summary = ArchiveSummary(fileCount: r.count, folderCount: folderCount,
                                     totalSize: r.size, packedSize: r.packed, encryptedCount: encryptedCount)
        return ArchiveListing(source: source, entries: entries, encoding: encoding, detectedEncoding: detected,
                              root: r.node, summary: summary, childrenByFolder: childrenByFolder,
                              allFiles: allFiles.sorted { $0.path < $1.path }, hasLegacyNames: legacy)
    }

    /// フォルダ直下の行
    public func items(in folderPath: String) -> [ArchiveItem] {
        childrenByFolder[folderPath] ?? []
    }

    /// 名前の部分一致で全ファイルから探す（大文字小文字・全角半角を区別しない）
    public func search(_ query: String) -> [ArchiveItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allFiles.filter {
            $0.name.range(of: q, options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// 選んだ行を、取り出すファイルの一覧に展開する（フォルダは配下全部）。
    /// relativePath は「選んだもの」を起点にした相対パス
    public func files(for selection: [ArchiveItem]) -> [(item: ArchiveItem, relativePath: String)] {
        var result: [(ArchiveItem, String)] = []
        var seen = Set<String>()
        for item in selection {
            if item.isFolder {
                let prefix = item.path + "/"
                let base = item.parentPath.isEmpty ? "" : item.parentPath + "/"
                for f in allFiles where f.path.hasPrefix(prefix) {
                    guard seen.insert(f.id).inserted else { continue }
                    result.append((f, String(f.path.dropFirst(base.count))))
                }
            } else if seen.insert(item.id).inserted {
                result.append((item, item.name))
            }
        }
        return result
    }

    // MARK: - 内部

    static func normalize(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "\\", with: "/")
        while s.hasPrefix("/") || s.hasPrefix("./") { s.removeFirst(s.hasPrefix("/") ? 1 : 2) }
        let parts = s.split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." && $0 != ".." }
        return parts.joined(separator: "/")
    }

    /// Macのzipに混ざる管理用データ（__MACOSX フォルダ）は見せない
    static func isHiddenJunk(_ path: String) -> Bool {
        path == "__MACOSX" || path.hasPrefix("__MACOSX/")
    }

    /// Finderに近い並び（数字は数として比べる：clip_2 < clip_10）
    static func nameOrder(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.numeric, .caseInsensitive, .widthInsensitive]) == .orderedAscending
    }
}
