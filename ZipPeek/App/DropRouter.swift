import AppKit
import ZipPeekCore

/// Dockへのドラッグ・「このアプリケーションで開く」・窓へのドラッグ・右クリックで渡されたものを振り分ける
@MainActor
enum DropRouter {
    /// どこから渡されたか。ダブルクリック（開く）とドラッグで、圧縮ファイルの扱いを分ける
    enum Source { case drop, open }

    /// 渡されたものに応じて解凍・中身を見る・圧縮を行う。
    /// option キーを押しながらなら「逆の動き」（解凍⇔中身を見る、圧縮は設定シートを必ず出す）
    static func handle(_ urls: [URL], source: Source = .drop, alternate: Bool = NSEvent.modifierFlags.contains(.option)) {
        let archives = urls.filter(ArchiveKind.isArchive)
        let others = urls.filter { !ArchiveKind.isArchive($0) }

        if !archives.isEmpty {
            var action = source == .open ? Preferences.shared.onArchiveOpen : Preferences.shared.onArchiveDrop
            if alternate { action = action == .extract ? .browse : .extract }
            switch action {
            case .extract: JobQueue.shared.enqueueExtract(archives)
            case .browse: for url in archives { WindowManager.shared.open(url) }
            }
        }
        if !others.isEmpty {
            compress(others, ask: Preferences.shared.askBeforeCompress || alternate)
        }
    }

    /// いま処理中の「開く」の依頼を、どのアプリが送ってきたか。Dock からならドラッグ、それ以外（Finder のダブルクリック、
    /// 「このアプリケーションで開く」、open コマンドなど）は「開く」として扱う
    static func sourceOfCurrentOpenEvent() -> Source {
        let senderPID = AEKeyword(0x7370_6964)  // 'spid'（送り主のプロセス番号）
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let desc = event.attributeDescriptor(forKeyword: senderPID) else { return .open }
        let app = NSRunningApplication(processIdentifier: pid_t(desc.int32Value))
        return app?.bundleIdentifier == "com.apple.dock" ? .drop : .open
    }

    static func compress(_ urls: [URL], ask: Bool) {
        guard !urls.isEmpty else { return }
        if ask {
            WindowManager.shared.showCompressOptions(for: urls)
        } else {
            JobQueue.shared.enqueueCompress(urls, options: Preferences.shared.compressDefaults)
        }
    }
}

/// Finderの右クリック（サービス）から呼ばれる係
@MainActor
final class ServiceProvider: NSObject {
    static let shared = ServiceProvider()

    private func urls(from pboard: NSPasteboard) -> [URL] {
        (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    @objc func compressFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        DropRouter.compress(urls(from: pboard), ask: Preferences.shared.askBeforeCompress)
    }

    @objc func extractFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let archives = urls(from: pboard).filter(ArchiveKind.isArchive)
        if archives.isEmpty {
            error.pointee = String(localized: "No archive is selected.") as NSString
            return
        }
        JobQueue.shared.enqueueExtract(archives)
    }

    @objc func browseFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        for url in urls(from: pboard).filter(ArchiveKind.isArchive) { WindowManager.shared.open(url) }
    }
}
