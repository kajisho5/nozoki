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
}
