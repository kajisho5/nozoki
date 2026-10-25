import AppKit
import Observation
import ZipPeekCore

/// 圧縮・解凍の作業を順番に処理する（同時には1つずつ）
@MainActor
@Observable
final class JobQueue {
    static let shared = JobQueue()

    enum Kind { case compress, extract }

    enum State: Equatable {
        case waiting
        case running
        case done
        case failed(String)
        case cancelled
    }

    struct Job: Identifiable {
        let id = UUID()
        let kind: Kind
        let inputs: [URL]
        let destination: URL?
        let options: CompressOptions?
        var state: State = .waiting
        var progress: Double = 0
        var results: [URL] = []
        let cancel = CancelFlag()
        let startedAt = Date()

        var title: String {
            let name = inputs.count == 1 ? inputs[0].lastPathComponent : String(localized: "\(inputs.count) items")
            switch (kind, state) {
            case (.compress, .done): return String(localized: "Created \(results.first?.lastPathComponent ?? name)")
            case (.extract, .done): return String(localized: "Extracted \(name)")
            case (.compress, .waiting): return String(localized: "Waiting to compress \(name)")
            case (.extract, .waiting): return String(localized: "Waiting to extract \(name)")
            case (.compress, _): return String(localized: "Compressing \(name)")
            case (.extract, _): return String(localized: "Extracting \(name)")
            }
        }

        var isActive: Bool { state == .waiting || state == .running }
    }

    var jobs: [Job] = []
    private var isRunning = false

    var activeJob: Job? { jobs.first { $0.state == .running } ?? jobs.first { $0.state == .waiting } }
    var hasActiveJobs: Bool { jobs.contains { $0.isActive } }
    var lastFinished: Job? { jobs.last { !$0.isActive } }

    private var engine: ArchiveOperations { ArchiveOperations(sevenZip: SevenZip.bundled()) }

    // MARK: 追加

    func enqueueExtract(_ archives: [URL]) {
        let prefs = Preferences.shared
        var dest: URL?
        if prefs.extractTo == .ask {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = String(localized: "Extract Here")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            dest = url
        }
        // 分割の2番目以降が一緒に渡されたら1つにまとめる
        var seen = Set<String>()
        for archive in archives.map(ArchiveKind.firstVolume(of:)) where seen.insert(archive.path).inserted {
            jobs.append(Job(kind: .extract, inputs: [archive], destination: dest, options: nil))
        }
        WindowManager.shared.showProgress()
        runNext()
    }

    func enqueueCompress(_ inputs: [URL], options: CompressOptions) {
        guard !inputs.isEmpty else { return }
        jobs.append(Job(kind: .compress, inputs: inputs, destination: nil, options: options))
        WindowManager.shared.showProgress()
        runNext()
    }

    func cancel(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].cancel.cancel()
        if jobs[i].state == .waiting { jobs[i].state = .cancelled }
    }

    func clearFinished() {
        jobs.removeAll { !$0.isActive }
    }

    // MARK: 実行

    private func runNext() {
        guard !isRunning, let index = jobs.firstIndex(where: { $0.state == .waiting }) else { return }
        isRunning = true
        jobs[index].state = .running
        let job = jobs[index]
        Task { await run(job) }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
    }

    private func run(_ job: Job) async {
        let id = job.id
        let cancel = job.cancel
        let engine = self.engine
        let progress: @Sendable (Double) -> Void = { p in
            Task { @MainActor in JobQueue.shared.update(id) { $0.progress = max($0.progress, p) } }
        }
        let group = Preferences.shared.groupIntoFolder
        var password: String?
        var wrong = false
        while true {
            do {
                let pw = password
                let results: [URL] = try await Task.detached(priority: .userInitiated) {
                    switch job.kind {
                    case .extract:
                        let archive = job.inputs[0]
                        let folder = job.destination ?? archive.deletingLastPathComponent()
                        return try engine.extractAll(archive, into: folder, password: pw,
                                                     groupIntoFolder: group,
                                                     onProgress: progress, isCancelled: { cancel.isCancelled })
                    case .compress:
                        return try engine.compress(job.inputs, options: job.options ?? CompressOptions(),
                                                   onProgress: progress, isCancelled: { cancel.isCancelled })
                    }
                }.value
                update(id) { $0.state = .done; $0.progress = 1; $0.results = results }
                finish(job, results: results)
                break
            } catch SevenZipError.needsPassword, SevenZipError.wrongPassword {
                // パスワードを聞いてやり直す
                if case .some = password { wrong = true }
                guard let pw = await WindowManager.shared.askPassword(for: job.inputs[0].lastPathComponent, wasWrong: wrong) else {
                    update(id) { $0.state = .cancelled }
                    break
                }
                password = pw
                continue
            } catch SevenZipError.cancelled {
                update(id) { $0.state = .cancelled }
                break
            } catch {
                update(id) { $0.state = .failed(error.localizedDescription) }
                break
            }
        }
        isRunning = false
        WindowManager.shared.progressChanged()
        runNext()
    }

    private func finish(_ job: Job, results: [URL]) {
        let prefs = Preferences.shared
        if job.kind == .extract, prefs.trashAfterExtract {
            for url in job.inputs { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        }
        if prefs.revealWhenDone, !results.isEmpty, !hasActiveJobs {
            NSWorkspace.shared.activateFileViewerSelecting(results)
        }
    }
}
