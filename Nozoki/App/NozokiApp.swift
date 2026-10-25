import SwiftUI

@main
struct NozokiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // zipごとの窓は WindowManager が開く（30GBのzipでも中身を読み込まないよう、文書型の仕組みは使わない）
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("zipを開く…") { WindowManager.shared.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .help) {
                Button("はじめにの画面を表示") { WindowManager.shared.showWelcome() }
                Link("nozoki のページ（GitHub）", destination: URL(string: "https://github.com/kajisho5/zippeek")!)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openedFileAtLaunch = false

    func application(_ application: NSApplication, open urls: [URL]) {
        openedFileAtLaunch = true
        for url in urls { WindowManager.shared.open(url) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Finderからzipを渡されて起動した場合は、その窓だけを出す
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !self.openedFileAtLaunch && WindowManager.shared.archiveWindowCount == 0 {
                WindowManager.shared.showWelcome()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.shared.showWelcome() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        TempFiles.removeAll()
    }
}
