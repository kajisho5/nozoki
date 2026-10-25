import Foundation

/// 今ある圧縮ファイル（zip・7z）に、ファイルを足したり消したりする。中身の処理は7-Zipに任せる。
public enum ArchiveEdit {
    public enum Failure: LocalizedError, Equatable {
        case unsupportedFormat, splitArchive, encrypted, legacyNames, readOnly, nothingDeleted, badName, nameExists, itemMissing, remoteLink, nested
        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat: tr("足したり消したりできるのは zip と 7z だけです。", "Only ZIP and 7z archives can be changed.")
            case .splitArchive: tr("分割された圧縮ファイルは変更できません。", "Split archives can’t be changed.")
            case .encrypted: tr("パスワード付きの圧縮ファイルは変更できません。", "Password-protected archives can’t be changed.")
            case .legacyNames: tr("Windowsで作られた名前のzipからは削除できません（追加はできます）。", "Items can’t be deleted from a ZIP with Windows-style names (adding works).")
            case .readOnly: tr("この圧縮ファイルは書き込みできない場所にあります。", "This archive is in a location you can’t write to.")
            case .remoteLink: tr("リンクのままのぞいている圧縮ファイルは変更できません。", "An archive opened from a link can’t be changed.")
            case .nested: tr("圧縮ファイルの中の圧縮ファイルは変更できません。いったん取り出してから開いてください。", "An archive inside another archive can’t be changed. Extract it first.")
            case .itemMissing: tr("その項目が圧縮ファイルの中に見つかりませんでした。", "That item wasn’t found in the archive.")
            case .badName: tr("その名前は使えません（「/」は入れられません）。", "That name can’t be used (it can’t contain “/”).")
            case .nameExists: tr("同じ名前のものが、すでに同じ場所にあります。", "An item with that name already exists there.")
            case .nothingDeleted: tr("選んだ項目が圧縮ファイルの中で見つからず、削除できませんでした。", "The selected items couldn’t be found in the archive, so nothing was deleted.")
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
        let before = try sevenZip.list(archive, password: nil).count
        // 「--」を付けると @リスト がファイル名扱いになるので付けない
        try sevenZip.run(["d", "-sccUTF-8", "-bsp1", "-bso0", "-bse2", "-spd", "-scsUTF-8",
                          archive.standardizedFileURL.path, "@" + lf.path], password: nil)
        // 7-Zip は名前が合わなくても成功扱いで終わるので、本当に減ったか確かめる
        if try sevenZip.list(archive, password: nil).count >= before { throw Failure.nothingDeleted }
    }

    /// archive の中の from（ファイルかフォルダ）の名前を newName に変える。フォルダは中身の道筋もまとめて変える
    public static func rename(_ from: String, to newName: String, in archive: URL, sevenZip: SevenZip) throws {
        let clean = nfc(newName.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !clean.isEmpty, !clean.contains("/"), clean != ".", clean != ".." else { throw Failure.badName }
        let entries = try sevenZip.list(archive, password: nil).compactMap { $0.archivePath }
        let parent = (from as NSString).deletingLastPathComponent
        let target = parent.isEmpty ? clean : parent + "/" + clean
        // 同じ名前がすでにあるときは変えない（上書きで消えるのを防ぐ）
        if entries.contains(where: { nfc($0) == nfc(target) || nfc($0).hasPrefix(nfc(target) + "/") }) { throw Failure.nameExists }
        var pairs: [String] = []
        // 一覧の名前と、保存されている名前の形（濁点が分かれているか）が違っても見つけられるよう NFC で比べる
        let f = nfc(from)
        for e in entries {
            let n = nfc(e)
            if n == f { pairs += [e, target] }
            else if n.hasPrefix(f + "/") { pairs += [e, target + n.dropFirst(f.count)] }
        }
        guard !pairs.isEmpty else { throw Failure.itemMissing }
        func names() throws -> [String] { try sevenZip.list(archive, password: nil).compactMap { $0.archivePath }.sorted() }
        let before = try names()
        // 削除と同じく、名前の組は UTF-8 のリストファイルで渡す（Mac ではコマンドの引数だと日本語の名前が合わないことがある）
        func run(_ list: [String]) throws {
            let lf = FileManager.default.temporaryDirectory.appendingPathComponent("zippeek-\(UUID().uuidString).txt")
            try list.joined(separator: "\n").write(to: lf, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: lf) }
            try sevenZip.run(["rn", "-sccUTF-8", "-bsp1", "-bso0", "-bse2", "-scsUTF-8", archive.standardizedFileURL.path, "@" + lf.path],
                             password: nil)
        }
        try run(pairs)
        // 7-Zip は名前が合わないと何もせず成功で終わる。名前の形（濁点が分かれた NFD）の違いもあり得るので、もう一度試す
        if try names() == before {
            try run(pairs.map { $0.decomposedStringWithCanonicalMapping })
            if try names() == before { throw Failure.itemMissing }
        }
        if archive.pathExtension.lowercased() == "zip" { try normalizeZipNames(archive) }
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
    static func mirror(_ src: URL, to dst: URL) throws {
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
