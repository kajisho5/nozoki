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
                Button(String(localized: "Compress or Extract…")) { WindowManager.shared.showOpenPanel() }
                    .keyboardShortcut("o")
                Button(String(localized: "Look Inside…")) { WindowManager.shared.showBrowsePanel() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            // 「表示」メニュー（サイドバー・ツールバーの表示切り替え）
            SidebarCommands()
            ToolbarCommands()
            // 「ウインドウ」メニュー：ドラッグ先の窓（このアプリの主な窓）
            CommandGroup(before: .windowList) {
                Button(String(localized: "Drop Target")) { WindowManager.shared.showDropTarget() }
                    .keyboardShortcut("0")
                Button(String(localized: "Activity")) { WindowManager.shared.showProgress() }
                Divider()
            }
            CommandGroup(replacing: .help) {
                Link(String(localized: "ZipPeek on GitHub"),
                     destination: URL(string: "https://github.com/kajisho5/zippeek")!)
                Link(String(localized: "Support ZipPeek (GitHub Sponsors)"),
                     destination: URL(string: "https://github.com/sponsors/kajisho5")!)
                Link(String(localized: "7-Zip License"),
                     destination: URL(string: "https://www.7-zip.org/license.txt")!)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var receivedFilesAtLaunch = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Finderの右クリック（サービス）を受け取る
        NSApp.servicesProvider = ServiceProvider.shared
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedFilesAtLaunch = true
        DropRouter.handle(urls, source: DropRouter.sourceOfCurrentOpenEvent())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dockへのドラッグなどで起動した場合は、ドラッグ先の窓を出さない
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard !self.receivedFilesAtLaunch else { return }
            // 前回開いていた「中身を見る窓」を戻す（Macの設定「アプリを終了するときにウインドウを閉じる」がオフのとき）
            WindowManager.shared.restoreArchiveWindows()
            if WindowManager.shared.archiveWindowCount == 0 {
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
        alert.messageText = String(localized: "ZipPeek is still working. Quit anyway?")
        alert.informativeText = String(localized: "Compressing or extracting in progress will be cancelled.")
        alert.alertStyle = .warning
        // 取り消せない操作なので、標準の（returnキーで押される）ボタンは「作業を続ける」にする
        alert.addButton(withTitle: String(localized: "Keep Working"))
        let quit = alert.addButton(withTitle: String(localized: "Quit"))
        quit.hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            for job in JobQueue.shared.jobs { JobQueue.shared.cancel(job.id) }
            return .terminateNow
        }
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowManager.shared.saveOpenArchiveWindows()
        TempFiles.removeAll()
    }
}
