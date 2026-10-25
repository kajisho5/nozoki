import AppKit
import CryptoKit
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
        /// 何のための取り出しか
        let purpose: Purpose
        /// 一時的な取り出し（プレビュー・中の圧縮ファイル・既定のアプリで開く）。小さければ進み具合を出さない
        var isForPreview: Bool { purpose != .save }

        var remainingSeconds: Double? {
            let elapsed = Date().timeIntervalSince(startedAt)
            guard elapsed > 1.5, progress > 0.01, progress < 1 else { return nil }
            return elapsed / progress * (1 - progress)
        }
    }

    /// 取り出しの目的
    enum Purpose: Equatable { case save, preview, openNested, edit }

    let url: URL
    /// リンクのままのぞいている zip（url が https のとき）
    private(set) var remote: RemoteZip?
    var isRemote: Bool { url.scheme == "http" || url.scheme == "https" }
    /// 別の圧縮ファイルの中から開いた圧縮ファイル（一時フォルダにある）
    var isNested = false
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
    /// errorMessage の見出し（nil なら「取り出せませんでした」）
    var errorTitle: String?
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
        let isRemote = self.isRemote
        let loadedRemote = remote
        Task {
            let start = Date()
            let result: Result<ArchiveListing, Error> = await Task.detached(priority: .userInitiated) {
                if isRemote {
                    // リンクの先の zip：末尾と目次だけを取り寄せる
                    do {
                        let r = try loadedRemote ?? RemoteZip(url: url)
                        if loadedRemote == nil { try r.load() }
                        await MainActor.run { self.remote = r }
                        return .success(ArchiveListing.build(entries: r.entries, encoding: choice))
                    } catch {
                        return .failure(error)
                    }
                }
                // zipはまず自前で目次を読む（30GBでも一瞬）。だめなら7-Zipに一覧を頼む
                if ArchiveKind.isZip(url), let listing = try? ArchiveListing.load(url: url, encoding: choice) {
                    return .success(listing)
                }
                if LibArchive.handles(url) {
                    // 7-Zip が読めない zstd・lzip は OS の libarchive で
                    do { return .success(ArchiveListing.build(raw: try LibArchive.entries(url))) } catch { return .failure(error) }
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
        } else if ArchiveKind.isArchive(URL(fileURLWithPath: item.name)) {
            openNested(item)
        } else {
            preview(item)
        }
    }

    /// 中の圧縮ファイルを、その中身を見る窓で開く（一時フォルダに取り出してから）
    func openNested(_ item: ArchiveItem) {
        guard !item.isFolder else { return }
        let folder = TempFiles.newFolder()
        tempFolders.append(folder)
        startExtraction([item], to: folder, purpose: .openNested)
    }

    /// 既定のアプリで開く。保存されたら、圧縮ファイルに書き戻すか聞く
    func openInDefaultApp(_ item: ArchiveItem) {
        guard !item.isFolder else { return }
        let folder = TempFiles.newFolder()
        tempFolders.append(folder)
        startExtraction([item], to: folder, purpose: .edit, editedItem: item)
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
        startExtraction(items, to: dest, purpose: .save)
    }

    func preview(_ item: ArchiveItem) {
        guard !item.isFolder else { return }
        let folder = TempFiles.newFolder()
        tempFolders.append(folder)
        startExtraction([item], to: folder, purpose: .preview)
    }

    func startExtraction(_ items: [ArchiveItem], to destination: URL, purpose: Purpose, editedItem: ArchiveItem? = nil) {
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
                               destinationLabel: Self.displayPath(destination), purpose: purpose)
        extraction = state
        let cancel = state.cancel
        let zipURL = url
        let engine = self.engine
        // 暗号のない普通のzipは自前で（日本語Windowsの名前を正しく扱える）。それ以外は7-Zip
        let native = listing.source == .zip && !files.contains { $0.item.isEncrypted } && !isRemote
        let remote = self.remote
        let progress: @Sendable (Double) -> Void = { p in
            Task { @MainActor in
                // 読むのと書くのを同時にすると Swift の決まり（同時アクセスの禁止）で止まるので、分けて行う
                let current = self.extraction?.progress ?? 0
                self.extraction?.progress = max(current, p)
            }
        }

        Task {
            var pw = self.password
            var wrong = false
            while true {
                do {
                    let passwordNow = pw
                    let written: [URL] = try await Task.detached(priority: .userInitiated) {
                        if let remote {
                            // リンクの先から、選んだファイルの部分だけを取り寄せる
                            var out: [URL] = []
                            for (n, f) in files.enumerated() {
                                guard let index = f.item.entryIndex else { continue }
                                out.append(try remote.extract(remote.entries[index], as: f.relativePath, into: destination,
                                                              isCancelled: { cancel.isCancelled }))
                                progress(Double(n + 1) / Double(files.count))
                            }
                            return out
                        }
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
                    switch purpose {
                    case .preview: self.previewURL = written.first
                    case .save: if !written.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(written) }
                    case .openNested: if let inner = written.first { WindowManager.shared.open(inner, nested: true) }
                    case .edit:
                        if let file = written.first, let editedItem {
                            self.watch(file, for: editedItem)
                            NSWorkspace.shared.open(file)
                        }
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

    // MARK: 足す・消す（zip と 7z）

    /// 足したり消したりしている最中の表示（nil なら何もしていない）
    var editing: String?

    /// 変更できない理由（できるなら nil）
    var editBlocker: ArchiveEdit.Failure? {
        if isRemote { return .remoteLink }
        if isNested { return .nested }
        let encrypted = listing?.allFiles.contains(where: \.isEncrypted) ?? false
        return ArchiveEdit.check(url, encrypted: encrypted || password != nil)
    }

    var canDelete: Bool {
        editBlocker == nil && !(listing?.namesNeedConversion ?? false) && !selectedItems.isEmpty && editing == nil && extraction == nil
    }

    /// 外から落とされたファイルを、今見ているフォルダに足す（確認してから）
    func requestAdd(_ urls: [URL]) -> Bool {
        // この窓から取り出したもの（一時フォルダの中）を戻しただけなら何もしない
        let items = urls.filter { !$0.standardizedFileURL.path.hasPrefix(TempFiles.root.standardizedFileURL.path) }
        guard !items.isEmpty, editing == nil, extraction == nil else { return false }
        if let blocker = editBlocker {
            errorTitle = String(localized: "Couldn’t Add")
            errorMessage = blocker.localizedDescription
            return false
        }
        // ドラッグの受け取りを終えてから確認を出す
        DispatchQueue.main.async { self.confirmAdd(items) }
        return true
    }

    /// 「追加…」ボタン：ファイルを選んで足す
    func chooseAndAdd() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = String(localized: "Add")
        panel.message = String(localized: "Choose files or folders to add to “\(url.lastPathComponent)”")
        guard panel.runModal() == .OK else { return }
        _ = requestAdd(panel.urls)
    }

    private func confirmAdd(_ items: [URL]) {
        let folder = isSearching ? "" : currentFolder
        let place = folder.isEmpty ? url.lastPathComponent : "\(url.lastPathComponent)/\(folder)"
        let a = NSAlert()
        a.messageText = items.count == 1
            ? String(localized: "Add “\(items[0].lastPathComponent)” to “\(place)”?")
            : String(localized: "Add \(items.count) items to “\(place)”?")
        a.informativeText = String(localized: "The archive is changed directly. Your original files aren’t moved or changed.")
        a.addButton(withTitle: String(localized: "Add"))
        a.addButton(withTitle: String(localized: "Cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let archive = url
        runEdit(label: String(localized: "Adding…")) { sevenZip in
            try ArchiveEdit.add(items, to: archive, inFolder: folder, sevenZip: sevenZip)
        }
    }

    /// 選んだものを圧縮ファイルの中から消す（確認してから。元に戻せない）
    func requestDelete() {
        let items = selectedItems
        guard !items.isEmpty, editing == nil, extraction == nil else { return }
        if let blocker = editBlocker ?? ((listing?.namesNeedConversion ?? false) ? .legacyNames : nil) {
            errorTitle = String(localized: "Couldn’t Delete")
            errorMessage = blocker.localizedDescription
            return
        }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = items.count == 1
            ? String(localized: "Delete “\(items[0].name)” from “\(url.lastPathComponent)”?")
            : String(localized: "Delete \(items.count) items from “\(url.lastPathComponent)”?")
        a.informativeText = String(localized: "They’re removed from the archive itself. This can’t be undone.")
        // 取り消せない操作なので、return キーで押されるのは「キャンセル」
        a.addButton(withTitle: String(localized: "Cancel"))
        let del = a.addButton(withTitle: String(localized: "Delete"))
        del.hasDestructiveAction = true
        guard a.runModal() == .alertSecondButtonReturn else { return }
        let paths = items.map(\.path)
        let archive = url
        runEdit(label: String(localized: "Deleting…")) { sevenZip in
            try ArchiveEdit.delete(paths, from: archive, sevenZip: sevenZip)
        }
    }

    // MARK: 名前を変える

    var canRename: Bool {
        editBlocker == nil && !(listing?.namesNeedConversion ?? false) && selectedItems.count == 1 && editing == nil && extraction == nil
    }

    func requestRename(_ item: ArchiveItem? = nil) {
        guard let item = item ?? selectedItems.first, editing == nil, extraction == nil else { return }
        if let blocker = editBlocker ?? ((listing?.namesNeedConversion ?? false) ? .legacyNames : nil) {
            errorTitle = String(localized: "Couldn’t Rename")
            errorMessage = blocker.localizedDescription
            return
        }
        let a = NSAlert()
        a.messageText = String(localized: "Rename “\(item.name)”")
        a.informativeText = String(localized: "The name is changed inside the archive.")
        let field = NSTextField(string: item.name)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        field.setAccessibilityLabel(String(localized: "New name"))
        a.accessoryView = field
        a.addButton(withTitle: String(localized: "Rename"))
        a.addButton(withTitle: String(localized: "Cancel"))
        a.window.initialFirstResponder = field
        // 拡張子の手前までを選んでおく（Finder と同じ）
        DispatchQueue.main.async {
            let stem = (item.name as NSString).deletingPathExtension
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: item.isFolder ? item.name.utf16.count : stem.utf16.count)
        }
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue
        guard newName != item.name else { return }
        let archive = url
        let from = item.archivePath ?? item.path
        runEdit(label: String(localized: "Renaming…")) { sevenZip in
            try ArchiveEdit.rename(from, to: newName, in: archive, sevenZip: sevenZip)
        }
    }

    // MARK: 壊れていないか確かめる

    var verifying = false

    func verify() {
        guard !isRemote, !verifying, extraction == nil, editing == nil, let sevenZip = SevenZip.bundled() else { return }
        verifying = true
        editing = String(localized: "Checking…")
        let archive = url
        Task {
            var pw = self.password
            var wrong = false
            while true {
                let passwordNow = pw
                let outcome: Result<(ArchiveTest.Result, String), Error> = await Task.detached(priority: .userInitiated) {
                    do {
                        let r = try ArchiveTest.run(archive, password: passwordNow, sevenZip: sevenZip)
                        return .success((r, Self.sha256(of: archive) ?? ""))
                    } catch { return .failure(error) }
                }.value
                switch outcome {
                case .failure(let e as SevenZipError) where e == .needsPassword || e == .wrongPassword:
                    if pw != nil { wrong = true }
                    guard let entered = await WindowManager.shared.askPassword(for: archive.lastPathComponent, wasWrong: wrong) else {
                        editing = nil; verifying = false; return
                    }
                    pw = entered
                    continue
                case .failure(let e):
                    editing = nil; verifying = false
                    errorTitle = String(localized: "Couldn’t Check")
                    errorMessage = e.localizedDescription
                    return
                case .success(let (result, hash)):
                    editing = nil; verifying = false
                    self.password = pw ?? self.password
                    showVerifyResult(result, hash: hash)
                    return
                }
            }
        }
    }

    private func showVerifyResult(_ result: ArchiveTest.Result, hash: String) {
        let a = NSAlert()
        a.alertStyle = result.ok ? .informational : .critical
        a.messageText = result.ok ? String(localized: "No Problems Found") : String(localized: "This Archive Is Damaged")
        var info = result.ok
            ? String(localized: "Every file was read and its checksum matched. Nothing was written to disk.")
            : String(localized: "Some files can’t be read correctly. Ask the sender to send it again.") + "\n\n" + result.detail
        if !hash.isEmpty { info += "\n\nSHA-256\n" + hash }
        a.informativeText = info
        a.addButton(withTitle: "OK")
        if !hash.isEmpty { a.addButton(withTitle: String(localized: "Copy SHA-256")) }
        if a.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hash, forType: .string)
        }
    }

    /// ファイル全体の SHA-256（相手が公開している値と見比べるため）
    nonisolated static func sha256(of url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 既定のアプリで直したら書き戻す

    private struct Watched { let item: ArchiveItem; var modified: Date; var asking = false }
    private var watched: [URL: Watched] = [:]
    private var watchTimer: Timer?

    private func watch(_ file: URL, for item: ArchiveItem) {
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        watched[file] = Watched(item: item, modified: date)
        guard watchTimer == nil else { return }
        // 保存のしかたはアプリによって違う（上書き・置き換え）ので、変更日時を見張る
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkWatched() }
        }
    }

    private func checkWatched() {
        for (file, w) in watched where !w.asking {
            guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date > w.modified else { continue }
            watched[file]?.modified = date
            watched[file]?.asking = true
            askWriteBack(file, item: w.item)
        }
    }

    private func askWriteBack(_ file: URL, item: ArchiveItem) {
        defer { watched[file]?.asking = false }
        if let blocker = editBlocker {
            errorTitle = String(localized: "Changes Can’t Be Saved to the Archive")
            errorMessage = blocker.localizedDescription + "\n" + String(localized: "Your edited copy is here: \(Self.displayPath(file))")
            return
        }
        let a = NSAlert()
        a.messageText = String(localized: "Update “\(item.name)” in “\(url.lastPathComponent)”?")
        a.informativeText = String(localized: "You saved changes to this file. ZipPeek can put the new version back into the archive.")
        a.addButton(withTitle: String(localized: "Update"))
        a.addButton(withTitle: String(localized: "Not Now"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let archive = url
        let folder = item.parentPath
        runEdit(label: String(localized: "Updating…")) { sevenZip in
            try ArchiveEdit.add([file], to: archive, inFolder: folder, sevenZip: sevenZip)
        }
    }

    private func runEdit(label: String, _ work: @escaping @Sendable (SevenZip) throws -> Void) {
        guard let sevenZip = SevenZip.bundled() else { return }
        editing = label
        Task {
            let result: Error? = await Task.detached(priority: .userInitiated) {
                do { try work(sevenZip); return nil } catch { return error }
            }.value
            editing = nil
            selection.removeAll()
            if let result {
                errorTitle = String(localized: "Couldn’t Change the Archive")
                errorMessage = result.localizedDescription
            }
            load()
        }
    }

    func close() {
        watchTimer?.invalidate()
        watchTimer = nil
        watched.removeAll()
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
        let native = listing.source == .zip && !item.isEncrypted && !isRemote
        let remote = self.remote
        let pw = password
        let engine = self.engine
        let folder = TempFiles.newFolder()
        tempFolders.append(folder)
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            let progress = Progress(totalUnitCount: 100)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let written: [URL]
                    if let remote, let index = item.entryIndex {
                        written = [try remote.extract(remote.entries[index], as: item.name, into: folder,
                                                      isCancelled: { progress.isCancelled })]
                    } else if native, let index = item.entryIndex {
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
