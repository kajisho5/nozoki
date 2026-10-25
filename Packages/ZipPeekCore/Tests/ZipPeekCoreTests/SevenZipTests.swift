import XCTest
@testable import ZipPeekCore

/// 7-Zipを使わずに確かめられること
final class ArchiveKindTests: XCTestCase {
    override func setUp() { L10n.override = true }

    func testIsArchive() {
        for name in ["a.zip", "a.7z", "a.RAR", "a.tar.gz", "a.7z.003", "a.z02", "a.iso"] {
            XCTAssertTrue(ArchiveKind.isArchive(URL(fileURLWithPath: "/tmp/" + name)), name)
        }
        for name in ["a.txt", "a.mov", "フォルダ"] {
            XCTAssertFalse(ArchiveKind.isArchive(URL(fileURLWithPath: "/tmp/" + name)), name)
        }
    }

    func testBaseName() {
        XCTAssertEqual(ArchiveKind.baseName(of: URL(fileURLWithPath: "/x/素材.tar.gz")), "素材")
        XCTAssertEqual(ArchiveKind.baseName(of: URL(fileURLWithPath: "/x/資料_例.7z.001")), "資料_例")
        XCTAssertEqual(ArchiveKind.baseName(of: URL(fileURLWithPath: "/x/納品.part1.rar")), "納品")
        XCTAssertEqual(ArchiveKind.baseName(of: URL(fileURLWithPath: "/x/v1.2.zip")), "v1.2")
    }

    func testFirstVolume() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vol-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for n in ["a.7z.001", "a.7z.002", "b.part1.rar", "b.part2.rar"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(n).path, contents: Data())
        }
        XCTAssertEqual(ArchiveKind.firstVolume(of: dir.appendingPathComponent("a.7z.002")).lastPathComponent, "a.7z.001")
        XCTAssertEqual(ArchiveKind.firstVolume(of: dir.appendingPathComponent("b.part2.rar")).lastPathComponent, "b.part1.rar")
    }

    func testParseProgress() {
        XCTAssertEqual(SevenZip.parseProgress("  12% 3 + clip.bin\u{8}\u{8}  45% 4 + x"), 0.45)
        XCTAssertNil(SevenZip.parseProgress("Scanning"))
    }

    func testParseList() {
        let text = """
        Path = 素材
        Folder = +
        Size = 0
        Packed Size = 0
        Modified = 2026-09-12 14:02:00.0000000
        Encrypted = -

        Path = 素材/clip.bin
        Folder = -
        Size = 3000000
        Packed Size = 3000028
        Modified = 2026-09-12 14:02:00.1234567
        Encrypted = +
        Comment =
        """
        let entries = SevenZip.parseList(text)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertEqual(entries[1].size, 3_000_000)
        XCTAssertTrue(entries[1].isEncrypted)
        XCTAssertNotNil(entries[1].modified)
        let listing = ArchiveListing.build(raw: entries)
        XCTAssertEqual(listing.source, .sevenZip)
        XCTAssertEqual(listing.items(in: "素材").first?.archivePath, "素材/clip.bin")
    }

    func testEnglishMessages() {
        L10n.override = false
        defer { L10n.override = true }
        XCTAssertEqual(SevenZipError.wrongPassword.localizedDescription, "The password is incorrect.")
        XCTAssertEqual(ByteFormat.string(10), "10 bytes")
    }

    func testCompressOptionsDoNotStorePassword() throws {
        var o = CompressOptions()
        o.password = "架空の合言葉"
        let json = String(decoding: try JSONEncoder().encode(o), as: UTF8.self)
        XCTAssertFalse(json.contains("架空の合言葉"))
    }
}

/// 本物の7-Zipを使う試験。ZIPPEEK_7ZZ に 7zz の場所が入っているときだけ動く（GitHubのMacで実行）
final class SevenZipIntegrationTests: XCTestCase {
    var dir: URL!
    var src: URL!
    var ops: ArchiveOperations!

