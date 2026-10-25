import AppKit
import SwiftUI
import ZipPeekCore

/// 標準のドラッグ先の窓（A4）。はじめて起動したときは、スペースキー機能の案内も出す
struct DropWindowView: View {
    @State private var isTargeted = false
    @State private var showSetup = !Preferences.shared.hasSeenWelcome
    @State private var preview = PreviewExtensionStatus()

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64).accessibilityHidden(true)
            Text("ZipPeek").font(.title2.bold())

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc").font(.system(size: 26, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                Text(tr("ここにドラッグ", "Drop files here")).font(.headline)
                HStack(spacing: 18) {
                    Label(tr("ファイル・フォルダ → 圧縮", "Files & folders → compress"), systemImage: "archivebox")
                    Label(tr("圧縮ファイル → 解凍", "Archives → extract"), systemImage: "shippingbox.and.arrow.backward")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
            .dropDestination(for: URL.self) { urls, _ in
                DropRouter.handle(urls)
                return !urls.isEmpty
            } isTargeted: { isTargeted = $0 }

            HStack {
                Button(tr("選ぶ…", "Choose…")) { WindowManager.shared.showOpenPanel() }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                Button(tr("中身を見る…", "Look Inside…")) { WindowManager.shared.showBrowsePanel() }
                    .buttonBorderShape(.capsule)
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help(tr("設定", "Settings"))
            }

            if showSetup {
                Divider()
                PreviewSetupSection(status: preview)
                Button(tr("あとで", "Later")) {
                    Preferences.shared.hasSeenWelcome = true
                    withAnimation { showSetup = false }
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
    }
}

/// 小窓モード（A5）。丸いガラスの小窓1つで、待機・作業中・完了を表示する
struct CompactDropView: View {
    @State private var isTargeted = false
    private var queue: JobQueue { JobQueue.shared }

    var body: some View {
        let active = queue.activeJob
        ZStack {
            if let active {
                VStack(spacing: 10) {
                    ZStack {
                        ProgressRing(progress: active.progress, lineWidth: 9).frame(width: 96, height: 96)
                        Text("\(Int((active.progress * 100).rounded()))%").font(.title2.bold()).monospacedDigit()
                    }
                    Text(active.inputs.first?.lastPathComponent ?? "").font(.caption).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                .contextMenu { Button(tr("中止", "Cancel")) { queue.cancel(active.id) } }
            } else if let done = queue.lastFinished, done.state == .done, !isTargeted {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Color.accentColor)
                    Button(tr("Finderで表示", "Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting(done.results)
                        queue.clearFinished()
                    }
                    .buttonStyle(.borderless).font(.caption)
                }
            } else if let failed = queue.lastFinished, case .failed(let message) = failed.state {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.orange)
                    Text(message).font(.caption2).multilineTextAlignment(.center).lineLimit(3)
                    Button(tr("閉じる", "Dismiss")) { queue.clearFinished() }.buttonStyle(.borderless).font(.caption)
                }
                .padding(.horizontal, 14)
            } else {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                        .scaleEffect(isTargeted ? 1.08 : 1).animation(.snappy, value: isTargeted)
                    Text(tr("ここにドラッグ", "Drop here")).font(.callout.weight(.semibold))
                    Text(tr("圧縮・解凍", "Compress · Extract")).font(.caption2).foregroundStyle(.secondary)
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
        .contextMenu {
            Button(tr("選ぶ…", "Choose…")) { WindowManager.shared.showOpenPanel() }
            Button(tr("中身を見る…", "Look Inside…")) { WindowManager.shared.showBrowsePanel() }
            SettingsLink { Text(tr("設定…", "Settings…")) }
            Divider()
            Button(tr("小窓を閉じる", "Close")) { WindowManager.shared.closeCompactWindow() }
        }
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
                Text(tr("作業はありません", "Nothing in progress")).foregroundStyle(.secondary).padding()
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
            switch job.state {
            case .running, .waiting:
                ProgressRing(progress: job.progress).frame(width: 22, height: 22)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).font(.title3)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
            case .cancelled:
                Image(systemName: "xmark.circle").foregroundStyle(.secondary).font(.title3)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(job.title).lineLimit(1).truncationMode(.middle)
                Group {
                    switch job.state {
                    case .running: Text("\(Int((job.progress * 100).rounded()))%")
                    case .waiting: Text(tr("前の作業が終わると始まります", "Starts after the current task"))
                    case .done: Text(tr("Finderで表示", "Show in Finder")).foregroundStyle(Color.accentColor)
                    case .failed(let m): Text(m).lineLimit(2)
                    case .cancelled: Text(tr("中止しました", "Cancelled"))
                    }
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 4)
            if job.isActive {
                Button { JobQueue.shared.cancel(job.id) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(tr("中止", "Cancel"))
            }
        }
        .onTapGesture {
            if job.state == .done { NSWorkspace.shared.activateFileViewerSelecting(job.results) }
        }
    }
}
