import AppKit
import Foundation
import Observation
import ZipPeekCore

/// 中身を見る窓1つ分の状態
@MainActor
@Observable
final class ArchiveModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    struct Extraction {
        var progress: Double = 0
        var totalBytes: UInt64
        var fileTotal: Int
        var currentName: String
        var destinationLabel: String
        let startedAt = Date()
        let cancel = CancelFlag()
        /// プレビュー用の取り出し（終わったら自動でプレビューを開く）
        let isForPreview: Bool

        var remainingSeconds: Double? {
            let elapsed = Date().timeIntervalSince(startedAt)
            guard elapsed > 1.5, progress > 0.01, progress < 1 else { return nil }
            return elapsed / progress * (1 - progress)
        }
    }

    let url: URL
    var state: LoadState = .loading
    var listing: ArchiveListing?
    var loadSeconds: Double = 0

    var folderPath: String? = ""
    var selection = Set<ArchiveItem.ID>()
    var search = ""
    var sortOrder: [KeyPathComparator<ArchiveItem>] = [KeyPathComparator(\ArchiveItem.name, comparator: .localizedStandard)]
    /// ファイル名の文字コード（zipのみ）。nil は自動
    var encodingChoice: NameEncoding?

    var extraction: Extraction?
    var errorMessage: String?
    var previewURL: URL?

    /// この窓で入力されたパスワード（窓を閉じたら消える。保存しない）
    private var password: String?
    private var tempFolders: [URL] = []

    init(url: URL) {
        self.url = url
    }

    private var engine: ArchiveOperations { ArchiveOperations(sevenZip: SevenZip.bundled()) }

    // MARK: 読み込み

    func load() {
        state = .loading
        let url = self.url
        let choice = encodingChoice
        let pw = password
        let sevenZip = SevenZip.bundled()
        Task {
            let start = Date()
            let result: Result<ArchiveListing, Error> = await Task.detached(priority: .userInitiated) {
                // zipはまず自前で目次を読む（30GBでも一瞬）。だめなら7-Zipに一覧を頼む
                if ArchiveKind.isZip(url), let listing = try? ArchiveListing.load(url: url, encoding: choice) {
                    return .success(listing)
                }
                guard let sevenZip else { return .failure(SevenZipError.notFound) }
                do {
                    return .success(ArchiveListing.build(raw: try sevenZip.list(url, password: pw)))
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case .success(let listing):
                self.listing = listing
                self.loadSeconds = Date().timeIntervalSince(start)
                self.state = .loaded
                if let path = self.folderPath, !path.isEmpty, listing.items(in: path).isEmpty { self.folderPath = "" }
            case .failure(let error):
                if let e = error as? SevenZipError, e == .needsPassword || e == .wrongPassword {
                    // 名前まで隠された7zなど：パスワードを聞いてから一覧を出す
                    if let pw = await WindowManager.shared.askPassword(for: url.lastPathComponent, wasWrong: e == .wrongPassword) {
                        self.password = pw
                        self.load()
                    } else {
                        self.state = .failed(e.localizedDescription)
                    }
                } else {
                    self.state = .failed(error.localizedDescription)
                }
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

    var visibleItems: [ArchiveItem] {
        guard let listing else { return [] }
        let base = isSearching ? listing.search(search) : listing.items(in: currentFolder)
        let sorted = base.sorted(using: sortOrder)
        return sorted.filter(\.isFolder) + sorted.filter { !$0.isFolder }
    }

    var selectedItems: [ArchiveItem] { visibleItems.filter { selection.contains($0.id) } }

    var selectedSize: UInt64 {
        guard let listing else { return 0 }
        return listing.files(for: selectedItems).reduce(0) { $0 + $1.item.size }
    }

    var folderTitle: String {
        if isSearching { return String(localized: "Results for “\(search)”") }
        let path = currentFolder
        return path.isEmpty ? String(localized: "All") : String(path.split(separator: "/").last ?? "")
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

    func extractSelection() {
        let items = selectedItems.isEmpty ? visibleItems : selectedItems
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Save Here")
        panel.message = items.count == 1
            ? String(localized: "Choose where to save “\(items[0].name)”")
            : String(localized: "Choose where to save \(items.count) items")
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
        guard !files.isEmpty else { return }
        let total = files.reduce(UInt64(0)) { $0 + $1.item.size }
        if let free = Self.freeSpace(at: destination), UInt64(max(free, 0)) < total {
            errorMessage = String(localized: "Not enough free space (needs \(ByteFormat.string(total)), available \(ByteFormat.string(UInt64(max(free, 0))))).")
            return
        }
        let state = Extraction(totalBytes: total, fileTotal: files.count,
                               currentName: files.count == 1 ? files[0].item.name : String(localized: "\(files.count) items"),
                               destinationLabel: Self.displayPath(destination), isForPreview: forPreview)
        extraction = state
        let cancel = state.cancel
        let zipURL = url
        let engine = self.engine
        // 暗号のない普通のzipは自前で（日本語Windowsの名前を正しく扱える）。それ以外は7-Zip
        let native = listing.source == .zip && !files.contains { $0.item.isEncrypted }
        let progress: @Sendable (Double) -> Void = { p in
            Task { @MainActor in self.extraction?.progress = max(self.extraction?.progress ?? 0, p) }
        }

        Task {
            var pw = self.password
            var wrong = false
            while true {
                do {
                    let passwordNow = pw
                    let written: [URL] = try await Task.detached(priority: .userInitiated) {
                        if native {
                            let jobs = files.compactMap { f -> Extractor.Job? in
                                guard let index = f.item.entryIndex else { return nil }
                                return Extractor.Job(entryIndex: index, name: f.item.name, size: f.item.size,
                                                     isEncrypted: false, relativePath: f.relativePath)
                            }
                            return try Extractor(zipURL: zipURL).extract(jobs, into: destination, onProgress: { p in
                                if p.totalBytes > 0 { progress(Double(p.doneBytes) / Double(p.totalBytes)) }
                            }, isCancelled: { cancel.isCancelled })
                        }
                        return try engine.extractSelected(zipURL, files: files, into: destination, password: passwordNow,
                                                          onProgress: progress, isCancelled: { cancel.isCancelled })
                    }.value
                    self.password = pw
                    self.extraction = nil
                    if forPreview {
                        self.previewURL = written.first
                    } else if !written.isEmpty {
                        NSWorkspace.shared.activateFileViewerSelecting(written)
                    }
                    break
                } catch SevenZipError.needsPassword, SevenZipError.wrongPassword {
                    if pw != nil { wrong = true }
                    guard let entered = await WindowManager.shared.askPassword(for: zipURL.lastPathComponent, wasWrong: wrong) else {
                        self.extraction = nil
                        break
                    }
                    pw = entered
                    continue
                } catch {
                    let cancelled = (error as? ExtractError) == .cancelled || (error as? SevenZipError) == .cancelled
                    self.extraction = nil
                    self.errorMessage = cancelled ? nil : error.localizedDescription
                    break
                }
            }
        }
    }

    func cancelExtraction() { extraction?.cancel.cancel() }

    func close() {
        extraction?.cancel.cancel()
        password = nil
        for folder in tempFolders { try? FileManager.default.removeItem(at: folder) }
        tempFolders.removeAll()
    }

    // MARK: ドラッグで書き出し

    /// Finderへドラッグしたときに渡すもの。落とされた時点でそのファイルだけ取り出す
    func itemProvider(for item: ArchiveItem) -> NSItemProvider? {
        guard !item.isFolder, let listing else { return nil }
        // パスワードが要るものは、パスワードを聞ける「取り出す」ボタンから
        if item.isEncrypted && password == nil { return nil }
        let provider = NSItemProvider()
        provider.suggestedName = item.name
        let type = FileIcon.contentType(for: item.fileExtension)
        let zipURL = url
        let files = listing.files(for: [item])
        let native = listing.source == .zip && !item.isEncrypted
        let pw = password
        let engine = self.engine
        let folder = TempFiles.newFolder()
        tempFolders.append(folder)
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            let progress = Progress(totalUnitCount: 100)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let written: [URL]
                    if native, let index = item.entryIndex {
                        let job = Extractor.Job(entryIndex: index, name: item.name, size: item.size, isEncrypted: false, relativePath: item.name)
                        written = try Extractor(zipURL: zipURL).extract([job], into: folder, onProgress: { p in
                            if p.totalBytes > 0 { progress.completedUnitCount = Int64(Double(p.doneBytes) / Double(p.totalBytes) * 100) }
                        }, isCancelled: { progress.isCancelled })
                    } else {
                        written = try engine.extractSelected(zipURL, files: files, into: folder, password: pw,
                                                             onProgress: { progress.completedUnitCount = Int64($0 * 100) },
                                                             isCancelled: { progress.isCancelled })
                    }
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
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
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
