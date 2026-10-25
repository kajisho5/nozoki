import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZipPeekCore

/// 窓をまとめて管理する（中身を見る窓、ドラッグ先の窓／小窓、作業中の窓、圧縮の設定、パスワード）
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var archiveWindows: [URL: (window: NSWindow, model: ArchiveModel)] = [:]
    private var dropWindow: NSWindow?
    private var compactWindow: NSWindow?
    private var jobsWindow: NSWindow?
    private var compressWindows: [NSWindow] = []

    var archiveWindowCount: Int { archiveWindows.count }

    // MARK: 中身を見る窓

    private let openArchivesKey = "openArchiveWindows"

    /// 終了時に開いていた窓を覚える（Macの設定で「終了時にウインドウを閉じる」がオンなら覚えない）
    func saveOpenArchiveWindows() {
        let keepWindows = UserDefaults.standard.bool(forKey: "NSQuitAlwaysKeepsWindows")
        let paths = keepWindows ? archiveWindows.keys.map(\.path) : []
        UserDefaults.standard.set(paths, forKey: openArchivesKey)
    }

    func restoreArchiveWindows() {
        let paths = UserDefaults.standard.stringArray(forKey: openArchivesKey) ?? []
        UserDefaults.standard.removeObject(forKey: openArchivesKey)
        for path in paths where FileManager.default.fileExists(atPath: path) {
            open(URL(fileURLWithPath: path))
        }
    }

    func open(_ rawURL: URL) {
        let url = ArchiveKind.firstVolume(of: rawURL).standardizedFileURL
        if let existing = archiveWindows[url] {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        let model = ArchiveModel(url: url)
        let host = NSHostingController(rootView: ArchiveView(model: model))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1000, height: 640))
        window.contentMinSize = NSSize(width: 760, height: 460)
        window.title = url.lastPathComponent
        window.representedURL = url
        // ツールバーは SwiftUI 側（ArchiveView の .toolbar）から作る
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .automatic
        if let key = NSApp.keyWindow, archiveWindows.values.contains(where: { $0.window === key }) {
            window.setFrameTopLeftPoint(NSPoint(x: key.frame.minX + 24, y: key.frame.maxY - 24))
        } else {
            window.center()
        }
        archiveWindows[url] = (window, model)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        model.load()
    }

    /// メニュー「中身を見る…」：圧縮ファイルを選んで中身を見る窓で開く
    func showBrowsePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose archives to look inside")
        panel.prompt = String(localized: "Open")
        if panel.runModal() == .OK {
            for url in panel.urls { open(url) }
        }
    }

    /// 「開く…」：何でも選べる。圧縮ファイルは解凍（設定どおり）、それ以外は圧縮
    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = String(localized: "Choose items to compress or extract")
        panel.prompt = String(localized: "Choose")
        if panel.runModal() == .OK {
            DropRouter.handle(panel.urls, alternate: false)
        }
    }

    // MARK: ドラッグ先（標準＝窓 A4 ／ 小窓 A5）

    func showDropTarget() {
        switch Preferences.shared.dropStyle {
        case .window:
            compactWindow?.close()
            showDropWindow()
        case .compactGlass:
            dropWindow?.close()
            showCompactWindow()
        }
    }

    private func showDropWindow() {
        if let w = dropWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: DropWindowView())
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "ZipPeek"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        Self.centerAfterLayout(window)
        dropWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showCompactWindow() {
        if let w = compactWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: CompactDropView())
        host.sizingOptions = .preferredContentSize
        let window = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                                   styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentViewController = host
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("ZipPeekCompactWindow")
        if !window.setFrameUsingName("ZipPeekCompactWindow") { window.center() }
        compactWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeCompactWindow() { compactWindow?.close() }

    /// SwiftUI の中身の大きさが決まってから中央に置く（先に置くと下に伸びて Dock に隠れるため）。
    /// 画面に収まらないときは、画面の上端に合わせる
    static func centerAfterLayout(_ window: NSWindow) {
        if let view = window.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            let size = view.fittingSize
            if size.width > 0, size.height > 0 { window.setContentSize(size) }
        }
        window.center()
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame, window.frame.maxY > visible.maxY || window.frame.minY < visible.minY {
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: visible.maxY))
        }
    }

    // MARK: 作業中の表示

    /// 作業が始まったら：標準は作業中の窓、小窓モードは小窓の中に出す
    func showProgress() {
        switch Preferences.shared.dropStyle {
        case .compactGlass:
            showCompactWindow()
        case .window:
            if let w = jobsWindow {
                w.orderFront(nil)
                return
            }
            let host = NSHostingController(rootView: JobsView())
            host.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: host)
            window.title = String(localized: "Activity")
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            if let drop = dropWindow, drop.isVisible {
                window.setFrameTopLeftPoint(NSPoint(x: drop.frame.maxX + 16, y: drop.frame.maxY))
            } else {
                window.center()
            }
            jobsWindow = window
            window.orderFront(nil)
        }
    }

    /// 作業が全部終わったら、少し待って作業中の窓を閉じる（失敗があれば残す）
    func progressChanged() {
        let queue = JobQueue.shared
        guard !queue.hasActiveJobs else { return }
        let hasFailure = queue.jobs.contains { if case .failed = $0.state { return true } else { return false } }
        guard !hasFailure else { return }
        // 終わったらFinderで表示する設定がオフのときは、結果を見落とさないよう窓を残す（時間で消える表示に頼らない）
        guard Preferences.shared.revealWhenDone else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, !JobQueue.shared.hasActiveJobs else { return }
            JobQueue.shared.clearFinished()
            self.jobsWindow?.close()
        }
    }

    // MARK: 圧縮の設定

    func showCompressOptions(for urls: [URL]) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        let view = CompressSheetView(inputs: urls) { [weak self, weak window] options in
            if let options { JobQueue.shared.enqueueCompress(urls, options: options) }
            window?.close()
            if let window { self?.compressWindows.removeAll { $0 === window } }
        }
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize
        window.contentViewController = host
        window.title = String(localized: "Compress")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        Self.centerAfterLayout(window)
        compressWindows.append(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: パスワード

    /// パスワードを聞く。やめたら nil。入力は保存しない
    func askPassword(for name: String, wasWrong: Bool) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            var resumed = false
            let view = PasswordView(fileName: name, wasWrong: wasWrong) { [weak window] value in
                guard !resumed else { return }
                resumed = true
                window?.close()
                continuation.resume(returning: value)
            }
            let host = NSHostingController(rootView: view)
            host.sizingOptions = .preferredContentSize
            window.contentViewController = host
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.level = .floating
            Self.centerAfterLayout(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: 後片付け

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === dropWindow { dropWindow = nil; return }
        if window === compactWindow { compactWindow = nil; return }
        if window === jobsWindow { jobsWindow = nil; return }
        if let entry = archiveWindows.first(where: { $0.value.window === window }) {
            entry.value.model.close()
            archiveWindows.removeValue(forKey: entry.key)
        }
    }
}

/// 枠のない小窓でもキーボード（⌘W など）を受け取れるようにする
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    // 枠のない窓は閉じるボタンがないため、⌘W（performClose）が警告音になる。ここで閉じる
    override func performClose(_ sender: Any?) { close() }
}

/// プレビューやドラッグのために取り出した一時ファイルの置き場
enum TempFiles {
    static let root: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ZipPeek", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func newFolder() -> URL {
        let url = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
