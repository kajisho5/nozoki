import AppKit
import SwiftUI
import ZipPeekCore

/// 設定画面（デザイン⑧・⑬）
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label(String(localized: "Appearance"), systemImage: "circle.lefthalf.filled") }
            CompressSettings()
                .tabItem { Label(String(localized: "Compression"), systemImage: "archivebox") }
            PreviewSettings()
                .tabItem { Label(String(localized: "Quick Look"), systemImage: "space") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @Bindable private var prefs = Preferences.shared
    @State private var defaultApp = DefaultAppStatus()

    var body: some View {
        Form {
            Section {
                DefaultAppSection(status: defaultApp, showRestore: true)
            }
            Section {
                Picker(String(localized: "When you double-click an archive"), selection: $prefs.onArchiveOpen) {
                    Text(String(localized: "Open it to look inside")).tag(Preferences.ArchiveDropAction.browse)
                    Text(String(localized: "Extract right away")).tag(Preferences.ArchiveDropAction.extract)
                }
                .pickerStyle(.radioGroup)
                Picker(String(localized: "When you drop an archive on the Dock icon"), selection: $prefs.onArchiveDrop) {
                    Text(String(localized: "Extract right away")).tag(Preferences.ArchiveDropAction.extract)
                    Text(String(localized: "Open it to look inside")).tag(Preferences.ArchiveDropAction.browse)
                }
                .pickerStyle(.radioGroup)
                Text(String(localized: "Double-click also covers Open With. Hold Option for the other action."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Picker(String(localized: "Extract to"), selection: $prefs.extractTo) {
                Text(String(localized: "Same folder as the archive")).tag(Preferences.ExtractDestination.sameFolder)
                Text(String(localized: "Ask every time")).tag(Preferences.ExtractDestination.ask)
            }
            Toggle(String(localized: "Put multiple items in a folder"), isOn: $prefs.groupIntoFolder)
            Toggle(String(localized: "Show in Finder when done"), isOn: $prefs.revealWhenDone)
            Toggle(isOn: $prefs.trashAfterExtract) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Move the archive to the Trash after extracting"))
                    Text(String(localized: "It’s only moved to the Trash, not deleted"))
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
            Section(String(localized: "Drop target and progress")) {
                HStack(spacing: 16) {
                    StyleChoice(title: String(localized: "Standard (window)"), selected: prefs.dropStyle == .window) {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.5)).frame(width: 90, height: 50)
                            .overlay(alignment: .bottom) { Capsule().fill(.secondary.opacity(0.3)).frame(width: 36, height: 10).padding(6) }
                    } action: { prefs.dropStyle = .window; WindowManager.shared.showDropTarget() }
                    StyleChoice(title: String(localized: "Compact (glass)"), selected: prefs.dropStyle == .compactGlass) {
                        RoundedRectangle(cornerRadius: 18).fill(Color.accentColor.opacity(0.25)).frame(width: 56, height: 56)
                    } action: { prefs.dropStyle = .compactGlass; WindowManager.shared.showDropTarget() }
                }
                Text(String(localized: "On macOS 14 and 15, a classic translucent material is used instead of glass."))
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
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CompressSettings: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Toggle(String(localized: "Ask for settings every time"), isOn: $prefs.askBeforeCompress)
            Picker(String(localized: "Format"), selection: $prefs.compressDefaults.format) {
                Text(verbatim: "zip").tag(CompressOptions.Format.zip)
                Text(verbatim: "7z").tag(CompressOptions.Format.sevenZip)
            }
            Picker(String(localized: "Compression Level"), selection: $prefs.compressDefaults.level) {
                Text(String(localized: "Faster")).tag(CompressOptions.Level.fast)
                Text(String(localized: "Normal")).tag(CompressOptions.Level.normal)
                Text(String(localized: "Smallest")).tag(CompressOptions.Level.max)
            }
            Toggle(String(localized: "Japanese Windows–friendly names (zip)"), isOn: $prefs.compressDefaults.windowsNames)
            Toggle(String(localized: "Leave out Mac-only hidden files"), isOn: $prefs.compressDefaults.excludeMacFiles)
            Text(String(localized: "Password and splitting are chosen each time in the compression sheet (never saved)."))
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
                Text(String(localized: "Press Space in Finder to look inside")).font(.headline)
                Spacer()
                StatusChip(state: status.state)
            }
            Text(String(localized: "Turn this on once in System Settings. Move ZipPeek to the Applications folder first."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(String(localized: "Open System Settings")) { status.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                Button(String(localized: "Try to Turn On")) { status.tryEnable() }
                Spacer()
                Button(String(localized: "Check")) { status.refresh() }.buttonStyle(.borderless)
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
        case .enabled: (String(localized: "On"), .green)
        case .disabled: (String(localized: "Off"), .orange)
        case .unknown: (String(localized: "Checking"), .secondary)
        case .notRegistered: (String(localized: "Not registered"), .orange)
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
                self.note = String(localized: "Select an archive in Finder and press Space. If nothing changes, turn it on manually in System Settings.")
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
