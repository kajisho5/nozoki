import AppKit
import Security

/// 新しい版の確認と入れ替え。
/// - GitHub の最新リリースを調べ（起動時は1日に1回まで、メニューからはいつでも）、新しければ知らせる
/// - 「アップデート」で dmg を落とし、中のアプリがこのアプリと同じ開発者（チームID）の署名か確かめてから入れ替え、再起動する
/// - 署名が確かめられないとき（署名なしの試し版など）は、入れ替えずにリリースのページを開く
@MainActor
final class Updater {
    static let shared = Updater()

    struct Release {
        let version: String
        let page: URL
        let dmg: URL?
    }

    /// 調べる先。試験のときだけ環境変数で差し替えられる
    private var feedURL: URL {
        if let s = ProcessInfo.processInfo.environment["ZIPPEEK_UPDATE_FEED"], let u = URL(string: s) { return u }
        return URL(string: "https://api.github.com/repos/kajisho5/zippeek/releases/latest")!
    }

    private let d = UserDefaults.standard
    private var checking = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: 確認

    /// 起動時：設定でオフなら何もしない。前回から1日たっていなければ何もしない
    func checkOnLaunch() {
        guard Preferences.shared.checkForUpdates else { return }
        let last = d.double(forKey: "lastUpdateCheck")
        let forced = ProcessInfo.processInfo.environment["ZIPPEEK_UPDATE_FEED"] != nil
        guard forced || Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }

    /// メニュー「アップデートを確認…」
    func checkFromMenu() {
        Task { await check(userInitiated: true) }
    }

    private func check(userInitiated: Bool) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        do {
            let release = try await fetchLatest()
            d.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
            guard Self.isNewer(release.version, than: currentVersion) else {
                if userInitiated {
                    alert(String(localized: "ZipPeek is up to date"),
                          String(localized: "You have the latest version (\(currentVersion))."))
                }
                return
            }
            if !userInitiated && d.string(forKey: "skippedVersion") == release.version { return }
            offer(release)
        } catch {
            if userInitiated {
                alert(String(localized: "Couldn’t check for updates"), error.localizedDescription)
            }
        }
    }

    private func fetchLatest() async throws -> Release {
        var req = URLRequest(url: feedURL, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ZipPeek/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            throw UpdateError.badFeed
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }?["browser_download_url"] as? String
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page, dmg: dmg.flatMap(URL.init(string:)))
    }

    /// "0.10.0" > "0.9.1" のように数字ごとに比べる
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: 知らせる

    private func offer(_ release: Release) {
        let a = NSAlert()
        a.messageText = String(localized: "ZipPeek \(release.version) is available")
        a.informativeText = String(localized: "You have \(currentVersion). Update now? ZipPeek will restart.")
        a.addButton(withTitle: String(localized: "Update"))
        a.addButton(withTitle: String(localized: "Later"))
        a.addButton(withTitle: String(localized: "Skip This Version"))
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn: Task { await install(release) }
        case .alertThirdButtonReturn: d.set(release.version, forKey: "skippedVersion")
        default: break
        }
    }

    // MARK: 入れ替え

    enum UpdateError: LocalizedError {
        case badFeed, notSigned, cannotReplace, mountFailed
        var errorDescription: String? {
            switch self {
            case .badFeed: String(localized: "The update information couldn’t be read.")
            case .notSigned: String(localized: "The downloaded app isn’t signed by the ZipPeek developer, so it wasn’t installed.")
            case .cannotReplace: String(localized: "ZipPeek couldn’t replace itself. Please install the new version from the website.")
            case .mountFailed: String(localized: "The downloaded disk image couldn’t be opened.")
            }
        }
    }

    private func install(_ release: Release) async {
        // 作業中は入れ替えない
        guard !JobQueue.shared.hasActiveJobs else {
            alert(String(localized: "ZipPeek is still working"), String(localized: "Try updating again when compressing or extracting is finished."))
            return
        }
        // 署名を確かめられない（このアプリ自体が署名されていない）ときや、dmg が無いときはページを開くだけ
        guard let team = Self.teamIdentifier(of: Bundle.main.bundleURL), let dmg = release.dmg else {
            NSWorkspace.shared.open(release.page)
            return
        }
        let progress = ProgressPanel(title: String(localized: "Downloading ZipPeek \(release.version)…"))
        progress.show()
        do {
            let (file, _) = try await URLSession.shared.download(from: dmg)
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("zippeek-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let dmgFile = work.appendingPathComponent("update.dmg")
            try FileManager.default.moveItem(at: file, to: dmgFile)
            progress.update(String(localized: "Checking the signature…"))
            let newApp = try await Task.detached { try Self.copyApp(fromDMG: dmgFile, into: work) }.value
            guard Self.isSigned(newApp, team: team, identifier: Bundle.main.bundleIdentifier ?? "") else { throw UpdateError.notSigned }
            progress.update(String(localized: "Installing…"))
            let current = Bundle.main.bundleURL
            do {
                _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp, backupItemName: nil, options: [])
            } catch {
                throw UpdateError.cannotReplace
            }
            progress.close()
            relaunch(current)
        } catch {
            progress.close()
            alert(String(localized: "Update failed"), error.localizedDescription)
            if case UpdateError.cannotReplace = error { NSWorkspace.shared.open(release.page) }
        }
    }

    /// dmg を開いて中の .app を作業フォルダへ写し、dmg を閉じる
    nonisolated private static func copyApp(fromDMG dmg: URL, into work: URL) throws -> URL {
        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path, dmg.path]) == 0 else {
            throw UpdateError.mountFailed
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }
        let items = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []
        guard let app = items.first(where: { $0.pathExtension == "app" }) else { throw UpdateError.mountFailed }
        let dest = work.appendingPathComponent(app.lastPathComponent)
        // ditto で写すと、署名に必要な情報（拡張属性など）も保たれる
        guard run("/usr/bin/ditto", [app.path, dest.path]) == 0 else { throw UpdateError.mountFailed }
        return dest
    }

    /// アプリの署名のチームID（署名されていなければ nil）
    nonisolated static func teamIdentifier(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Apple が発行した Developer ID で、同じチーム・同じアプリIDとして正しく署名されているか（中の部品まで）
    nonisolated static func isSigned(_ app: URL, team: String, identifier: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        var req: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &req) == errSecSuccess else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess
    }

    /// 今のアプリが終わるのを待ってから、新しいアプリを開く
    private func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"\(app.path)\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    nonisolated private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

/// ダウンロード中などに出す小さな窓
@MainActor
private final class ProgressPanel {
    private let window: NSPanel
    private let label = NSTextField(labelWithString: "")

    init(title: String) {
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 90), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "ZipPeek"
        let bar = NSProgressIndicator()
        bar.isIndeterminate = true
        bar.style = .bar
        bar.startAnimation(nil)
        label.stringValue = title
        let stack = NSStackView(views: [label, bar])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        bar.widthAnchor.constraint(equalToConstant: 300).isActive = true
        window.contentView = stack
        window.center()
    }

    func show() { window.makeKeyAndOrderFront(nil) }
    func update(_ text: String) { label.stringValue = text }
    func close() { window.close() }
}
