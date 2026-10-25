import QuickLook
import SwiftUI
import ZipPeekCore

/// 中身を見る窓（デザイン②・⑪）。窓は不透明で読みやすく、上の操作と作業中の表示だけガラスで浮かせる
struct ArchiveView: View {
    @Bindable var model: ArchiveModel

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView(tr("目次を読んでいます…", "Reading the table of contents…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label(tr("「\(model.url.lastPathComponent)」を開けませんでした", "Couldn’t open “\(model.url.lastPathComponent)”"),
                          systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button(tr("もう一度読む", "Try Again")) { model.load() }
                }
            case .loaded:
                if let listing = model.listing {
                    LoadedView(model: model, listing: listing)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .quickLookPreview($model.previewURL)
        .alert(tr("うまくいきませんでした", "Something went wrong"),
               isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct LoadedView: View {
    @Bindable var model: ArchiveModel
    let listing: ArchiveListing

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model, listing: listing)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            VStack(spacing: 0) {
                FileTable(model: model)
                StatusBar(model: model, listing: listing)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                FloatingHeader(model: model)
            }
            .overlay(alignment: .bottom) {
                if let e = model.extraction, !(e.isForPreview && e.totalBytes < 200_000_000) {
                    ExtractionCapsule(model: model, extraction: e)
                        .padding(.bottom, 44)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.extraction != nil)
        }
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
                FolderRow(name: tr("すべて", "All"), count: listing.summary.fileCount, isRoot: true)
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
                Text("\(tr("展開後", "Expanded")) \(ByteFormat.string(listing.summary.totalSize))")
                Text("\(tr("圧縮後", "Packed")) \(ByteFormat.string(listing.summary.packedSize))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
    }
}

// MARK: - 浮かぶ操作（A4）

private struct FloatingHeader: View {
    @Bindable var model: ArchiveModel

    var body: some View {
        HStack(spacing: 12) {
            GlassCapsule {
                Button { model.goUp() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .help(tr("ひとつ上のフォルダへ", "Go to the enclosing folder"))
                    .disabled(model.currentFolder.isEmpty || model.isSearching)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.folderTitle).font(.headline).lineLimit(1)
                    Text(tr("\(model.visibleItems.count.formatted()) 項目", "\(model.visibleItems.count.formatted()) items"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            GlassCapsule {
                Button {
                    if let item = model.selectedItems.first(where: { !$0.isFolder }) { model.preview(item) }
                } label: {
                    Label(tr("プレビュー", "Preview"), systemImage: "eye")
                }
                .buttonStyle(.plain)
                .help(tr("選んだファイルだけを一時的に取り出して表示します（スペースキーでも可）",
                         "Temporarily extract and show the selected file (or press Space)"))
                .disabled(!model.selectedItems.contains { !$0.isFolder } || model.extraction != nil)

                Button {
                    model.extractSelection()
                } label: {
                    Label(model.selection.isEmpty ? tr("すべて取り出す", "Extract All") : tr("取り出す", "Extract"),
                          systemImage: "arrow.down.to.line")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .help(tr("選んだファイルやフォルダだけを書き出します", "Save only the selected files and folders"))
                .disabled(model.visibleItems.isEmpty || model.extraction != nil)

                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(tr("検索", "Search"), text: $model.search, prompt: Text(tr("ファイル名で検索", "Search file names")))
                        .textFieldStyle(.plain)
                        .frame(width: 150)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

// MARK: - 一覧

private struct FileTable: View {
    @Bindable var model: ArchiveModel

    var body: some View {
        let items = model.visibleItems
        Table(of: ArchiveItem.self, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn(tr("名前", "Name"), value: \.name, comparator: .localizedStandard) { item in
                HStack(spacing: 7) {
                    FileIconView(item: item)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if item.isEncrypted {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                            .help(tr("パスワード付き", "Password-protected"))
                    }
                    if model.isSearching, !item.parentPath.isEmpty {
                        Text(item.parentPath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                    }
                }
            }
            .width(min: 220, ideal: 360)

            TableColumn(tr("サイズ", "Size"), value: \.size) { item in
                Text(ByteFormat.string(item.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90)

            TableColumn(tr("圧縮後", "Packed"), value: \.packedSize) { item in
                Text(ByteFormat.string(item.packedSize)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90)

            TableColumn(tr("更新日", "Modified"), value: \.sortDate) { item in
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
                Button(tr("プレビュー", "Preview")) { model.preview(one) }
            }
            if !chosen.isEmpty {
                Button(tr("取り出す…", "Extract…")) {
                    model.selection = Set(ids)
                    model.extractSelection()
                }
            }
        } primaryAction: { ids in
            if ids.count == 1, let item = items.first(where: { ids.contains($0.id) }) { model.open(item) }
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
                ContentUnavailableView(model.isSearching ? tr("見つかりません", "No Results") : tr("このフォルダは空です", "This folder is empty"),
                                       systemImage: model.isSearching ? "magnifyingglass" : "folder")
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
                         ? tr("プレビューの準備中 ・ \(extraction.currentName)", "Preparing preview · \(extraction.currentName)")
                         : tr("取り出し中 ・ \(extraction.currentName)", "Extracting · \(extraction.currentName)"))
                        .lineLimit(1).truncationMode(.middle)
                    Text(remainingText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Button { model.cancelExtraction() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(tr("中止", "Cancel"))
                    .keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: 460)
        }
    }

    var remainingText: String {
        let pct = Int((extraction.progress * 100).rounded())
        guard let s = extraction.remainingSeconds else { return "\(pct)%" }
        if s < 60 { return tr("\(pct)% ・ 残り 約 \(max(1, Int(s))) 秒", "\(pct)% · about \(max(1, Int(s))) s left") }
        return tr("\(pct)% ・ 残り 約 \(Int(s / 60)) 分", "\(pct)% · about \(Int(s / 60)) min left")
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
                .animation(.linear(duration: 0.2), value: progress)
        }
    }
}

// MARK: - 下の帯

private struct StatusBar: View {
    @Bindable var model: ArchiveModel
    let listing: ArchiveListing

    var body: some View {
        HStack(spacing: 12) {
            if model.selection.isEmpty {
                Text(tr("\(listing.summary.fileCount.formatted()) ファイル ・ 目次の読み込み \(String(format: "%.1f", model.loadSeconds)) 秒",
                        "\(listing.summary.fileCount.formatted()) files · read in \(String(format: "%.1f", model.loadSeconds)) s"))
                    .foregroundStyle(.secondary)
            } else {
                Text(tr("\(model.selection.count) 件選択", "\(model.selection.count) selected")).fontWeight(.semibold)
                Text("・ \(ByteFormat.string(model.selectedSize))").foregroundStyle(.secondary)
            }
            if let free = model.desktopFreeSpace {
                Text(tr("・ デスクトップの空き \(ByteFormat.string(UInt64(max(free, 0))))",
                        "· Desktop free \(ByteFormat.string(UInt64(max(free, 0))))"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if listing.hasLegacyNames {
                Menu {
                    Button(tr("自動（\(listing.detectedEncoding.label)）", "Automatic (\(listing.detectedEncoding.label))")) { model.setEncoding(nil) }
                    Divider()
                    ForEach(NameEncoding.allCases) { enc in
                        Button(enc.label) { model.setEncoding(enc) }
                    }
                } label: {
                    Text(tr("ファイル名：", "File names: ") + listing.encoding.label
                         + (model.encodingChoice == nil ? tr("（自動判定）", " (auto)") : ""))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .help(tr("ファイル名が文字化けしているときは、ここで読み方を切り替えます", "If file names look garbled, change the encoding here"))
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
