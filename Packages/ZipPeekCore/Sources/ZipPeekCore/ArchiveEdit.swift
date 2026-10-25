import Foundation

/// 今ある圧縮ファイル（zip・7z）に、ファイルを足したり消したりする。中身の処理は7-Zipに任せる。
public enum ArchiveEdit {
    public enum Failure: LocalizedError, Equatable {
        case unsupportedFormat, splitArchive, encrypted, legacyNames, readOnly
        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat: tr("足したり消したりできるのは zip と 7z だけです。", "Only ZIP and 7z archives can be changed.")
            case .splitArchive: tr("分割された圧縮ファイルは変更できません。", "Split archives can’t be changed.")
            case .encrypted: tr("パスワード付きの圧縮ファイルは変更できません。", "Password-protected archives can’t be changed.")
            case .legacyNames: tr("Windowsで作られた名前のzipからは削除できません（追加はできます）。", "Items can’t be deleted from a ZIP with Windows-style names (adding works).")
            case .readOnly: tr("この圧縮ファイルは書き込みできない場所にあります。", "This archive is in a location you can’t write to.")
            }
        }
    }

    /// 変更できるか（できないなら理由）
    public static func check(_ archive: URL, encrypted: Bool) -> Failure? {
        let ext = archive.pathExtension.lowercased()
        guard ext == "zip" || ext == "7z" else {
            return archive.lastPathComponent.range(of: #"\.\d{3}$"#, options: .regularExpression) != nil ? .splitArchive : .unsupportedFormat
        }
        let dir = archive.deletingLastPathComponent()
        let base = archive.deletingPathExtension().lastPathComponent
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent(base + ".z01").path) { return .splitArchive }
        if encrypted { return .encrypted }
        if !FileManager.default.isWritableFile(atPath: archive.path) || !FileManager.default.isWritableFile(atPath: dir.path) {
            return .readOnly
        }
        return nil
    }

    /// items を archive の中の folder（"" なら一番上）へ足す。
    /// 名前は Windows と同じ形（NFC）にまとめ、Mac専用の隠しファイルは入れない。
    public static func add(_ items: [URL], to archive: URL, inFolder folder: String, sevenZip: SevenZip,
                           onProgress: @escaping @Sendable (Double) -> Void = { _ in },
                           isCancelled: @escaping @Sendable () -> Bool = { false }) throws {
        guard !items.isEmpty else { return }
        let fm = FileManager.default
        // 元のファイルと同じ場所に作業用フォルダを作り、そこへ「同じ中身を指す別名（ハードリンク）」で並べ直す。
        // 中に入る場所と名前をこちらで決められ、ファイルを複製しないので巨大でも速い
        let stageParent = items[0].deletingLastPathComponent()
        var stage = stageParent.appendingPathComponent(".zippeek-add-\(UUID().uuidString)")
        if (try? fm.createDirectory(at: stage, withIntermediateDirectories: false)) == nil {
            stage = fm.temporaryDirectory.appendingPathComponent("zippeek-add-\(UUID().uuidString)")
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: stage) }

        let parts = folder.split(separator: "/").map { nfc(String($0)) }
        var base = stage
        for p in parts { base.appendPathComponent(p, isDirectory: true) }
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        for item in items {
            try mirror(item, to: base.appendingPathComponent(nfc(item.lastPathComponent)))
        }
        let tops = parts.first.map { [$0] } ?? items.map { nfc($0.lastPathComponent) }
        var args = ["a", "-sccUTF-8", "-bsp1", "-bso0", "-bse2", "-spd"]
        args += ["-xr!.DS_Store", "-xr!__MACOSX", "-xr!._*", "-xr!.Spotlight-V100", "-xr!.Trashes", "-xr!.fseventsd"]
        args += ["--", archive.standardizedFileURL.path] + tops
        try sevenZip.run(args, password: nil, cwd: stage, onProgress: { onProgress($0 * 0.95) }, isCancelled: isCancelled)
        // Mac はファイル名を保存するとき濁点を分けた形（NFD）に戻してしまうので、zip の中の名前を後からまとめ直す
        if archive.pathExtension.lowercased() == "zip" { try normalizeZipNames(archive) }
        onProgress(1)
    }

    /// zip の中の UTF-8 の名前を NFC にそろえる（変える必要が無ければ何もしない）。Windows形式（Shift_JIS）の名前は触らない
    public static func normalizeZipNames(_ archive: URL) throws {
        let fm = FileManager.default
        let tmp = archive.deletingLastPathComponent().appendingPathComponent(".zippeek-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: tmp) }
        let changed = try ZipNameRewriter.rewrite(archive, to: tmp, keepUTF8: true) { name in
            let n = nfc(name)
            return Array(n.utf8) == Array(name.utf8) ? nil : Data(n.utf8)
        }
        guard changed > 0 else { return }
        _ = try fm.replaceItemAt(archive, withItemAt: tmp)
    }

    /// archive の中の paths（ファイルやフォルダ。フォルダは中身ごと）を消す
    public static func delete(_ paths: [String], from archive: URL, sevenZip: SevenZip) throws {
        guard !paths.isEmpty else { return }
        let lf = FileManager.default.temporaryDirectory.appendingPathComponent("zippeek-\(UUID().uuidString).txt")
        try paths.joined(separator: "\n").write(to: lf, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: lf) }
        // 「--」を付けると @リスト がファイル名扱いになるので付けない
        try sevenZip.run(["d", "-sccUTF-8", "-bsp1", "-bso0", "-bse2", "-spd", "-scsUTF-8",
                          archive.standardizedFileURL.path, "@" + lf.path], password: nil)
    }

    /// Windows と同じ形（濁点などを1文字にまとめた形 = NFC）にする
    public static func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }

    /// 名前に、濁点などが分かれた形（NFD）が含まれるか。Swift の == は形の違いを同じとみなすのでバイトで比べる
    public static func hasDecomposedNames(_ urls: [URL]) -> Bool {
        func differs(_ name: String) -> Bool { Array(nfc(name).utf8) != Array(name.utf8) }
        for url in urls {
            if differs(url.lastPathComponent) { return true }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                  let e = FileManager.default.enumerator(atPath: url.path) else { continue }
            while let rel = e.nextObject() as? String {
                if differs((rel as NSString).lastPathComponent) { return true }
            }
        }
        return false
    }

    /// src を dst へ並べる（フォルダは中まで。ファイルはハードリンク、できなければ複製）
    private static func mirror(_ src: URL, to dst: URL) throws {
        let fm = FileManager.default
        let values = try src.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            let target = try fm.destinationOfSymbolicLink(atPath: src.path)
            try fm.createSymbolicLink(atPath: dst.path, withDestinationPath: target)
        } else if values.isDirectory == true {
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            for child in try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil, options: []) {
                try mirror(child, to: dst.appendingPathComponent(nfc(child.lastPathComponent)))
            }
        } else {
            do { try fm.linkItem(at: src, to: dst) } catch { try fm.copyItem(at: src, to: dst) }
        }
    }
}
