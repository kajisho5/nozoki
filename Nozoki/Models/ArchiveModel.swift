import AppKit
import Foundation
import NozokiCore
import Observation

/// zip1つ分の画面の状態
@MainActor
@Observable
final class ArchiveModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    struct Extraction {
        var doneBytes: UInt64 = 0
        var totalBytes: UInt64
        var fileNumber: Int = 0
        var fileTotal: Int
        var currentName: String = ""
        var destinationLabel: String
        let startedAt = Date()
        let cancel = CancelFlag()
        /// プレビュー用の取り出し（終わったら自動でプレビューを開く）
        let isForPreview: Bool

        var fraction: Double { totalBytes == 0 ? 0 : min(1, Double(doneBytes) / Double(totalBytes)) }

        /// 残り時間（秒）。始まってすぐは出さない
        var remainingSeconds: Double? {
            let elapsed = Date().timeIntervalSince(startedAt)
            guard elapsed > 1.5, doneBytes > 0, totalBytes > doneBytes else { return nil }
            return elapsed / Double(doneBytes) * Double(totalBytes - doneBytes)
        }
    }

    let url: URL
    var state: LoadState = .loading
    var listing: ArchiveListing?
    var loadSeconds: Double = 0

    /// サイドバーで選んでいるフォルダ（"" は最上位）
    var folderPath: String? = ""
    var selection = Set<ArchiveItem.ID>()
    var search = ""
    var sortOrder: [KeyPathComparator<ArchiveItem>] = [KeyPathComparator(\ArchiveItem.name, comparator: .localizedStandard)]
    /// ファイル名の文字コード。nil は自動
    var encodingChoice: NameEncoding?

    var extraction: Extraction?
    var errorMessage: String?
    var previewURL: URL?

    private var tempFolders: [URL] = []

    init(url: URL) {
        self.url = url
    }

    // MARK: 読み込み

    func load() {
        state = .loading
        let url = self.url
        let choice = encodingChoice
        Task.detached(priority: .userInitiated) {
            let start = Date()
            do {
                let listing = try ArchiveListing.load(url: url, encoding: choice)
                let seconds = Date().timeIntervalSince(start)
                await MainActor.run {
                    self.listing = listing
                    self.loadSeconds = seconds
                    self.state = .loaded
                    if let path = self.folderPath, !path.isEmpty, listing.items(in: path).isEmpty {
                        self.folderPath = ""
                    }
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { self.state = .failed(message) }
            }
        }
    }

    func setEncoding(_ choice: NameEncoding?) {
        guard choice != encodingChoice else { return }
        encodingChoice = choice
        selection.removeAll()
        folderPath = ""
        load()
    }

    // MARK: 一覧

    var currentFolder: String { folderPath ?? "" }

    var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    /// 今の一覧（フォルダが先、あとは並べ替えの指定どおり）
    var visibleItems: [ArchiveItem] {
        guard let listing else { return [] }
        let base = isSearching ? listing.search(search) : listing.items(in: currentFolder)
        let sorted = base.sorted(using: sortOrder)
        return sorted.filter(\.isFolder) + sorted.filter { !$0.isFolder }
    }

    var selectedItems: [ArchiveItem] {
        visibleItems.filter { selection.contains($0.id) }
    }

    var selectedSize: UInt64 {
        guard let listing else { return 0 }
        return listing.files(for: selectedItems).reduce(0) { $0 + $1.item.size }
    }

    var folderTitle: String {
        if isSearching { return "「\(search)」の検索結果" }
        let path = currentFolder
        return path.isEmpty ? "すべて" : String(path.split(separator: "/").last ?? "")
    }

    func open(_ item: ArchiveItem) {
        if item.isFolder {
            search = ""
            folderPath = item.path
            selection.removeAll()
        } else {
            preview(item)
        }
    }

    func goUp() {
        let path = currentFolder
        guard !path.isEmpty else { return }
        folderPath = path.contains("/") ? String(path[..<path.lastIndex(of: "/")!]) : ""
        selection.removeAll()
    }

    // MARK: 取り出し

    /// 保存先を選んで、選択中のものを取り出す
    func extractSelection() {
        let items = selectedItems.isEmpty ? visibleItems : selectedItems
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "ここに取り出す"
        panel.message = items.count == 1 ? "「\(items[0].name)」の保存先を選んでください" : "\(items.count) 件の保存先を選んでください"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        startExtraction(items, to: dest, forPreview: false)
    }

    func preview(_ item: ArchiveItem) {
        guard !item.isFolder else { return }
        let folder = TempFiles.newFolder()
        tempFolders.append(folder)
        startExtraction([item], to: folder, forPreview: true)
    }

    func startExtraction(_ items: [ArchiveItem], to destination: URL, forPreview: Bool) {
        guard let listing, extraction == nil else { return }
        let files = listing.files(for: items)
        if let locked = files.first(where: { $0.item.isEncrypted }) {
            errorMessage = ExtractError.encrypted(locked.item.name).localizedDescription
            return
        }
        let jobs = files.compactMap { f -> Extractor.Job? in
            guard let index = f.item.entryIndex else { return nil }
            return Extractor.Job(entryIndex: index, name: f.item.name, size: f.item.size,
                                 isEncrypted: f.item.isEncrypted, relativePath: f.relativePath)
        }
        guard !jobs.isEmpty else { return }
        let total = jobs.reduce(UInt64(0)) { $0 + $1.size }
        if let free = Self.freeSpace(at: destination), UInt64(max(free, 0)) < total {
            errorMessage = "保存先の空きが足りません（必要 \(ByteFormat.string(total))、空き \(ByteFormat.string(UInt64(max(free, 0))))）。"
            return
        }

        let state = Extraction(totalBytes: total, fileTotal: jobs.count,
                               destinationLabel: Self.displayPath(destination), isForPreview: forPreview)
        extraction = state
        let cancel = state.cancel
        let zipURL = url

        Task.detached(priority: .userInitiated) {
            do {
                let written = try Extractor(zipURL: zipURL).extract(jobs, into: destination, onProgress: { p in
                    Task { @MainActor in
                        self.extraction?.doneBytes = p.doneBytes
                        self.extraction?.fileNumber = p.fileNumber
                        if !p.currentName.isEmpty { self.extraction?.currentName = p.currentName }
                    }
                }, isCancelled: { cancel.isCancelled })
                await MainActor.run {
                    self.extraction = nil
                    if forPreview {
                        self.previewURL = written.first
                    } else if !written.isEmpty {
                        NSWorkspace.shared.activateFileViewerSelecting(written)
                    }
                }
            } catch {
                let message = (error as? ExtractError) == .cancelled ? nil : error.localizedDescription
                await MainActor.run {
                    self.extraction = nil
                    self.errorMessage = message
                }
            }
        }
    }

    /// 取り出し中の画面を出すか。小さいファイルのプレビューは一瞬で終わるので出さない
    var showsExtractionSheet: Bool {
        guard let e = extraction else { return false }
        return !e.isForPreview || e.totalBytes > 200_000_000
    }

    func cancelExtraction() {
        extraction?.cancel.cancel()
    }

    /// 窓を閉じたとき：取り出し中なら止め、一時ファイルを消す
    func close() {
        extraction?.cancel.cancel()
        for folder in tempFolders { try? FileManager.default.removeItem(at: folder) }
        tempFolders.removeAll()
    }

    // MARK: ドラッグで書き出し

    /// Finderへドラッグしたときに渡すもの。落とされた時点でそのファイルだけ取り出す
    func itemProvider(for item: ArchiveItem) -> NSItemProvider? {
        guard !item.isFolder, !item.isEncrypted, let index = item.entryIndex else { return nil }
        let provider = NSItemProvider()
        provider.suggestedName = item.name
        let type = FileIcon.contentType(for: item.fileExtension)
        let zipURL = url
        let job = Extractor.Job(entryIndex: index, name: item.name, size: item.size, isEncrypted: false, relativePath: item.name)
        let folder = TempFiles.newFolder()
        tempFolders.append(folder)
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            let progress = Progress(totalUnitCount: Int64(max(job.size, 1)))
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let written = try Extractor(zipURL: zipURL).extract([job], into: folder, onProgress: { p in
                        progress.completedUnitCount = Int64(p.doneBytes)
                    }, isCancelled: { progress.isCancelled })
                    completion(written.first, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return progress
        }
        return provider
    }

    // MARK: 補助

    nonisolated static func freeSpace(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    var desktopFreeSpace: Int64? {
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else { return nil }
        return Self.freeSpace(at: desktop)
    }

    static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) { return "ホーム" + path.dropFirst(home.count) }
        return path
    }
}

/// 別の作業列から「止めて」を伝えるための旗
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func cancel() {
        lock.lock(); value = true; lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

extension ArchiveItem {
    /// 並べ替え用（日付がないものは一番古い扱い）
    var sortDate: Date { modified ?? .distantPast }
}
