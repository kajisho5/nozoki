import AppKit
import SwiftUI
import ZipPeekCore

/// 設定画面（デザイン⑧・⑬）
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(tr("一般", "General"), systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label(tr("見た目", "Appearance"), systemImage: "circle.lefthalf.filled") }
            CompressSettings()
                .tabItem { Label(tr("圧縮", "Compression"), systemImage: "archivebox") }
            PreviewSettings()
                .tabItem { Label(tr("スペースキー", "Quick Look"), systemImage: "space") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Picker(tr("圧縮ファイルを渡されたとき", "When given an archive"), selection: $prefs.onArchiveDrop) {
                Text(tr("すぐ解凍する", "Extract right away")).tag(Preferences.ArchiveDropAction.extract)
                Text(tr("中身を見る窓を開く", "Open it to look inside")).tag(Preferences.ArchiveDropAction.browse)
            }
            .pickerStyle(.radioGroup)
            Text(tr("Dockへのドラッグ、ダブルクリック、「このアプリケーションで開く」のとき。optionキーを押しながらだと逆の動きになります。",
                    "Applies to Dock drops, double-clicks and Open With. Hold Option for the other action."))
                .font(.caption).foregroundStyle(.secondary)

            Picker(tr("解凍先", "Extract to"), selection: $prefs.extractTo) {
                Text(tr("元のファイルと同じ場所", "Same folder as the archive")).tag(Preferences.ExtractDestination.sameFolder)
                Text(tr("毎回選ぶ", "Ask every time")).tag(Preferences.ExtractDestination.ask)
            }
            Toggle(tr("中身が複数のときはフォルダにまとめる", "Put multiple items in a folder"), isOn: $prefs.groupIntoFolder)
            Toggle(tr("終わったらFinderで表示する", "Show in Finder when done"), isOn: $prefs.revealWhenDone)
            Toggle(isOn: $prefs.trashAfterExtract) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("解凍したら元の圧縮ファイルをゴミ箱に入れる", "Move the archive to the Trash after extracting"))
                    Text(tr("ゴミ箱に入れるだけで、完全には消しません", "It’s only moved to the Trash, not deleted"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }
}

private struct AppearanceSettings: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Picker(tr("外観", "Appearance"), selection: $prefs.appearance) {
                Text(tr("Macに合わせる", "Match System")).tag(Preferences.Appearance.system)
                Text(tr("ライト", "Light")).tag(Preferences.Appearance.light)
                Text(tr("ダーク", "Dark")).tag(Preferences.Appearance.dark)
            }
            .pickerStyle(.segmented)

            Section(tr("ドラッグ先と作業中の表示", "Drop target and progress")) {
                HStack(spacing: 16) {
                    StyleChoice(title: tr("標準（窓）", "Standard (window)"), selected: prefs.dropStyle == .window) {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.5)).frame(width: 90, height: 50)
                            .overlay(alignment: .bottom) { Capsule().fill(.secondary.opacity(0.3)).frame(width: 36, height: 10).padding(6) }
                    } action: { prefs.dropStyle = .window; WindowManager.shared.showDropTarget() }
                    StyleChoice(title: tr("小窓（ガラス）", "Compact (glass)"), selected: prefs.dropStyle == .compactGlass) {
                        RoundedRectangle(cornerRadius: 18).fill(Color.accentColor.opacity(0.25)).frame(width: 56, height: 56)
                    } action: { prefs.dropStyle = .compactGlass; WindowManager.shared.showDropTarget() }
                }
                Text(tr("macOS 14・15では、ガラスの代わりに従来の半透明になります。", "On macOS 14 and 15, a classic translucent material is used instead of glass."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }
}

