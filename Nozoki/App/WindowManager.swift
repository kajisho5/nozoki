import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// zipごとの窓と「はじめに」窓を管理する
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var archiveWindows: [URL: (window: NSWindow, model: ArchiveModel)] = [:]
    private var welcomeWindow: NSWindow?

    var archiveWindowCount: Int { archiveWindows.count }

    func open(_ rawURL: URL) {
        let url = rawURL.standardizedFileURL
        if let existing = archiveWindows[url] {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        let model = ArchiveModel(url: url)
        let host = NSHostingController(rootView: ArchiveView(model: model))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1000, height: 640))
        window.contentMinSize = NSSize(width: 760, height: 460)
        window.title = url.lastPathComponent
        window.representedURL = url
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .automatic
        if let key = NSApp.keyWindow, key !== welcomeWindow {
            window.setFrameTopLeftPoint(NSPoint(x: key.frame.minX + 24, y: key.frame.maxY - 24))
        } else {
            window.center()
        }
        archiveWindows[url] = (window, model)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.close()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        model.load()
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "中身を見たいzipを選んでください"
        panel.prompt = "開く"
        if panel.runModal() == .OK {
            for url in panel.urls { open(url) }
        }
    }

    func showWelcome() {
        if let w = welcomeWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: WelcomeView())
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "nozoki へようこそ"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        welcomeWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === welcomeWindow {
            welcomeWindow = nil
            return
        }
        if let entry = archiveWindows.first(where: { $0.value.window === window }) {
            entry.value.model.close()
            archiveWindows.removeValue(forKey: entry.key)
        }
    }
}

/// プレビューやドラッグのために取り出した一時ファイルの置き場
enum TempFiles {
    static let root: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nozoki", isDirectory: true)
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
