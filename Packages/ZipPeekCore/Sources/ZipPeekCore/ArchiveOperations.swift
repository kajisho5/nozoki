import Foundation

/// 「解凍する」「圧縮する」をまるごと行う（名前の決め方、フォルダのまとめ方、後片付けまで）
public struct ArchiveOperations: Sendable {
    public let sevenZip: SevenZip?

    public init(sevenZip: SevenZip?) { self.sevenZip = sevenZip }

    // MARK: - 解凍

    /// archive を folder の中に解凍する。
    /// - groupIntoFolder: 中身が複数なら「圧縮ファイルの名前のフォルダ」にまとめる。1つならそのまま置く
    /// - Returns: できたファイルまたはフォルダ
    @discardableResult
    public func extractAll(_ rawArchive: URL, into folder: URL, password: String?, groupIntoFolder: Bool = true,
                           onProgress: @escaping @Sendable (Double) -> Void = { _ in },
                           isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> [URL] {
        let archive = ArchiveKind.firstVolume(of: rawArchive)
        let fm = FileManager.default
        let temp = folder.appendingPathComponent(".zippeek-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        var success = false
        defer { if !success { try? fm.removeItem(at: temp) } }

        if try !extractZipNatively(archive, to: temp, onProgress: onProgress, isCancelled: isCancelled) {
            guard let sevenZip else { throw SevenZipError.notFound }
            try sevenZip.extract(archive, to: temp, password: password, onProgress: onProgress, isCancelled: isCancelled)
        }
        Self.removeMacJunk(in: temp)

        let items = try fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
        var results: [URL] = []
        if items.isEmpty {
            try fm.removeItem(at: temp)
        } else if items.count == 1 || !groupIntoFolder {
            for item in items {
                let target = Extractor.uniqueURL(folder.appendingPathComponent(item.lastPathComponent))
                try fm.moveItem(at: item, to: target)
                results.append(target)
            }
            try? fm.removeItem(at: temp)
        } else {
            let target = Extractor.uniqueURL(folder.appendingPathComponent(ArchiveKind.baseName(of: archive)))
            try fm.moveItem(at: temp, to: target)
            results.append(target)
        }
        success = true
        return results
    }

    /// 暗号のない普通のzipは自前で解凍する（日本語Windowsの名前も正しく読めるため）。
    /// 自前で扱えないときは false を返し、7-Zipに任せる
    func extractZipNatively(_ archive: URL, to temp: URL, onProgress: @escaping @Sendable (Double) -> Void,
                            isCancelled: @escaping @Sendable () -> Bool) throws -> Bool {
        guard ArchiveKind.isZip(archive), let listing = try? ArchiveListing.load(url: archive),
              listing.summary.encryptedCount == 0 else { return false }
        let jobs = listing.allFiles.compactMap { item -> Extractor.Job? in
            guard let idx = item.entryIndex else { return nil }
            return Extractor.Job(entryIndex: idx, name: item.name, size: item.size, isEncrypted: false, relativePath: item.path)
        }
        // フォルダだけのzipも、フォルダを作っておく
        for f in listing.root.children ?? [] {
            try? FileManager.default.createDirectory(at: temp.appendingPathComponent(f.path), withIntermediateDirectories: true)
        }
        do {
            try Extractor(zipURL: archive).extract(jobs, into: temp, onProgress: { p in
                if p.totalBytes > 0 { onProgress(Double(p.doneBytes) / Double(p.totalBytes)) }
            }, isCancelled: isCancelled)
        } catch ExtractError.cancelled {
            throw SevenZipError.cancelled
        } catch ExtractError.openFailed {
            return false
        }
        return true
    }

    static func removeMacJunk(in folder: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: folder.appendingPathComponent("__MACOSX"))
        guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in e where url.lastPathComponent.hasPrefix("._") || url.lastPathComponent == ".DS_Store" {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - 一部だけ解凍（中身を見る窓から）

    /// 7-Zipで扱う形式（7z・rar、パスワード付きzipなど）から、選んだものだけ取り出す
    @discardableResult
    public func extractSelected(_ archive: URL, files: [(item: ArchiveItem, relativePath: String)], into folder: URL,
                                password: String?,
                                onProgress: @escaping @Sendable (Double) -> Void = { _ in },
                                isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> [URL] {
        guard let sevenZip else { throw SevenZipError.notFound }
        let fm = FileManager.default
        let temp = folder.appendingPathComponent(".zippeek-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temp) }
        let paths = files.compactMap { $0.item.archivePath }
        try sevenZip.extract(ArchiveKind.firstVolume(of: archive), to: temp, password: password, only: paths,
                             onProgress: onProgress, isCancelled: isCancelled)
        var results: [URL] = []
        for f in files {
            guard let ap = f.item.archivePath else { continue }
            let src = temp.appendingPathComponent(ArchiveListing.normalize(ap))
            guard fm.fileExists(atPath: src.path) else { continue }
            let target = Extractor.uniqueURL(folder.appendingPathComponent(Extractor.safeRelativePath(f.relativePath)))
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: src, to: target)
            results.append(target)
        }
        return results
    }

    // MARK: - 圧縮

    /// 圧縮後のファイル名。1つならその名前、複数なら「アーカイブ」
    public static func archiveName(for inputs: [URL], options: CompressOptions) -> String {
        let stem = inputs.count == 1 ? inputs[0].lastPathComponent : tr("アーカイブ", "Archive")
        return stem + "." + options.fileExtension
    }

    /// inputs を圧縮して folder に置く。folder が nil なら最初の入力と同じ場所
    @discardableResult
    public func compress(_ inputs: [URL], into folder: URL? = nil, options: CompressOptions,
                         onProgress: @escaping @Sendable (Double) -> Void = { _ in },
                         isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> [URL] {
        guard let sevenZip else { throw SevenZipError.notFound }
        guard let first = inputs.first else { return [] }
        let fm = FileManager.default
        let dir = folder ?? first.deletingLastPathComponent()
        let name = Self.archiveName(for: inputs, options: options)
        var output = Extractor.uniqueURL(dir.appendingPathComponent(name))
        let split = options.splitSize != nil && !(options.windowsNames && options.format == .zip)
        if split {
            // 分割では 名前.zip.001 ができるので、そちらの重なりも避ける
            var n = 2
            while fm.fileExists(atPath: output.path + ".001") {
                let base = (name as NSString).deletingPathExtension
                output = dir.appendingPathComponent("\(base) \(n).\(options.fileExtension)")
                n += 1
            }
        }

        let useRewrite = options.format == .zip && options.windowsNames
        let workOutput = useRewrite ? dir.appendingPathComponent(".zippeek-\(UUID().uuidString).zip") : output
        do {
            try sevenZip.compress(inputs, to: workOutput, options: options, onProgress: { p in onProgress(p * (useRewrite ? 0.9 : 1)) },
                                  isCancelled: isCancelled)
            if useRewrite {
                try ZipNameRewriter.rewrite(workOutput, to: output) { name in
                    String(data: Data(name.utf8), encoding: .utf8)?.data(using: NameEncoding.shiftJIS.stringEncoding)
                }
                try? fm.removeItem(at: workOutput)
                onProgress(1)
            }
        } catch {
            try? fm.removeItem(at: workOutput)
            if useRewrite { try? fm.removeItem(at: output) }
            // 分割の途中のファイルや、7-Zipの作業用ファイル（名前.tmp など）も消す
            if let parts = try? fm.contentsOfDirectory(atPath: dir.path) {
                for p in parts where p.hasPrefix(output.lastPathComponent + ".") || p.hasPrefix(workOutput.lastPathComponent + ".") {
                    try? fm.removeItem(at: dir.appendingPathComponent(p))
                }
            }
            throw error
        }

        if split, let parts = try? fm.contentsOfDirectory(atPath: dir.path) {
            let made = parts.filter { $0.hasPrefix(output.lastPathComponent + ".") }.sorted()
            if !made.isEmpty { return made.map { dir.appendingPathComponent($0) } }
        }
        return [output]
    }
}
