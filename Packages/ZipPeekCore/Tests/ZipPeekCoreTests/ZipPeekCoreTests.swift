import XCTest
import ZIPFoundation
@testable import ZipPeekCore

final class ZipDirectoryTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        L10n.override = true
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZipPeek-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // ZIPFoundationで普通に作ったzipの目次が読めること
    func testReadsStandardArchive() throws {
        let url = dir.appendingPathComponent("サンプル.zip")
        let archive = try Archive(url: url, accessMode: .create)
        let video = Data(repeating: 7, count: 50_000)
        try archive.addEntry(with: "CAM_A/clip_0002.mov", type: .file, uncompressedSize: Int64(video.count),
                             compressionMethod: .deflate) { pos, size in
            video.subdata(in: Int(pos)..<Int(pos) + size)
        }
        try archive.addEntry(with: "CAM_A/clip_0010.mov", type: .file, uncompressedSize: Int64(3)) { _, _ in Data("abc".utf8) }
        try archive.addEntry(with: "readme.txt", type: .file, uncompressedSize: Int64(5)) { _, _ in Data("hello".utf8) }

        let listing = try ArchiveListing.load(url: url)
        XCTAssertEqual(listing.summary.fileCount, 3)
        XCTAssertEqual(listing.summary.folderCount, 1)
        XCTAssertEqual(listing.summary.totalSize, 50_008)
        XCTAssertLessThan(listing.summary.packedSize, 50_008)
        // 並びは「フォルダが先」「数字は数として」
        let top = listing.items(in: "")
        XCTAssertEqual(top.map(\.name), ["CAM_A", "readme.txt"])
        XCTAssertTrue(top[0].isFolder)
        XCTAssertEqual(top[0].fileCount, 2)
        XCTAssertEqual(listing.items(in: "CAM_A").map(\.name), ["clip_0002.mov", "clip_0010.mov"])
    }

    // 「UTF-8」の印がない日本語名（Windowsで作ったzip）をShift_JISと判定すること
    func testDetectsShiftJIS() throws {
        var b = ZipBuilder()
        b.items = [
            .init(rawName: Sample.sjisFolder),
            .init(rawName: Sample.sjisFolder + Sample.sjisMemo, content: Data("memo".utf8)),
            .init(rawName: Data("CAM_A/clip_0001.mov".utf8), content: Data(repeating: 1, count: 10))
        ]
        let url = dir.appendingPathComponent("win.zip")
        try b.write(to: url)
        let entries = try ZipDirectory.read(url: url)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(NameEncoding.detect(entries), .shiftJIS)
        #if canImport(Darwin)
        let listing = ArchiveListing.build(entries: entries)
        XCTAssertEqual(listing.items(in: "").map(\.name), ["CAM_A", "素材"])
        XCTAssertEqual(listing.items(in: "素材").first?.name, "撮影メモ.txt")
        XCTAssertTrue(listing.hasLegacyNames)
        #endif
    }

    // 印なしでもUTF-8として正しければUTF-8（Macの標準の圧縮がこれ）
    func testUnflaggedUTF8StaysUTF8() throws {
        var b = ZipBuilder()
        b.items = [.init(rawName: Data("撮影メモ.txt".utf8), content: Data("x".utf8))]
        let url = dir.appendingPathComponent("mac.zip")
        try b.write(to: url)
        let listing = try ArchiveListing.load(url: url)
        XCTAssertEqual(listing.detectedEncoding, .utf8)
        XCTAssertEqual(listing.allFiles.first?.name, "撮影メモ.txt")
    }

    // Info-ZIPのUnicode名の拡張があればそれを使う
    func testUnicodeExtraFieldWins() throws {
        var b = ZipBuilder()
        b.items = [.init(rawName: Data("????.txt".utf8), content: Data("x".utf8), unicodeName: "撮影メモ.txt")]
        let url = dir.appendingPathComponent("extra.zip")
        try b.write(to: url)
        let listing = try ArchiveListing.load(url: url)
        XCTAssertEqual(listing.allFiles.first?.name, "撮影メモ.txt")
    }

    // 4GB超の形式（ZIP64）の目次が読めること
    func testZIP64Directory() throws {
        var b = ZipBuilder()
        b.forceZIP64 = true
        b.items = [
            .init(rawName: Data("big/part1.bin".utf8), content: Data(repeating: 2, count: 1234), utf8Flag: true),
            .init(rawName: Data("big/part2.bin".utf8), content: Data(repeating: 3, count: 10), utf8Flag: true)
        ]
        let url = dir.appendingPathComponent("z64.zip")
        try b.write(to: url)
        let entries = try ZipDirectory.read(url: url)
        XCTAssertEqual(entries.map(\.size), [1234, 10])
        XCTAssertEqual(entries.map(\.packedSize), [1234, 10])
        XCTAssertEqual(entries.first?.modified.map { Calendar(identifier: .gregorian).component(.year, from: $0) }, 2026)
    }

    // 末尾にコメントが付いていても読めること
    func testTrailingComment() throws {
        var b = ZipBuilder()
        b.items = [.init(rawName: Data("a.txt".utf8), content: Data("1".utf8))]
        b.comment = Data(repeating: 0x41, count: 3000)
        let url = dir.appendingPathComponent("comment.zip")
        try b.write(to: url)
        XCTAssertEqual(try ZipDirectory.read(url: url).count, 1)
    }

    func testRejectsNonZip() throws {
        let url = dir.appendingPathComponent("not.zip")
        try Data("これはzipではありません".utf8).write(to: url)
        XCTAssertThrowsError(try ZipDirectory.read(url: url)) { error in
            XCTAssertEqual(error as? ZipReadError, .notAZip)
        }
    }

    func testTruncatedZip() throws {
        var b = ZipBuilder()
        b.items = [.init(rawName: Data("a.txt".utf8), content: Data(repeating: 9, count: 100))]
        var data = b.build()
        // 目次の位置を壊す
        data.replaceSubrange((data.count - 6)..<(data.count - 2), with: Data([0xFF, 0xFF, 0xFF, 0x7F]))
        let url = dir.appendingPathComponent("broken.zip")
        try data.write(to: url)
        XCTAssertThrowsError(try ZipDirectory.read(url: url))
    }

    // Macのzipに混ざる __MACOSX は一覧に出さない
    func testHidesMacJunk() throws {
        var b = ZipBuilder()
        b.items = [
            .init(rawName: Data("photo.jpg".utf8), content: Data("j".utf8)),
            .init(rawName: Data("__MACOSX/._photo.jpg".utf8), content: Data("r".utf8))
        ]
        let url = dir.appendingPathComponent("junk.zip")
        try b.write(to: url)
        let listing = try ArchiveListing.load(url: url)
        XCTAssertEqual(listing.summary.fileCount, 1)
        XCTAssertEqual(listing.items(in: "").map(\.name), ["photo.jpg"])
    }

    func testEncryptedFlagCounted() throws {
        var b = ZipBuilder()
        b.items = [.init(rawName: Data("secret.txt".utf8), content: Data("x".utf8), encryptedFlag: true)]
        let url = dir.appendingPathComponent("locked.zip")
        try b.write(to: url)
        let listing = try ArchiveListing.load(url: url)
        XCTAssertEqual(listing.summary.encryptedCount, 1)
        XCTAssertTrue(listing.allFiles[0].isEncrypted)
        let job = Extractor.Job(entryIndex: 0, name: "secret.txt", size: 1, isEncrypted: true, relativePath: "secret.txt")
        XCTAssertThrowsError(try Extractor(zipURL: url).extract([job], into: dir)) { error in
            XCTAssertEqual(error as? ExtractError, .encrypted("secret.txt"))
        }
    }

    // ..（親フォルダ）を含む名前でも保存先の外に出ない
    func testSafePaths() {
        XCTAssertEqual(ArchiveListing.normalize("../../etc/passwd"), "etc/passwd")
        XCTAssertEqual(ArchiveListing.normalize("/abs\\win\\file.txt"), "abs/win/file.txt")
        XCTAssertEqual(Extractor.safeRelativePath("../x/../y.txt"), "x/y.txt")
    }
}

