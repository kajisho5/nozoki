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

        if LibArchive.handles(archive) {
            // 7-Zip が読めない zstd・lzip は OS の libarchive で
            try LibArchive.extract(archive, to: temp, isCancelled: isCancelled)
        } else if try !extractZipNatively(archive, to: temp, onProgress: onProgress, isCancelled: isCancelled) {
            guard let sevenZip else { throw SevenZipError.notFound }
            try sevenZip.extract(archive, to: temp, password: password, onProgress: onProgress, isCancelled: isCancelled)
        }
        // .tar.gz などは、1回目で中の .tar が出てくるので、続けて開く
        try unpackInnerTar(of: archive, in: temp, onProgress: onProgress, isCancelled: isCancelled)
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
        Quarantine.propagate(from: archive, to: results)
        return results
    }

    /// 「圧縮された tar」（.tar.gz・.tgz・.tar.zst など）を解凍して中から .tar が1つだけ出てきたら、その中身に置き換える
    func unpackInnerTar(of archive: URL, in temp: URL, onProgress: @escaping @Sendable (Double) -> Void,
                        isCancelled: @escaping @Sendable () -> Bool) throws {
        let ext = archive.pathExtension.lowercased()
        let stem = archive.deletingPathExtension().pathExtension.lowercased()
        guard ["tgz", "tbz", "tbz2", "txz", "tzst", "tlz"].contains(ext) || stem == "tar" else { return }
        let fm = FileManager.default
        let inner = (try? fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? []
        guard inner.count == 1, inner[0].pathExtension.lowercased() == "tar", let sevenZip else { return }
        let tar = inner[0]
        let unpacked = temp.appendingPathComponent(".tar-\(UUID().uuidString)")
        try sevenZip.extract(tar, to: unpacked, password: nil, onProgress: onProgress, isCancelled: isCancelled)
        try fm.removeItem(at: tar)
        for item in try fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil) {
            try fm.moveItem(at: item, to: temp.appendingPathComponent(item.lastPathComponent))
        }
        try fm.removeItem(at: unpacked)
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
        let fm = FileManager.default
        let temp = folder.appendingPathComponent(".zippeek-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temp) }
        let paths = files.compactMap { $0.item.archivePath }
        if LibArchive.handles(archive) {
            try LibArchive.extract(archive, to: temp, only: Set(paths.map(ArchiveListing.normalize)), isCancelled: isCancelled)
        } else {
            guard let sevenZip else { throw SevenZipError.notFound }
            try sevenZip.extract(ArchiveKind.firstVolume(of: archive), to: temp, password: password, only: paths,
                                 onProgress: onProgress, isCancelled: isCancelled)
        }
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
        Quarantine.propagate(from: archive, to: results)
        return results
    }

    // MARK: - 圧縮

    /// zip・7z 以外（tar 系と dmg）。書きかけは失敗したら消す
    func compressOther(_ inputs: [URL], to output: URL, options: CompressOptions,
                       onProgress: @escaping @Sendable (Double) -> Void,
                       isCancelled: @escaping @Sendable () -> Bool) throws {
        let fm = FileManager.default
        let work = output.deletingLastPathComponent().appendingPathComponent(".zippeek-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let temp = work.appendingPathComponent(output.lastPathComponent)
        switch options.format {
        case .dmg:
            try Self.makeDiskImage(inputs, to: temp, stage: work.appendingPathComponent("stage"),
                                   excludeMacFiles: options.excludeMacFiles)
        case .tarZst:
            try LibArchive.writeTar(inputs, to: temp, filter: .zstd, excludeMacFiles: options.excludeMacFiles, isCancelled: isCancelled)
        default:
            guard let sevenZip else { throw SevenZipError.notFound }
            // 1) tar にまとめる（名前は Windows と同じ形にそろえるため、並べ直した作業用フォルダから）
            let stage = work.appendingPathComponent("stage")
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            for input in inputs { try ArchiveEdit.mirror(input, to: stage.appendingPathComponent(ArchiveEdit.nfc(input.lastPathComponent))) }
            let tar = options.format == .tar ? temp : work.appendingPathComponent(ArchiveKind.baseName(of: output) + ".tar")
            var args = ["a", "-ttar", "-sccUTF-8", "-bsp1", "-bso0", "-bse2"]
            if options.excludeMacFiles {
                args += ["-xr!.DS_Store", "-xr!__MACOSX", "-xr!._*", "-xr!.Spotlight-V100", "-xr!.Trashes", "-xr!.fseventsd"]
            }
            args += ["--", tar.path] + inputs.map { ArchiveEdit.nfc($0.lastPathComponent) }
            try sevenZip.run(args, password: nil, cwd: stage, onProgress: { onProgress($0 * 0.5) }, isCancelled: isCancelled)
            // 2) 圧縮する
            if options.format != .tar {
                let type = ["tarGz": "gzip", "tarXz": "xz", "tarBz2": "bzip2"][options.format.rawValue]!
                let level = ["fast": "-mx=1", "normal": "-mx=5", "max": "-mx=9"][options.level.rawValue]!
                try sevenZip.run(["a", "-t" + type, level, "-sccUTF-8", "-bsp1", "-bso0", "-bse2", "--", temp.path, tar.path],
                                 password: nil, onProgress: { onProgress(0.5 + $0 * 0.5) }, isCancelled: isCancelled)
            }
        }
        try fm.moveItem(at: temp, to: output)
        onProgress(1)
    }

    /// Mac のディスクイメージ（dmg）を作る。作ったあと確かめ、壊れていたら一度だけ作り直す
    static func makeDiskImage(_ inputs: [URL], to output: URL, stage: URL, excludeMacFiles: Bool) throws {
        #if os(macOS)
        let fm = FileManager.default
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        for input in inputs { try ArchiveEdit.mirror(input, to: stage.appendingPathComponent(input.lastPathComponent)) }
        if excludeMacFiles { removeMacJunk(in: stage) }
        let volume = inputs.count == 1 ? inputs[0].deletingPathExtension().lastPathComponent : tr("アーカイブ", "Archive")
        func hdiutil(_ args: [String]) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            p.arguments = args
            let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
            try p.run(); p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                let m = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                throw SevenZipError.failed(m.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        let create = ["create", "-volname", volume, "-srcfolder", stage.path, "-fs", "HFS+", "-format", "UDZO", "-ov", output.path]
        try hdiutil(create)
        if (try? hdiutil(["verify", "-quiet", output.path])) == nil {
            try hdiutil(create)
            try hdiutil(["verify", "-quiet", output.path])
        }
        #else
        throw LibArchive.Failure.unavailable
        #endif
    }

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
        guard let first = inputs.first else { return [] }
        let fm = FileManager.default
        let dir = folder ?? first.deletingLastPathComponent()
        let name = Self.archiveName(for: inputs, options: options)
        if !options.format.supportsPassword {
            let output = Extractor.uniqueURL(dir.appendingPathComponent(name))
            try compressOther(inputs, to: output, options: options, onProgress: onProgress, isCancelled: isCancelled)
            return [output]
        }
        guard let sevenZip else { throw SevenZipError.notFound }
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

        // Macの名前は濁点などが分かれた形（NFD）のことがあり、そのままだとWindowsで「か゛」のように崩れる。
        // zipでは、Windowsと同じ形（NFC）にまとめ直す（分割するときは書き直せないのでそのまま）
        let normalizeNames = options.format == .zip && !options.windowsNames && !split && ArchiveEdit.hasDecomposedNames(inputs)
        let useRewrite = options.format == .zip && (options.windowsNames || normalizeNames)
        let workOutput = useRewrite ? dir.appendingPathComponent(".zippeek-\(UUID().uuidString).zip") : output
        do {
            try sevenZip.compress(inputs, to: workOutput, options: options, onProgress: { p in onProgress(p * (useRewrite ? 0.9 : 1)) },
                                  isCancelled: isCancelled)
            if useRewrite {
                if options.windowsNames {
                    try ZipNameRewriter.rewrite(workOutput, to: output) { name in
                        ArchiveEdit.nfc(name).data(using: NameEncoding.shiftJIS.stringEncoding)
                    }
                } else {
                    try ZipNameRewriter.rewrite(workOutput, to: output, keepUTF8: true) { name in
                        let n = ArchiveEdit.nfc(name)
                        return Array(n.utf8) == Array(name.utf8) ? nil : Data(n.utf8)
                    }
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
