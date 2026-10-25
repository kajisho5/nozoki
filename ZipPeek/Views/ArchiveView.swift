import QuickLook
import SwiftUI
import ZipPeekCore

/// 中身を見る窓（デザイン②・⑪）。操作は標準のツールバーに置く（macOS 26以降はシステムが Liquid Glass の浮かぶボタンとして描く）
struct ArchiveView: View {
    @Bindable var model: ArchiveModel

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView(String(localized: "Reading the table of contents…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label(String(localized: "Couldn’t open “\(model.url.lastPathComponent)”"),
                          systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button(String(localized: "Try Again")) { model.load() }
                }
            case .loaded:
                if let listing = model.listing {
                    LoadedView(model: model, listing: listing)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .navigationTitle(model.url.lastPathComponent)
        .quickLookPreview($model.previewURL)
        .alert(model.errorTitle ?? String(localized: "Couldn’t Extract"),
               isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil; model.errorTitle = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil; model.errorTitle = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct LoadedView: View {
    @Bindable var model: ArchiveModel
    let listing: ArchiveListing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model, listing: listing)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            VStack(spacing: 0) {
                FileTable(model: model)
                StatusBar(model: model, listing: listing)
            }
            .overlay(alignment: .bottom) {
                if let label = model.editing {
                    GlassCapsule {
                        ProgressView().controlSize(.small)
                        Text(label)
                    }
                    .padding(.bottom, 44)
                }
                if let e = model.extraction, !(e.isForPreview && e.totalBytes < 200_000_000) {
                    ExtractionCapsule(model: model, extraction: e)
                        .padding(.bottom, 44)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: model.extraction != nil)
        }
        .navigationSubtitle(String(localized: "\(model.folderTitle) · \(model.visibleItems.count.formatted()) items"))
        .searchable(text: $model.search, placement: .toolbar, prompt: Text(String(localized: "Search file names")))
        .toolbar { ArchiveToolbar(model: model, listing: listing) }
    }
}

// MARK: - サイドバー

private struct Sidebar: View {
    @Bindable var model: ArchiveModel
    let listing: ArchiveListing

    var body: some View {
        List(selection: Binding(get: { model.isSearching ? nil : model.folderPath },
                                set: { model.search = ""; model.folderPath = $0; model.selection.removeAll() })) {
            Section(model.url.lastPathComponent) {
                FolderRow(name: String(localized: "All"), count: listing.summary.fileCount, isRoot: true)
                    .tag("")
                OutlineGroup(listing.root.children ?? [], children: \.children) { node in
                    FolderRow(name: node.name, count: node.fileCount, isRoot: false)
                        .tag(node.path)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Expanded \(ByteFormat.string(listing.summary.totalSize))"))
                Text(String(localized: "Packed \(ByteFormat.string(listing.summary.packedSize))"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct FolderRow: View {
    let name: String
    let count: Int
    let isRoot: Bool

    var body: some View {
        HStack {
            Label(name, systemImage: isRoot ? "square.stack.3d.up" : "folder").lineLimit(1)
            Spacer(minLength: 4)
            Text(count.formatted()).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ツールバー（A4。macOS 26以降はシステムがガラスの浮かぶボタンとして描く）

private struct ArchiveToolbar: ToolbarContent {
    @Bindable var model: ArchiveModel
    let listing: ArchiveListing

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { model.goUp() } label: {
                Label(String(localized: "Enclosing Folder"), systemImage: "chevron.backward")
            }
            .help(String(localized: "Go to the enclosing folder (⌘↑)"))
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(model.currentFolder.isEmpty || model.isSearching)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if listing.hasLegacyNames {
                EncodingMenu(model: model, listing: listing)
            }
            Button { model.chooseAndAdd() } label: {
                Label(String(localized: "Add Files…"), systemImage: "plus")
            }
            .help(model.editBlocker?.localizedDescription
                  ?? String(localized: "Add files to the folder you’re viewing (or drag them into this window)"))
            .disabled(model.editBlocker != nil || model.editing != nil)
            Button {
                if let item = model.selectedItems.first(where: { !$0.isFolder }) { model.preview(item) }
            } label: {
                Label(String(localized: "Preview"), systemImage: "eye")
            }
            .help(String(localized: "Temporarily extract and show the selected file (or press Space)"))
            .disabled(!model.selectedItems.contains { !$0.isFolder } || model.extraction != nil)

            MoreMenu(model: model)

            Button {
                model.extractSelection()
            } label: {
                Label(model.selection.isEmpty ? String(localized: "Extract All") : String(localized: "Extract"),
                      systemImage: "arrow.down.to.line")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .help(String(localized: "Save the selected files and folders, or everything if nothing is selected"))
            .disabled(model.visibleItems.isEmpty || model.extraction != nil)
        }
    }
}

/// そのほかの操作（名前を変える、既定のアプリで開く、壊れていないか確かめる）
private struct MoreMenu: View {
    @Bindable var model: ArchiveModel

    var body: some View {
        Menu {
            let one = model.selectedItems.count == 1 ? model.selectedItems.first : nil
            Button(String(localized: "Open in Default App")) { if let one { model.openInDefaultApp(one) } }
                .disabled(one == nil || one?.isFolder == true || model.extraction != nil)
            Button(String(localized: "Rename…")) { model.requestRename() }
                .disabled(!model.canRename)
            Divider()
            Button(String(localized: "Check for Damage")) { model.verify() }
                .disabled(model.isRemote || model.verifying || model.extraction != nil || model.editing != nil)
        } label: {
            Label(String(localized: "More"), systemImage: "ellipsis.circle")
        }
        .help(String(localized: "Rename, open in another app, or check the archive for damage"))
    }
}

/// ファイル名の文字コードの切り替え（Windowsで作ったzipなど、UTF-8でない名前があるときだけ出す）
private struct EncodingMenu: View {
    @Bindable var model: ArchiveModel
    let listing: ArchiveListing

    var body: some View {
        Menu {
            Picker(String(localized: "File Name Encoding"), selection: Binding(get: { model.encodingChoice }, set: { model.setEncoding($0) })) {
                Text(String(localized: "Automatic (\(listing.detectedEncoding.label))")).tag(NameEncoding?.none)
                Divider()
                ForEach(NameEncoding.allCases) { enc in
                    Text(enc.label).tag(NameEncoding?.some(enc))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(String(localized: "File Name Encoding"), systemImage: "character.book.closed")
        }
        .help(String(localized: "If file names look garbled, change the encoding here (now: \(listing.encoding.label))"))
    }
}

// MARK: - 一覧

private struct FileTable: View {
    @Bindable var model: ArchiveModel

    var body: some View {
        let items = model.visibleItems
        Table(of: ArchiveItem.self, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn(String(localized: "Name"), value: \.name, comparator: .localizedStandard) { item in
                HStack(spacing: 7) {
                    FileIconView(item: item)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if item.isEncrypted {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                            .help(String(localized: "Password-protected"))
                            .accessibilityLabel(String(localized: "Password-protected"))
                    }
                    if model.isSearching, !item.parentPath.isEmpty {
                        Text(item.parentPath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                    }
                }
            }
            .width(min: 220, ideal: 360)

            TableColumn(String(localized: "Size"), value: \.size) { item in
                Text(ByteFormat.string(item.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90)

            TableColumn(String(localized: "Packed"), value: \.packedSize) { item in
                Text(ByteFormat.string(item.packedSize)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90)

            TableColumn(String(localized: "Modified"), value: \.sortDate) { item in
                Text(item.modified.map { $0.formatted(date: .numeric, time: .shortened) } ?? "—")
                    .monospacedDigit().foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 110, ideal: 140)
        } rows: {
            ForEach(items) { item in
                TableRow(item).itemProvider { model.itemProvider(for: item) }
            }
        }
        .contextMenu(forSelectionType: ArchiveItem.ID.self) { ids in
            let chosen = items.filter { ids.contains($0.id) }
            if chosen.count == 1, let one = chosen.first, !one.isFolder {
                if ArchiveKind.isArchive(URL(fileURLWithPath: one.name)) {
                    Button(String(localized: "Look Inside")) { model.openNested(one) }
                }
                Button(String(localized: "Preview")) { model.preview(one) }
                Button(String(localized: "Open in Default App")) { model.openInDefaultApp(one) }
            }
            if !chosen.isEmpty {
                Button(String(localized: "Extract…")) {
                    model.selection = Set(ids)
                    model.extractSelection()
                }
                Divider()
                if chosen.count == 1, let one = chosen.first {
                    Button(String(localized: "Rename…")) {
                        model.selection = Set(ids)
                        model.requestRename(one)
                    }
                    .disabled(model.editBlocker != nil || (model.listing?.namesNeedConversion ?? false))
                }
                Button(String(localized: "Delete from Archive…"), role: .destructive) {
                    model.selection = Set(ids)
                    model.requestDelete()
                }
                .disabled(model.editBlocker != nil || (model.listing?.namesNeedConversion ?? false))
            }
        } primaryAction: { ids in
            if ids.count == 1, let item = items.first(where: { ids.contains($0.id) }) { model.open(item) }
        }
        .onDeleteCommand { model.requestDelete() }
        // Finder などから落とされたファイルを、今見ているフォルダに足す
        .dropDestination(for: URL.self) { urls, _ in
            model.requestAdd(urls)
        }
        .onKeyPress(.space) {
            if let item = model.selectedItems.first(where: { !$0.isFolder }) {
                model.preview(item)
                return .handled
            }
            return .ignored
        }
        .overlay {
            if items.isEmpty {
                if model.isSearching {
                    ContentUnavailableView.search(text: model.search)
                } else {
                    ContentUnavailableView(String(localized: "This Folder Is Empty"), systemImage: "folder")
                }
            }
        }
    }
}

// MARK: - 作業中の表示（ガラスの粒）

private struct ExtractionCapsule: View {
    let model: ArchiveModel
    let extraction: ArchiveModel.Extraction

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            GlassCapsule {
                ProgressRing(progress: extraction.progress).frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(extraction.isForPreview
                         ? String(localized: "Preparing preview · \(extraction.currentName)")
                         : String(localized: "Extracting · \(extraction.currentName)"))
                        .lineLimit(1).truncationMode(.middle)
                    Text(remainingText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                CancelButton(help: String(localized: "Stop extracting (esc)")) { model.cancelExtraction() }
                    .keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: 460)
        }
    }

    var remainingText: String {
        let pct = Int((extraction.progress * 100).rounded())
        guard let s = extraction.remainingSeconds else { return "\(pct)%" }
        if s < 60 { return String(localized: "\(pct)% · about \(max(1, Int(s))) s left") }
        return String(localized: "\(pct)% · about \(Int(s / 60)) min left")
    }
}

/// 丸い進み具合
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.02, progress))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.2), value: progress)
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Progress"))
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}

/// 中止ボタン（見た目は小さな記号、当たり判定は 44pt 四方まで広げる）
struct CancelButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(String(localized: "Stop"), systemImage: "xmark.circle.fill")
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.vertical, -11)
        .help(help)
    }
}

// MARK: - 下の帯

private struct StatusBar: View {
    @Bindable var model: ArchiveModel
    let listing: ArchiveListing

    var body: some View {
        HStack(spacing: 12) {
            if model.selection.isEmpty {
                Text(String(localized: "\(listing.summary.fileCount.formatted()) files · read in \(String(format: "%.1f", model.loadSeconds)) s"))
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "\(model.selection.count) selected")).fontWeight(.semibold)
                Text(String(localized: "· \(ByteFormat.string(model.selectedSize))")).foregroundStyle(.secondary)
            }
            if let free = model.desktopFreeSpace {
                Text(String(localized: "· Desktop free \(ByteFormat.string(UInt64(max(free, 0))))"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if listing.hasLegacyNames {
                Text(String(localized: "File names: \(listing.encoding.label)"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }
}
