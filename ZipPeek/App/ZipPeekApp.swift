import SwiftUI
import ZipPeekCore

@main
struct ZipPeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 窓は WindowManager が開く（30GBの圧縮ファイルでも中身を読み込まないよう、文書型の仕組みは使わない）
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(tr("圧縮・解凍するものを選ぶ…", "Compress or Extract…")) { WindowManager.shared.showOpenPanel() }
                    .keyboardShortcut("o")
                Button(tr("中身を見る…", "Look Inside…")) { WindowManager.shared.showBrowsePanel() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button(tr("ドラッグ先を表示", "Show Drop Target")) { WindowManager.shared.showDropTarget() }
                    .keyboardShortcut("n")
            }
            CommandGroup(replacing: .help) {
                Link(tr("ZipPeek のページ（GitHub）", "ZipPeek on GitHub"),
                     destination: URL(string: "https://github.com/kajisho5/zippeek")!)
                Link(tr("7-Zip のライセンス", "7-Zip License"),
                     destination: URL(string: "https://www.7-zip.org/license.txt")!)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var receivedFilesAtLaunch = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        Preferences.shared.applyAppearance()
        // Finderの右クリック（サービス）を受け取る
        NSApp.servicesProvider = ServiceProvider.shared
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedFilesAtLaunch = true
        DropRouter.handle(urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dockへのドラッグなどで起動した場合は、ドラッグ先の窓を出さない
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !self.receivedFilesAtLaunch && WindowManager.shared.archiveWindowCount == 0 {
                WindowManager.shared.showDropTarget()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.shared.showDropTarget() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !JobQueue.shared.hasActiveJobs
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard JobQueue.shared.hasActiveJobs else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = tr("作業中です。終了しますか？", "ZipPeek is still working. Quit anyway?")
        alert.informativeText = tr("終了すると、作業中の圧縮・解凍は中止されます。", "Compressing or extracting in progress will be cancelled.")
        alert.addButton(withTitle: tr("終了する", "Quit"))
        alert.addButton(withTitle: tr("続ける", "Keep Working"))
        if alert.runModal() == .alertFirstButtonReturn {
            for job in JobQueue.shared.jobs { JobQueue.shared.cancel(job.id) }
            return .terminateNow
        }
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        TempFiles.removeAll()
    }
}
