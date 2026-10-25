import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// zip などをダブルクリックしたときに開くアプリ（既定のアプリ）を ZipPeek にする係。
/// macOS 26.4 以降は、切り替えるときに Mac が確認の画面を出す。
@MainActor
@Observable
final class DefaultAppStatus {
    enum State { case unknown, isZipPeek, other(String) }

    /// ダブルクリックで ZipPeek を開く形式（zip・7z・rar）
    static let types: [UTType] = [
        .zip,
        UTType("org.7-zip.7-zip-archive"),
        UTType("com.rarlab.rar-archive"),
    ].compactMap { $0 }

    static let archiveUtility = URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Archive Utility.app")

    var state: State = .unknown
    var working = false
    var note: String?

    var isZipPeek: Bool { if case .isZipPeek = state { return true } else { return false } }

    /// zip を開くアプリが今どれか
    func refresh() {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: .zip) else {
            state = .other("—")
            return
        }
        if Bundle(url: url)?.bundleIdentifier == Bundle.main.bundleIdentifier {
            state = .isZipPeek
        } else {
            state = .other(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
        }
    }

    /// zip・7z・rar を ZipPeek で開くようにする
    func useZipPeek() {
        apply(app: Bundle.main.bundleURL, types: Self.types)
    }

    /// zip を Mac 標準（アーカイブユーティリティ）に戻す
    func restoreSystemDefault() {
        apply(app: Self.archiveUtility, types: [.zip])
    }

    private func apply(app: URL, types: [UTType]) {
        working = true
        note = nil
        Task {
            var failed = false
            for type in types {
                do {
                    try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
                } catch {
                    // Mac の確認で「やめる」を選んだときもここに来る
                    failed = true
                }
            }
            working = false
            refresh()
            if failed && !isZipPeek && app == Bundle.main.bundleURL {
                note = String(localized: "Couldn’t change it. In Finder, select a ZIP, choose File → Get Info, pick ZipPeek under “Open with”, then click “Change All…”.")
            }
        }
    }
}

/// 「ダブルクリックで中身を見る」の案内（最初の窓と設定で使う）
struct DefaultAppSection: View {
    @Bindable var status: DefaultAppStatus
    var showRestore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Double-click a ZIP to look inside")).font(.headline)
                Spacer()
                DefaultAppChip(status: status)
            }
            Text(String(localized: "Open ZIP, 7z and rar files in ZipPeek when you double-click them. If your Mac asks to confirm, allow it."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if status.isZipPeek {
                    Label(String(localized: "Double-clicking opens ZipPeek"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button(String(localized: "Open with ZipPeek")) { status.useZipPeek() }
                        .buttonStyle(.borderedProminent)
                        .disabled(status.working)
                }
                if status.working { ProgressView().controlSize(.small) }
                Spacer()
                if showRestore && status.isZipPeek {
                    Button(String(localized: "Restore Archive Utility")) { status.restoreSystemDefault() }
                        .buttonStyle(.borderless)
                        .disabled(status.working)
                }
            }
            if let note = status.note {
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { status.refresh() }
    }
}

private struct DefaultAppChip: View {
    let status: DefaultAppStatus

    var body: some View {
        let (label, color): (String, Color) = switch status.state {
        case .isZipPeek: (String(localized: "On"), .green)
        case .other: (String(localized: "Off"), .orange)
        case .unknown: (String(localized: "Checking"), .secondary)
        }
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 2)
            .foregroundStyle(color)
            .overlay(Capsule().stroke(color.opacity(0.6)))
            .help(statusHelp)
    }

    private var statusHelp: String {
        if case .other(let name) = status.state { return String(localized: "Now: \(name)") }
        return ""
    }
}