final class ExtractorTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZipPeek-ex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func makeArchive() throws -> URL {
        let url = dir.appendingPathComponent("src.zip")
        let archive = try Archive(url: url, accessMode: .create)
        let big = Data((0..<300_000).map { UInt8($0 % 251) })
        try archive.addEntry(with: "CAM_B/clip_0101.mov", type: .file, uncompressedSize: Int64(big.count),
                             compressionMethod: .deflate) { pos, size in big.subdata(in: Int(pos)..<Int(pos) + size) }
        try archive.addEntry(with: "CAM_B/notes/メモ.txt", type: .file, uncompressedSize: Int64(6)) { _, _ in Data("memo!\n".utf8) }
        try archive.addEntry(with: "top.txt", type: .file, uncompressedSize: Int64(3)) { _, _ in Data("top".utf8) }
        return url
    }

    // 選んだ1件だけを取り出し、中身が一致すること
    func testExtractSingleFile() throws {
        let url = try makeArchive()
        let listing = try ArchiveListing.load(url: url)
        let item = try XCTUnwrap(listing.allFiles.first { $0.name == "clip_0101.mov" })
        let out = dir.appendingPathComponent("out")
        let jobs = listing.files(for: [item]).map {
            Extractor.Job(entryIndex: $0.item.entryIndex!, name: $0.item.name, size: $0.item.size,
                          isEncrypted: false, relativePath: $0.relativePath)
        }
        let written = try Extractor(zipURL: url).extract(jobs, into: out)
        XCTAssertEqual(written.map(\.lastPathComponent), ["clip_0101.mov"])
        let data = try Data(contentsOf: written[0])
        XCTAssertEqual(data.count, 300_000)
        XCTAssertEqual(data[1000], UInt8(1000 % 251))
        // 他のファイルは出ていない
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), ["clip_0101.mov"])
    }

    // フォルダを選ぶと配下ごと、フォルダ構造を保って取り出す。同名は「 2」を付ける
    func testExtractFolderAndUniqueNames() throws {
        let url = try makeArchive()
        let listing = try ArchiveListing.load(url: url)
        let folder = try XCTUnwrap(listing.items(in: "").first { $0.isFolder })
        let jobs = listing.files(for: [folder]).map {
            Extractor.Job(entryIndex: $0.item.entryIndex!, name: $0.item.name, size: $0.item.size,
                          isEncrypted: false, relativePath: $0.relativePath)
        }
        XCTAssertEqual(Set(jobs.map(\.relativePath)), ["CAM_B/clip_0101.mov", "CAM_B/notes/メモ.txt"])
        let ex = Extractor(zipURL: url)
        try ex.extract(jobs, into: dir)
        let again = try ex.extract(jobs, into: dir)
        XCTAssertTrue(again.contains { $0.lastPathComponent == "メモ 2.txt" })
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("CAM_B/notes/メモ.txt"), encoding: .utf8), "memo!\n")
    }

    // 途中で止めたら書きかけを残さない
    func testCancelLeavesNothing() throws {
        let url = try makeArchive()
        let listing = try ArchiveListing.load(url: url)
        let item = try XCTUnwrap(listing.allFiles.first { $0.name == "clip_0101.mov" })
        let out = dir.appendingPathComponent("cancel")
        let job = Extractor.Job(entryIndex: item.entryIndex!, name: item.name, size: item.size, isEncrypted: false, relativePath: item.name)
        XCTAssertThrowsError(try Extractor(zipURL: url).extract([job], into: out, isCancelled: { true })) { error in
            XCTAssertEqual(error as? ExtractError, .cancelled)
        }
        let left = (try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []
        XCTAssertTrue(left.isEmpty, "残っていたもの: \(left)")
    }

    // 手で組んだShift_JIS名のzipからも、番号指定で正しく取り出せる
    func testExtractFromHandBuiltShiftJISZip() throws {
        var b = ZipBuilder()
        b.items = [.init(rawName: Sample.sjisMemo, content: Data("中身".utf8))]
        let url = dir.appendingPathComponent("sjis.zip")
        try b.write(to: url)
        let job = Extractor.Job(entryIndex: 0, name: "撮影メモ.txt", size: 6, isEncrypted: false, relativePath: "撮影メモ.txt")
        let written = try Extractor(zipURL: url).extract([job], into: dir.appendingPathComponent("o"))
        XCTAssertEqual(try String(contentsOf: written[0], encoding: .utf8), "中身")
    }
}

