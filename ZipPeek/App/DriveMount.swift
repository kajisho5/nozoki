import AppKit
import ZipPeekCore

/// 圧縮ファイルを、Finder からドライブのように見られるようにつなぐ（解凍しない。macOS 26 以降）。
/// つなぐ処理はアプリに入れた部品（ZipPeekMount.appex、Apple の FSKit）が行う。部品は最初に一度、
/// 使う人が「システム設定 → 一般 → ログイン項目と機能拡張 → ZipPeek」でオンにする必要がある（Apple の決まり）
@MainActor
enum DriveMount {
    enum Failure: LocalizedError {
        case unsupported, notEnabled, failed(String)
        var errorDescription: String? {
            switch self {
            case .unsupported: String(localized: "Opening as a drive needs macOS 26 or later.")
            case .notEnabled: String(localized: "Turn on ZipPeek’s file system extension first.")
            case .failed(let m): String(localized: "Couldn’t open it as a drive.") + "\n" + m
            }
        }
    }

    /// この Mac とこのアプリで使えるか（部品が入っていて、macOS 26 以降）
    static var isAvailable: Bool {
        guard #available(macOS 26, *) else { return false }
        return FileManager.default.fileExists(atPath: Bundle.main.bundleURL
            .appendingPathComponent("Contents/Extensions/ZipPeekMount.appex").path)
    }

    /// つないだ場所（つなぐたびに新しい場所を使う。失敗した場所はしばらく使えなくなるため）
    private static func newMountPoint(for archive: URL) throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZipPeek/Drives", isDirectory: true)
        let name = ArchiveKind.baseName(of: archive)
        var url = base.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            if (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.isEmpty == true,
               !isMounted(url) { try? FileManager.default.removeItem(at: url); break }
            url = base.appendingPathComponent("\(name) \(n)", isDirectory: true)
            n += 1
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func isMounted(_ url: URL) -> Bool {
        var s = statfs()
        guard statfs(url.path, &s) == 0 else { return false }
        let mountedOn = withUnsafePointer(to: &s.f_mntonname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
        return mountedOn == url.standardizedFileURL.path
    }

    /// つないで、つないだ場所を返す
    static func mount(_ archive: URL) async throws -> URL {
        guard isAvailable else { throw Failure.unsupported }
        let point = try newMountPoint(for: archive)
        let result: (Int32, String) = await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/sbin/mount")
            p.arguments = ["-F", "-t", "zippeek", archive.standardizedFileURL.path, point.path]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = Pipe()
            do { try p.run() } catch { return (-1, error.localizedDescription) }
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }.value
        if result.0 != 0 {
            try? FileManager.default.removeItem(at: point)
            if result.1.contains("disabled") { throw Failure.notEnabled }
            throw Failure.failed(result.1.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return point
    }

    /// 「ドライブとして開く」：つないで Finder で開く。部品がオフなら、オンにする場所を案内する
    static func openAsDrive(_ archive: URL) {
        Task {
            do {
                let point = try await mount(archive)
                NSWorkspace.shared.open(point)
            } catch Failure.notEnabled {
                let a = NSAlert()
                a.messageText = String(localized: "Turn On “Open as Drive”")
                a.informativeText = String(localized: "macOS asks you to allow ZipPeek’s file system extension once. In System Settings, open General → Login Items & Extensions, click ⓘ next to ZipPeek, and turn on FSKit Modules. Then try again.")
                a.addButton(withTitle: String(localized: "Open System Settings"))
                a.addButton(withTitle: String(localized: "Cancel"))
                if a.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            } catch {
                let a = NSAlert()
                a.messageText = String(localized: "Couldn’t Open as a Drive")
                a.informativeText = error.localizedDescription
                a.runModal()
            }
        }
    }
}