    override func setUpWithError() throws {
        L10n.override = true
        guard let env = ProcessInfo.processInfo.environment["ZIPPEEK_7ZZ"] else {
            throw XCTSkip("ZIPPEEK_7ZZ が無いので7-Zipの試験は省略")
        }
        ops = ArchiveOperations(sevenZip: SevenZip(executable: URL(fileURLWithPath: env)))
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("zp7-\(UUID().uuidString)")
        src = dir.appendingPathComponent("撮影素材_サンプル")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("CAM_A"), withIntermediateDirectories: true)
        try Data("これは架空のテスト用メモです。\n".utf8).write(to: src.appendingPathComponent("撮影メモ.txt"))
        try Data((0..<1_500_000).map { _ in UInt8.random(in: 0...255) }).write(to: src.appendingPathComponent("CAM_A/clip_0001.mov"))
        try Data("x".utf8).write(to: src.appendingPathComponent(".DS_Store"))
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    func content(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    // zipに圧縮 → 解凍 で元に戻る。.DS_Store は入らない
    func testZipRoundTrip() throws {
        let out = try ops.compress([src], options: CompressOptions())
        XCTAssertEqual(out.map(\.lastPathComponent), ["撮影素材_サンプル.zip"])
        let listing = try ArchiveListing.load(url: out[0])
        XCTAssertEqual(listing.summary.fileCount, 2)
        XCTAssertFalse(listing.allFiles.contains { $0.name == ".DS_Store" })

        let dest = dir.appendingPathComponent("out"); try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let made = try ops.extractAll(out[0], into: dest, password: nil)
        XCTAssertEqual(made.map(\.lastPathComponent), ["撮影素材_サンプル"])
        XCTAssertEqual(try content(made[0].appendingPathComponent("撮影メモ.txt")), "これは架空のテスト用メモです。\n")
        XCTAssertEqual(try Data(contentsOf: made[0].appendingPathComponent("CAM_A/clip_0001.mov")).count, 1_500_000)
    }

    // パスワード付きzip：なし → 必要、違う → 違う、正しい → 解凍できる
    func testEncryptedZip() throws {
        var o = CompressOptions(); o.password = "kakuu-123"
        let out = try ops.compress([src.appendingPathComponent("撮影メモ.txt")], options: o)
        let listing = try ArchiveListing.load(url: out[0])
        XCTAssertEqual(listing.summary.encryptedCount, 1)

        let dest = dir.appendingPathComponent("enc"); try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ops.extractAll(out[0], into: dest, password: nil)) {
            XCTAssertEqual($0 as? SevenZipError, .needsPassword)
        }
        XCTAssertThrowsError(try ops.extractAll(out[0], into: dest, password: "chigau")) {
            XCTAssertEqual($0 as? SevenZipError, .wrongPassword)
        }
        let made = try ops.extractAll(out[0], into: dest, password: "kakuu-123")
        XCTAssertEqual(made.map(\.lastPathComponent), ["撮影メモ.txt"])
        // 失敗した回の作業用フォルダが残っていない
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dest.path), ["撮影メモ.txt"])
    }

    // 7z・名前も隠す暗号・分割 → 先頭以外を渡しても解凍できる
    func testSevenZipSplitWithHeaderEncryption() throws {
        var o = CompressOptions(); o.format = .sevenZip; o.password = "kakuu"; o.splitSize = 500_000; o.level = .fast
        let parts = try ops.compress([src], options: o)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertTrue(parts[0].lastPathComponent.hasSuffix(".7z.001"))

        let sz = ops.sevenZip!
        XCTAssertThrowsError(try sz.list(parts[0], password: nil)) { XCTAssertEqual($0 as? SevenZipError, .needsPassword) }
        let entries = try sz.list(parts[0], password: "kakuu")
        XCTAssertTrue(entries.contains { $0.path.hasSuffix("clip_0001.mov") })

        let dest = dir.appendingPathComponent("7z"); try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        guard parts.count > 1 else { return }
        let made = try ops.extractAll(parts[1], into: dest, password: "kakuu")
        XCTAssertEqual(made.map(\.lastPathComponent), ["撮影素材_サンプル"])
    }

    // 中身を見る窓から：7zの中の1ファイルだけ取り出す
    func testExtractSelectedFromSevenZip() throws {
        var o = CompressOptions(); o.format = .sevenZip
        let out = try ops.compress([src], options: o)
        let listing = ArchiveListing.build(raw: try ops.sevenZip!.list(out[0], password: nil))
        let memo = try XCTUnwrap(listing.allFiles.first { $0.name == "撮影メモ.txt" })
        let dest = dir.appendingPathComponent("sel"); try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let made = try ops.extractSelected(out[0], files: listing.files(for: [memo]), into: dest, password: nil)
        XCTAssertEqual(made.map(\.lastPathComponent), ["撮影メモ.txt"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dest.path), ["撮影メモ.txt"])
    }

    // Windows向け：名前がShift_JISで書かれ、UTF-8の印が外れ、Unicode名も添えてある。中身は壊れていない
    func testWindowsNamesZip() throws {
        #if canImport(Darwin)
        var o = CompressOptions(); o.windowsNames = true; o.password = "kakuu"; o.zipCipher = .zipCrypto
        let out = try ops.compress([src], options: o)
        let entries = try ZipDirectory.read(url: out[0])
        let memo = try XCTUnwrap(entries.first { $0.unicodeName?.hasSuffix("撮影メモ.txt") ?? false })
        XCTAssertFalse(memo.isUTF8Flagged)
        XCTAssertEqual(String(data: memo.rawName, encoding: NameEncoding.shiftJIS.stringEncoding), "撮影素材_サンプル/撮影メモ.txt")
        // 7-Zip自身でも壊れていないか確かめる（暗号付きでもデータは写しただけ）
        _ = try ops.sevenZip!.run(["t", "-pkakuu", out[0].path], password: "kakuu")
        let dest = dir.appendingPathComponent("win"); try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let made = try ops.extractAll(out[0], into: dest, password: "kakuu")
        XCTAssertEqual(try content(made[0].appendingPathComponent("撮影メモ.txt")), "これは架空のテスト用メモです。\n")
        #else
        throw XCTSkip("Shift_JISへの変換はMacで確かめる")
        #endif
    }

    // 名前の書き直しの仕組みそのもの（Linuxでも動く仮の2バイト文字コードで確かめる）
    func testNameRewriterKeepsArchiveValid() throws {
        var o = CompressOptions(); o.password = "kakuu"; o.format = .zip
        let out = try ops.compress([src], options: o)
        let rewritten = dir.appendingPathComponent("rewritten.zip")
        let fake: (String) -> Data? = { s in
            var d = Data()
            for u in s.unicodeScalars {
                if u.value < 0x80 { d.append(UInt8(u.value)) } else { d.append(0x81); d.append(UInt8(0x40 + u.value % 0x3F)) }
            }
            return d
        }
        let n = try ZipNameRewriter.rewrite(out[0], to: rewritten, encode: fake)
        XCTAssertGreaterThan(n, 0)
        _ = try ops.sevenZip!.run(["t", "-pkakuu", rewritten.path], password: "kakuu")
        let entries = try ZipDirectory.read(url: rewritten)
        XCTAssertTrue(entries.contains { $0.unicodeName == "撮影素材_サンプル/撮影メモ.txt" && !$0.isUTF8Flagged })
        XCTAssertLessThan(try FileManager.default.attributesOfItem(atPath: rewritten.path)[.size] as! UInt64,
                          (try FileManager.default.attributesOfItem(atPath: out[0].path)[.size] as! UInt64) + 200)
    }

    // 途中で止めたら、作りかけのファイルを残さない
    func testCancelCompress() throws {
        let big = dir.appendingPathComponent("big.bin")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let h = try FileHandle(forWritingTo: big)
        var g = SystemRandomNumberGenerator(); for _ in 0..<40 { var d = Data(count: 1_000_000); d.withUnsafeMutableBytes { b in for i in stride(from: 0, to: b.count, by: 8) { var v = g.next(); withUnsafeBytes(of: &v) { src in for k in 0..<min(8, b.count - i) { b[i + k] = src[k] } } } }; try h.write(contentsOf: d) }
        try h.close()
        var o = CompressOptions(); o.level = .max; o.format = .sevenZip
        let start = Date()
        XCTAssertThrowsError(try ops.compress([big], options: o, isCancelled: { Date().timeIntervalSince(start) > 0.3 })) {
            XCTAssertEqual($0 as? SevenZipError, .cancelled)
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".7z") || $0.hasPrefix(".zippeek") }
        XCTAssertTrue(left.isEmpty, "残っていたもの: \(left)")
    }

    var sevenZip: SevenZip { SevenZip(executable: URL(fileURLWithPath: ProcessInfo.processInfo.environment["ZIPPEEK_7ZZ"]!)) }

    /// 濁点が分かれた形（NFD）の名前は、zip ではWindowsと同じ形（NFC）にまとめて入る
    func testCompressNormalizesDecomposedNames() throws {
        let nfd = "ガイド".decomposedStringWithCanonicalMapping + ".txt"
        XCTAssertNotEqual(Array(nfd.utf8), Array("ガイド.txt".utf8))
        let folder = dir.appendingPathComponent("濁点テスト")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent(nfd))
        XCTAssertTrue(ArchiveEdit.hasDecomposedNames([folder]))
        let out = try ops.compress([folder], options: CompressOptions())
        let names = try ArchiveListing.load(url: out[0]).allFiles.map(\.name)
        XCTAssertEqual(names.map { Array($0.utf8) }, [Array("ガイド.txt".utf8)])
        // 作業用のファイルが残っていない
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix(".zippeek") })
    }

    /// 今あるzipの一番上とフォルダの中へ足す。名前はNFCで入り、作業用フォルダは残らない
    func testAddToZip() throws {
        let zip = try ops.compress([src], options: CompressOptions())[0]
        let extra = dir.appendingPathComponent("追加分")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        let nfd = "バックアップ".decomposedStringWithCanonicalMapping + ".txt"
        try Data("add".utf8).write(to: extra.appendingPathComponent(nfd))
        try Data("b".utf8).write(to: extra.appendingPathComponent(".DS_Store"))
        try ArchiveEdit.add([extra.appendingPathComponent(nfd)], to: zip, inFolder: "撮影素材_サンプル/CAM_A", sevenZip: sevenZip)
        try ArchiveEdit.add([extra], to: zip, inFolder: "", sevenZip: sevenZip)
        let listing = try ArchiveListing.load(url: zip)
        let paths = listing.allFiles.map(\.path)
        XCTAssertTrue(paths.contains { Array($0.utf8) == Array("撮影素材_サンプル/CAM_A/バックアップ.txt".utf8) }, "\(paths)")
        XCTAssertTrue(paths.contains { Array($0.utf8) == Array("追加分/バックアップ.txt".utf8) }, "\(paths)")
        XCTAssertFalse(paths.contains { $0.hasSuffix(".DS_Store") })
        XCTAssertEqual(listing.summary.fileCount, 4)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".zippeek") }
        XCTAssertTrue(left.isEmpty, "残っていたもの: \(left)")
        // 元のファイルはそのまま
        XCTAssertEqual(try content(extra.appendingPathComponent(nfd)), "add")
    }

    /// ファイルとフォルダ（中身ごと）を消す。7z でも
    func testDeleteFromZipAnd7z() throws {
        for format in [CompressOptions.Format.zip, .sevenZip] {
            var o = CompressOptions(); o.format = format
            let archive = try ops.compress([src], options: o)[0]
            // アプリと同じく、一覧に出た名前（Macで作った7zは濁点が分かれた形のこともある）をそのまま渡す
            var names = try sevenZip.list(archive, password: nil).map(\.path)
            let memo = try XCTUnwrap(names.first { ArchiveEdit.nfc($0) == "撮影素材_サンプル/撮影メモ.txt" })
            try ArchiveEdit.delete([memo], from: archive, sevenZip: sevenZip)
            names = try sevenZip.list(archive, password: nil).map(\.path)
            XCTAssertFalse(names.contains { ArchiveEdit.nfc($0) == "撮影素材_サンプル/撮影メモ.txt" }, "\(format) \(names)")
            XCTAssertTrue(names.contains { ArchiveEdit.nfc($0) == "撮影素材_サンプル/CAM_A/clip_0001.mov" })
            let camA = try XCTUnwrap(names.first { ArchiveEdit.nfc($0) == "撮影素材_サンプル/CAM_A/clip_0001.mov" })
            try ArchiveEdit.delete([(camA as NSString).deletingLastPathComponent], from: archive, sevenZip: sevenZip)
            names = try sevenZip.list(archive, password: nil).map(\.path)
            XCTAssertFalse(names.contains { ArchiveEdit.nfc($0).hasPrefix("撮影素材_サンプル/CAM_A") }, "\(format) \(names)")
        }
    }

    /// Windowsで作ったzip（Shift_JIS）に足しても、元の名前は壊れない
    func testAddKeepsShiftJISNames() throws {
        let zip = dir.appendingPathComponent("win.zip")
        var b = ZipBuilder()
        b.items = [.init(rawName: Sample.sjisMemo, content: Data("memo".utf8))]
        try b.build().write(to: zip)
        let before = try ArchiveListing.load(url: zip).allFiles.map(\.path)
        let extra = dir.appendingPathComponent("new.txt"); try Data("n".utf8).write(to: extra)
        try ArchiveEdit.add([extra], to: zip, inFolder: "", sevenZip: sevenZip)
        let after = try ArchiveListing.load(url: zip).allFiles.map(\.path)
        for name in before { XCTAssertTrue(after.contains(name), "\(name) が消えた: \(after)") }
        XCTAssertTrue(after.contains("new.txt"))
    }

    /// Mac の「アーカイブユーティリティ」のzipのように、目印なしの UTF-8 の名前でも削除できる
    func testDeleteFromUnflaggedUTF8Zip() throws {
        let zip = dir.appendingPathComponent("mac.zip")
        var b = ZipBuilder()
        b.items = [.init(rawName: Data("撮影/メモ.txt".utf8), content: Data("m".utf8)),
                   .init(rawName: Data("撮影/a.txt".utf8), content: Data("a".utf8))]
        try b.build().write(to: zip)
        let listing = try ArchiveListing.load(url: zip)
        XCTAssertFalse(listing.namesNeedConversion)
        try ArchiveEdit.delete(["撮影/メモ.txt"], from: zip, sevenZip: sevenZip)
        XCTAssertEqual(try ArchiveListing.load(url: zip).allFiles.map(\.path), ["撮影/a.txt"])
        XCTAssertThrowsError(try ArchiveEdit.delete(["無い.txt"], from: zip, sevenZip: sevenZip))
    }

    func testEditChecks() throws {
        let zip = try ops.compress([src], options: CompressOptions())[0]
        XCTAssertNil(ArchiveEdit.check(zip, encrypted: false))
        XCTAssertEqual(ArchiveEdit.check(zip, encrypted: true), .encrypted)
        XCTAssertEqual(ArchiveEdit.check(dir.appendingPathComponent("a.rar"), encrypted: false), .unsupportedFormat)
        XCTAssertEqual(ArchiveEdit.check(dir.appendingPathComponent("a.7z.001"), encrypted: false), .splitArchive)
    }

    // MARK: - 0.4 の機能

    /// tar 系の形式で作って、解凍すると元に戻る
    func testTarFormatsRoundTrip() throws {
        var formats: [CompressOptions.Format] = [.tar, .tarGz, .tarXz, .tarBz2]
        if LibArchive.canWrite(.zstd) { formats.append(.tarZst) }
        for format in formats {
            var o = CompressOptions(); o.format = format
            let out = try ops.compress([src], options: o)
            XCTAssertEqual(out.count, 1)
            XCTAssertTrue(out[0].lastPathComponent.hasSuffix("." + format.fileExtension), out[0].lastPathComponent)
            let dest = dir.appendingPathComponent("out-\(format.rawValue)")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let made = try ops.extractAll(out[0], into: dest, password: nil)
            XCTAssertEqual(made.map(\.lastPathComponent), ["撮影素材_サンプル"], "\(format)")
            XCTAssertEqual(try content(made[0].appendingPathComponent("撮影メモ.txt")), "これは架空のテスト用メモです。\n", "\(format)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: made[0].appendingPathComponent(".DS_Store").path), "\(format)")
            XCTAssertEqual(try Data(contentsOf: made[0].appendingPathComponent("CAM_A/clip_0001.mov")),
                           try Data(contentsOf: src.appendingPathComponent("CAM_A/clip_0001.mov")), "\(format)")
        }
    }

    /// .tar.zst の一覧（窓とスペースキー用）と、一部だけ取り出し
    func testZstdListAndExtractSelected() throws {
        guard LibArchive.canWrite(.zstd) else { throw XCTSkip("この OS の libarchive は zstd を書けない") }
        var o = CompressOptions(); o.format = .tarZst
        let out = try ops.compress([src], options: o)[0]
        let raw = try LibArchive.entries(out)
        let listing = ArchiveListing.build(raw: raw)
        XCTAssertEqual(Set(listing.allFiles.map(\.path)), ["撮影素材_サンプル/撮影メモ.txt", "撮影素材_サンプル/CAM_A/clip_0001.mov"])
        let memo = try XCTUnwrap(listing.allFiles.first { $0.name == "撮影メモ.txt" })
        let dest = dir.appendingPathComponent("sel")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let got = try ops.extractSelected(out, files: [(memo, "撮影メモ.txt")], into: dest, password: nil)
        XCTAssertEqual(got.map(\.lastPathComponent), ["撮影メモ.txt"])
    }

    /// 中で名前を変える（ファイルとフォルダ）
    func testRename() throws {
        for format in [CompressOptions.Format.zip, .sevenZip] {
            var o = CompressOptions(); o.format = format
            let archive = try ops.compress([src], options: o)[0]
            try ArchiveEdit.rename("撮影素材_サンプル/撮影メモ.txt", to: "台本.txt", in: archive, sevenZip: sevenZip)
            try ArchiveEdit.rename("撮影素材_サンプル/CAM_A", to: "CAM_B", in: archive, sevenZip: sevenZip)
            let names = Set(try sevenZip.list(archive, password: nil).filter { !$0.isDirectory }.map { ArchiveEdit.nfc($0.path) })
            XCTAssertEqual(names, ["撮影素材_サンプル/台本.txt", "撮影素材_サンプル/CAM_B/clip_0001.mov"], "\(format)")
            XCTAssertThrowsError(try ArchiveEdit.rename("撮影素材_サンプル/台本.txt", to: "CAM_B", in: archive, sevenZip: sevenZip))
            XCTAssertThrowsError(try ArchiveEdit.rename("撮影素材_サンプル/台本.txt", to: "a/b", in: archive, sevenZip: sevenZip))
        }
    }

    /// 壊れていないかのテスト：正常なら ok、途中を壊すとエラー
    func testIntegrityTest() throws {
        var o = CompressOptions(); o.format = .sevenZip; o.level = .fast
        let archive = try ops.compress([src], options: o)[0]
        XCTAssertTrue(try ArchiveTest.run(archive, password: nil, sevenZip: sevenZip).ok)
        var bytes = try Data(contentsOf: archive)
        for i in stride(from: 2000, to: 60_000, by: 7) { bytes[i] ^= 0xFF }
        try bytes.write(to: archive)
        let r = try ArchiveTest.run(archive, password: nil, sevenZip: sevenZip)
        XCTAssertFalse(r.ok)
    }

    #if os(macOS)
    /// ネットから来た zip の印が、解凍したものにも付く
    func testQuarantinePropagates() throws {
        let zip = try ops.compress([src], options: CompressOptions())[0]
        let value = Data("0083;65f00000;Safari;".utf8)
        _ = value.withUnsafeBytes { setxattr(zip.path, "com.apple.quarantine", $0.baseAddress, value.count, 0, 0) }
        let dest = dir.appendingPathComponent("q")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let made = try ops.extractAll(zip, into: dest, password: nil)
        XCTAssertEqual(Quarantine.read(made[0]), value)
        XCTAssertEqual(Quarantine.read(made[0].appendingPathComponent("CAM_A/clip_0001.mov")), value)
    }

    /// 中国語・韓国語の Windows で作った zip の名前も読める
    func testOtherEncodings() throws {
        let cases: [(NameEncoding, String)] = [(.gbk, "测试文件.txt"), (.big5, "測試檔案.txt"), (.korean, "테스트.txt")]
        for (enc, name) in cases {
            let raw = try XCTUnwrap(name.data(using: enc.stringEncoding))
            XCTAssertEqual(enc.decode(raw), name)
            var b = ZipBuilder(); b.items = [.init(rawName: raw, content: Data("x".utf8))]
            let zip = dir.appendingPathComponent("\(enc.rawValue).zip")
            try b.build().write(to: zip)
            XCTAssertEqual(try ArchiveListing.load(url: zip, encoding: enc).allFiles.map(\.path), [name])
        }
    }
    #endif
}