final class FormatTests: XCTestCase {
    override func setUp() { L10n.override = true }

    func testByteFormat() {
        XCTAssertEqual(ByteFormat.string(512), "512 バイト")
        XCTAssertEqual(ByteFormat.string(4_096), "4 KB")
        XCTAssertEqual(ByteFormat.string(1_200_000), "1.2 MB")
        XCTAssertEqual(ByteFormat.string(27_400_000_000), "27.4 GB")
        XCTAssertEqual(ByteFormat.string(182_000_000_000), "182 GB")
    }

    func testPreviewHTMLEscapesAndCounts() throws {
        var b = ZipBuilder()
        b.items = [
            .init(rawName: Data("CAM_A/<clip>&1.mov".utf8), content: Data("v".utf8)),
            .init(rawName: Data("readme.txt".utf8), content: Data("r".utf8))
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prev-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try b.write(to: url)
        let html = PreviewHTML.make(listing: try ArchiveListing.load(url: url), fileName: "a&b.zip", elapsed: 0.2)
        XCTAssertTrue(html.contains("&lt;clip&gt;&amp;1.mov"))
        XCTAssertFalse(html.contains("<clip>"))
        XCTAssertTrue(html.contains("2 ファイル"))
        XCTAssertTrue(html.contains("目次の読み込み 0.2 秒"))
        XCTAssertFalse(html.contains("<script"))
    }

    // 行数の上限を超えたら残り件数を書く
    func testPreviewRowLimit() throws {
        var b = ZipBuilder()
        b.items = (0..<(PreviewHTML.rowLimit + 50)).map { .init(rawName: Data("f\($0).txt".utf8)) }
        let entries = try ZipDirectory.read(ZipDirectory.Reader.memory(b.build())).entries
        let html = PreviewHTML.make(listing: ArchiveListing.build(entries: entries), fileName: "many.zip")
        XCTAssertTrue(html.contains("ほか 50 件"))
    }
}

extension ZipDirectory.Reader {
    /// テスト用：一時ファイル経由でメモリ上のzipを読む
    static func memory(_ data: Data) throws -> ZipDirectory.Reader {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mem-\(UUID().uuidString).zip")
        try data.write(to: url)
        let h = try FileHandle(forReadingFrom: url)
        return ZipDirectory.Reader(handle: h, fileSize: UInt64(data.count))
    }
}
