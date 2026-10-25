import AppKit
import SwiftUI
import ZipPeekCore

/// 標準のドラッグ先の窓（A4）。はじめて起動したときは、スペースキー機能の案内も出す
struct DropWindowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false
    @State private var showSetup = !Preferences.shared.hasSeenWelcome
    @State private var preview = PreviewExtensionStatus()
    @State private var defaultApp = DefaultAppStatus()

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64).accessibilityHidden(true)
            Text(verbatim: "ZipPeek").font(.title2.bold())

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc").font(.system(size: 26, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                Text(String(localized: "Drop files here")).font(.headline)
                HStack(spacing: 18) {
                    Label(String(localized: "Files & folders → compress"), systemImage: "archivebox")
                    Label(String(localized: "Archives → extract"), systemImage: "arrow.down.to.line")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background {
                // 重なったときは色だけでなく、線の太さと塗りでも示す
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isTargeted ? Color.accentColor.opacity(0.10) : Color.clear)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                                  style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: isTargeted ? [] : [7, 5]))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Drop target. Drop files or folders to compress, or archives to extract"))
            .dropDestination(for: URL.self) { urls, _ in
                DropRouter.handle(urls)
                return !urls.isEmpty
            } isTargeted: { isTargeted = $0 }

            HStack {
                Button(String(localized: "Choose…")) { WindowManager.shared.showOpenPanel() }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                Button(String(localized: "Look Inside…")) { WindowManager.shared.showBrowsePanel() }
                    .buttonBorderShape(.capsule)
                Spacer()
            }

            if showSetup {
                Divider()
                DefaultAppSection(status: defaultApp)
                Divider()
                PreviewSetupSection(status: preview)
                Button(String(localized: "Later")) {
                    Preferences.shared.hasSeenWelcome = true
                    withAnimation(reduceMotion ? nil : .default) { showSetup = false }
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 34)
        .padding(.bottom, 22)
        .frame(width: 420)
        .onAppear { preview.refresh() }
        // オンになったら、次からは案内を出さない
        .onChange(of: preview.state) { _, state in
            if state == .enabled { Preferences.shared.hasSeenWelcome = true }
        }
    }
}

/// 小窓モード（A5）。丸いガラスの小窓1つで、待機・作業中・完了を表示する
struct CompactDropView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false
    private var queue: JobQueue { JobQueue.shared }

    var body: some View {
        let active = queue.activeJob
        ZStack {
            if let active {
                VStack(spacing: 10) {
                    ZStack {
                        ProgressRing(progress: active.progress, lineWidth: 9).frame(width: 96, height: 96)
                        Text(verbatim: "\(Int((active.progress * 100).rounded()))%").font(.title2.bold()).monospacedDigit()
                    }
                    Text(active.inputs.first?.lastPathComponent ?? "").font(.caption).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                .contextMenu { Button(String(localized: "Stop")) { queue.cancel(active.id) } }
                .accessibilityAction(named: String(localized: "Stop")) { queue.cancel(active.id) }
            } else if let done = queue.lastFinished, done.state == .done, !isTargeted {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Color.accentColor)
                        .accessibilityLabel(String(localized: "Done"))
                    Button(String(localized: "Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting(done.results)
                        queue.clearFinished()
                    }
                    .buttonStyle(.borderless).font(.caption)
                }
            } else if let failed = queue.lastFinished, case .failed(let message) = failed.state {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.orange)
                        .accessibilityLabel(String(localized: "Failed"))
                    Text(message).font(.caption2).multilineTextAlignment(.center).lineLimit(3)
                    Button(String(localized: "Dismiss")) { queue.clearFinished() }.buttonStyle(.borderless).font(.caption)
                }
                .padding(.horizontal, 14)
            } else {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                        .scaleEffect(isTargeted && !reduceMotion ? 1.08 : 1).animation(reduceMotion ? nil : .snappy, value: isTargeted)
                        .accessibilityHidden(true)
                    Text(String(localized: "Drop here")).font(.callout.weight(.semibold))
                    Text(String(localized: "Compress · Extract")).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 200, height: 200)
        .zpGlass(in: RoundedRectangle(cornerRadius: 56, style: .continuous), interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 56, style: .continuous))
        .dropDestination(for: URL.self) { urls, _ in
            DropRouter.handle(urls)
            return !urls.isEmpty
        } isTargeted: { isTargeted = $0 }
        // 重なったときは拡大に加えて、縁取りでも示す（視差効果を減らす設定でも分かるように）
        .overlay {
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 3)
                .opacity(isTargeted ? 1 : 0)
        }
        .contextMenu {
            Button(String(localized: "Choose…")) { WindowManager.shared.showOpenPanel() }
            Button(String(localized: "Look Inside…")) { WindowManager.shared.showBrowsePanel() }
            SettingsLink { Text(String(localized: "Settings…")) }
            Divider()
            Button(String(localized: "Close")) { WindowManager.shared.closeCompactWindow() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "ZipPeek drop target"))
        .accessibilityAction(named: String(localized: "Choose…")) { WindowManager.shared.showOpenPanel() }
        .accessibilityAction(named: String(localized: "Look Inside…")) { WindowManager.shared.showBrowsePanel() }
        .padding(8)
    }
}

/// 標準の作業中の窓（A4）。1作業1行のガラスの粒
struct JobsView: View {
    private var queue: JobQueue { JobQueue.shared }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(queue.jobs) { job in
                JobRow(job: job)
            }
            if queue.jobs.isEmpty {
                Text(String(localized: "Nothing in progress")).foregroundStyle(.secondary).padding()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 34)
        .padding(.bottom, 16)
        .frame(width: 440)
    }
}

private struct JobRow: View {
    let job: JobQueue.Job

    var body: some View {
        GlassCapsule {
            Group {
                switch job.state {
                case .running, .waiting:
                    ProgressRing(progress: job.progress).frame(width: 22, height: 22)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).font(.title3)
                        .accessibilityLabel(String(localized: "Done"))
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
                        .accessibilityLabel(String(localized: "Failed"))
                case .cancelled:
                    Image(systemName: "xmark.circle").foregroundStyle(.secondary).font(.title3)
                        .accessibilityLabel(String(localized: "Stopped"))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(job.title).lineLimit(1).truncationMode(.middle)
                Group {
                    switch job.state {
                    case .running: Text(verbatim: "\(Int((job.progress * 100).rounded()))%")
                    case .waiting: Text(String(localized: "Starts after the current task"))
                    case .done: EmptyView()
                    case .failed(let m): Text(m).lineLimit(2)
                    case .cancelled: Text(String(localized: "Stopped"))
                    }
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            if job.isActive {
                CancelButton(help: String(localized: "Stop")) { JobQueue.shared.cancel(job.id) }
            } else if job.state == .done {
                Button(String(localized: "Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting(job.results)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