private struct StyleChoice<Preview: View>: View {
    let title: String
    let selected: Bool
    @ViewBuilder var preview: Preview
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview.frame(height: 60)
                Text(title).font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                                                         lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct CompressSettings: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Toggle(tr("圧縮のたびに設定を確認する", "Ask for settings every time"), isOn: $prefs.askBeforeCompress)
            Picker(tr("形式", "Format"), selection: $prefs.compressDefaults.format) {
                Text("zip").tag(CompressOptions.Format.zip)
                Text("7z").tag(CompressOptions.Format.sevenZip)
            }
            Picker(tr("圧縮率", "Compression"), selection: $prefs.compressDefaults.level) {
                Text(tr("速さ優先", "Faster")).tag(CompressOptions.Level.fast)
                Text(tr("標準", "Normal")).tag(CompressOptions.Level.normal)
                Text(tr("最小サイズ", "Smallest")).tag(CompressOptions.Level.max)
            }
            Toggle(tr("Windowsで文字化けしない名前にする（zip）", "Japanese Windows–friendly names (zip)"), isOn: $prefs.compressDefaults.windowsNames)
            Toggle(tr("Mac専用の隠しファイルを入れない", "Leave out Mac-only hidden files"), isOn: $prefs.compressDefaults.excludeMacFiles)
            Text(tr("パスワードと分割は、圧縮のたびに設定シートで決めます（保存しません）。",
                    "Password and splitting are chosen each time in the compression sheet (never saved)."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }
}

private struct PreviewSettings: View {
    @State private var status = PreviewExtensionStatus()

    var body: some View {
        Form { PreviewSetupSection(status: status) }
            .formStyle(.grouped)
            .padding(.vertical, 6)
            .onAppear { status.refresh() }
    }
}

/// スペースキー機能（クイックルック拡張）の案内
struct PreviewSetupSection: View {
    @Bindable var status: PreviewExtensionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Finderでスペースキーを押して中身を見る", "Press Space in Finder to look inside")).font(.headline)
                Spacer()
                StatusChip(state: status.state)
            }
            Text(tr("最初に1回だけ、Macの設定でこの機能をオンにします。ZipPeek を「アプリケーション」フォルダに入れてから行ってください。",
                    "Turn this on once in System Settings. Move ZipPeek to the Applications folder first."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(tr("設定を開く", "Open System Settings")) { status.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                Button(tr("自動でオンにしてみる", "Try to Turn On")) { status.tryEnable() }
                Spacer()
                Button(tr("状態を確認", "Check")) { status.refresh() }.buttonStyle(.borderless)
            }
            if let note = status.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatusChip: View {
    let state: PreviewExtensionStatus.State

    var body: some View {
        let (label, color): (String, Color) = switch state {
        case .enabled: (tr("オン", "On"), .green)
        case .disabled: (tr("オフ", "Off"), .orange)
        case .unknown: (tr("確認中", "Checking"), .secondary)
        case .notRegistered: (tr("未登録", "Not registered"), .orange)
        }
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 2)
            .foregroundStyle(color)
            .overlay(Capsule().stroke(color.opacity(0.6)))
    }
}

/// クイックルック拡張がオンかどうかを pluginkit で確かめる
@MainActor
@Observable
final class PreviewExtensionStatus {
    enum State { case unknown, enabled, disabled, notRegistered }

    nonisolated static let extensionID = "com.kajisho5.zippeek.preview"

    var state: State = .unknown
    var note: String?

    func refresh() {
        Task.detached {
            let out = Self.run("/usr/bin/pluginkit", ["-m", "-A", "-i", Self.extensionID])
            let line = out.split(separator: "\n").first { $0.contains(Self.extensionID) }.map(String.init)
            let newState: State
            if let line {
                newState = line.trimmingCharacters(in: .whitespaces).hasPrefix("-") ? .disabled : .enabled
            } else {
                newState = .notRegistered
            }
            await MainActor.run { self.state = newState }
        }
    }

    func tryEnable() {
        note = nil
        Task.detached {
            _ = Self.run("/usr/bin/pluginkit", ["-e", "use", "-i", Self.extensionID])
            _ = Self.run("/usr/bin/qlmanage", ["-r"])
            await MainActor.run {
                self.refresh()
                self.note = tr("Finderで圧縮ファイルを選んでスペースキーを押して確かめてください。変わらなければ「設定を開く」から手動でオンにしてください。",
                               "Select an archive in Finder and press Space. If nothing changes, turn it on manually in System Settings.")
            }
        }
    }

    /// Macの設定の「機能拡張」画面を開く（開けなければ設定アプリそのものを開く）
    func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ]
        for c in candidates {
            if let url = URL(string: c), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    nonisolated static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
