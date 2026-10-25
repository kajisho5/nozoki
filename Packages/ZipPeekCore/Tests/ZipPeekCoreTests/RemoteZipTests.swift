import XCTest
import ZIPFoundation
@testable import ZipPeekCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// リンクのままのぞく：手元に「途中から読める」小さなサーバーを立てて確かめる
final class RemoteZipTests: XCTestCase {
    var dir: URL!
    var server: Process?
    var port = 0

    /// Range（途中から読む）に対応した、試験用の小さなサーバー
    static let serverScript = """
    import http.server, os, re, sys
    class H(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a): pass
        def do_GET(self):
            path = self.translate_path(self.path)
            if not os.path.isfile(path):
                self.send_error(404); return
            size = os.path.getsize(path)
            rng = self.headers.get('Range')
            if not rng or sys.argv[2] == 'norange':
                self.send_response(200); self.send_header('Content-Length', str(size)); self.end_headers()
                with open(path, 'rb') as f: self.wfile.write(f.read())
                return
            m = re.match(r'bytes=(\\d*)-(\\d*)', rng)
            a, b = m.group(1), m.group(2)
            if a == '': start, end = max(0, size - int(b)), size - 1
            else: start, end = int(a), (int(b) if b else size - 1)
            end = min(end, size - 1)
            self.send_response(206)
            self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, size))
            self.send_header('Content-Length', str(end - start + 1)); self.end_headers()
            with open(path, 'rb') as f:
                f.seek(start); self.wfile.write(f.read(end - start + 1))
    s = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
    print(s.server_address[1], flush=True)
    s.serve_forever()
    """

    func startServer(rangeSupport: Bool) throws {
        let script = dir.appendingPathComponent("server.py")
        try Self.serverScript.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", script.path, dir.path, rangeSupport ? "range" : "norange"]
        p.currentDirectoryURL = dir
        let out = Pipe()
        p.standardOutput = out
        do { try p.run() } catch { throw XCTSkip("python3 が無い") }
        server = p
        var line = Data()
        while !line.contains(0x0A) {
            let d = out.fileHandleForReading.availableData
            if d.isEmpty { break }
            line.append(d)
        }
        port = Int(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard port > 0 else { throw XCTSkip("試験用サーバーが起動しない") }
    }

    override func setUpWithError() throws {
        L10n.override = true
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("zpr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 架空の素材で zip を作る（圧縮あり・なし、日本語の名前、大きめのファイル）
        let zip = dir.appendingPathComponent("sample.zip")
        let src = dir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("架空の撮影/RAW"), withIntermediateDirectories: true)
        try Data("架空の台本です\n".utf8).write(to: src.appendingPathComponent("架空の撮影/台本.txt"))
        try Data((0..<800_000).map { _ in UInt8.random(in: 0...255) }).write(to: src.appendingPathComponent("架空の撮影/RAW/clip_0101.bin"))
        try Data("hello".utf8).write(to: src.appendingPathComponent("readme.txt"))
        let archive = try Archive(url: zip, accessMode: .create)
        try archive.addEntry(with: "架空の撮影/台本.txt", relativeTo: src, compressionMethod: .deflate)
        try archive.addEntry(with: "架空の撮影/RAW/clip_0101.bin", relativeTo: src, compressionMethod: .deflate)
        try archive.addEntry(with: "readme.txt", relativeTo: src, compressionMethod: .none)
    }

    override func tearDownWithError() throws {
        server?.terminate()
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    func testListAndExtractOverHTTP() throws {
        try startServer(rangeSupport: true)
        let remote = try RemoteZip(url: URL(string: "http://127.0.0.1:\(port)/sample.zip")!)
        try remote.load()
        let listing = ArchiveListing.build(entries: remote.entries)
        XCTAssertEqual(Set(listing.allFiles.map(\.path)), ["架空の撮影/台本.txt", "架空の撮影/RAW/clip_0101.bin", "readme.txt"])
        // 目次を読むのに取り寄せたのは、ファイル全体よりずっと少ない
        XCTAssertLessThan(remote.bytesFetched, remote.size / 4)

        let out = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for item in listing.allFiles {
            let entry = remote.entries[item.entryIndex!]
            let file = try remote.extract(entry, as: item.name, into: out)
            if item.name == "台本.txt" { XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "架空の台本です\n") }
            if item.name == "readme.txt" { XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hello") }
            if item.name == "clip_0101.bin" { XCTAssertEqual(try Data(contentsOf: file), try Data(contentsOf: dir.appendingPathComponent("src/架空の撮影/RAW/clip_0101.bin"))) }
        }
    }

    func testServerWithoutRangeSupport() throws {
        try startServer(rangeSupport: false)
        let remote = try RemoteZip(url: URL(string: "http://127.0.0.1:\(port)/sample.zip")!)
        XCTAssertThrowsError(try remote.load()) { XCTAssertEqual($0 as? RemoteZip.Failure, .noRangeSupport) }
    }

    func testBadLink() {
        XCTAssertThrowsError(try RemoteZip(url: URL(string: "file:///tmp/a.zip")!))
    }
}
