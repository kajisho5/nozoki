import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// はじめに画面（デザイン④）。zipのドロップ先も兼ねる
struct WelcomeView: View {
    @State private var preview = PreviewExtensionStatus()
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("nozoki へようこそ").font(.title2).bold()
                Text("zipを展開せずに中身を見て、必要なファイルだけ取り出せます。")
                    .foregroundStyle(.secondary)
            }

            dropZone

            Divider()

            PreviewSetupSection(status: preview)
        }
        .padding(28)
        .frame(width: 460)
        .onAppear { preview.refresh() }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
            Text("ここにzipをドロップ").font(.headline)
            Button("zipを選ぶ…") { WindowManager.shared.showOpenPanel() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                          style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .dropDestination(for: URL.self) { urls, _ in
            let zips = urls.filter { $0.pathExtension.lowercased() == "zip" }
            for url in zips { WindowManager.shared.open(url) }
            return !zips.isEmpty
        } isTargeted: { isDropTargeted = $0 }
    }
}

/// スペースキー機能（クイックルック拡張）の案内。設定画面と共用
struct PreviewSetupSection: View {
    @Bindable var status: PreviewExtensionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Finderでスペースキーを押して中身を見る").font(.headline)
                Spacer()
                StatusChip(state: status.state)
            }
            Text("最初に1回だけ、Macの設定でこの機能をオンにします。nozoki を「アプリケーション」フォルダに入れてから行ってください。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                StepRow(number: 1, text: "下の「設定を開く」を押す")
                StepRow(number: 2, text: "「クイックルック」の一覧で「nozoki」をオンにする")
            }
            HStack {
                Button("設定を開く") { status.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                Button("自動でオンにしてみる") { status.tryEnable() }
                    .help("Macの仕組みを使ってオンにします。うまくいかないときは「設定を開く」から手動で")
                Spacer()
                Button("状態を確認") { status.refresh() }
                    .buttonStyle(.borderless)
            }
            if let note = status.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
                .foregroundStyle(Color.accentColor)
            Text(text)
        }
    }
}

private struct StatusChip: View {
    let state: PreviewExtensionStatus.State

    var body: some View {
        let (label, color): (String, Color) = switch state {
        case .enabled: ("オン", .green)
        case .disabled: ("オフ", .orange)
        case .unknown: ("確認中", .secondary)
        case .notRegistered: ("未登録", .orange)
        }
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .overlay(Capsule().stroke(color.opacity(0.6)))
    }
}

/// クイックルック拡張がオンかどうかを pluginkit で確かめる
@MainActor
@Observable
final class PreviewExtensionStatus {
    enum State { case unknown, enabled, disabled, notRegistered }

    nonisolated static let extensionID = "com.kajisho5.nozoki.preview"

    var state: State = .unknown
    var note: String?

    func refresh() {
        Task.detached {
            let out = Self.run("/usr/bin/pluginkit", ["-m", "-A", "-i", Self.extensionID])
            let line = out.split(separator: "\n").first { $0.contains(Self.extensionID) }.map(String.init)
            let newState: State
            if let line {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                newState = trimmed.hasPrefix("-") ? .disabled : .enabled
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
                self.note = "Finderでzipを選んでスペースキーを押して確かめてください。変わらなければ「設定を開く」から手動でオンにしてください。"
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

/// 設定画面（メニュー「nozoki → 設定…」）
struct SettingsView: View {
    @State private var preview = PreviewExtensionStatus()

    var body: some View {
        Form {
            PreviewSetupSection(status: preview)
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear { preview.refresh() }
    }
}
