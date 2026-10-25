import NozokiCore
import QuickLook
import SwiftUI

/// zipを開いた窓（デザイン②）
struct ArchiveView: View {
    @Bindable var model: ArchiveModel

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("目次を読んでいます…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                FailedView(message: message, fileName: model.url.lastPathComponent) { model.load() }
            case .loaded:
                if let listing = model.listing {
                    LoadedView(model: model, listing: listing)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .quickLookPreview($model.previewURL)
        .sheet(isPresented: Binding(get: { model.showsExtractionSheet },
                                    set: { if !$0 { model.cancelExtraction() } })) {
            ExtractSheet(model: model)
        }
        .alert("うまくいきませんでした", isPresented: Binding(get: { model.errorMessage != nil },
                                                    set: { if !$0 { model.errorMessage = nil } })) {
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
                HeaderBar(model: model)
                Divider()
                FileTable(model: model)
                Divider()
                StatusBar(model: model, listing: listing)
            }
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
                FolderRow(name: "すべて", count: listing.summary.fileCount, isRoot: true)
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
                Text("展開後 \(ByteFormat.string(listing.summary.totalSize))")
                Text("圧縮後 \(ByteFormat.string(listing.summary.packedSize))")
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
            Label(name, systemImage: isRoot ? "square.stack.3d.up" : "folder")
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(count.formatted())
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 上の帯

private struct HeaderBar: View {
    @Bindable var model: ArchiveModel

    var body: some View {
        HStack(spacing: 10) {
            Button { model.goUp() } label: { Image(systemName: "chevron.up") }
                .help("ひとつ上のフォルダへ")
                .disabled(model.currentFolder.isEmpty || model.isSearching)
                .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.folderTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(model.visibleItems.count.formatted()) 項目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                if let item = model.selectedItems.first(where: { !$0.isFolder }) { model.preview(item) }
            } label: {
                Label("プレビュー", systemImage: "eye")
            }
            .help("選んだファイルだけを一時的に取り出して表示します（スペースキーでも可）")
            .disabled(!model.selectedItems.contains { !$0.isFolder } || model.extraction != nil)

            Button {
                model.extractSelection()
            } label: {
                Label(model.selection.isEmpty ? "すべて取り出す" : "取り出す", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.borderedProminent)
            .help("選んだファイルやフォルダだけを、保存先に書き出します")
            .disabled(model.visibleItems.isEmpty || model.extraction != nil)

            TextField("検索", text: $model.search, prompt: Text("ファイル名で検索"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - 一覧

private struct FileTable: View {
    @Bindable var model: ArchiveModel

    var body: some View {
        let items = model.visibleItems
        Table(of: ArchiveItem.self, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("名前", value: \.name, comparator: .localizedStandard) { item in
                HStack(spacing: 7) {
                    FileIconView(item: item)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if item.isEncrypted {
                        Text("鍵付き")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .overlay(Capsule().stroke(.orange.opacity(0.7)))
                    }
                    if model.isSearching {
                        Text(item.parentPath.isEmpty ? "" : item.parentPath)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
            .width(min: 220, ideal: 360)

            TableColumn("サイズ", value: \.size) { item in
                Text(ByteFormat.string(item.size)).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90)

            TableColumn("圧縮後", value: \.packedSize) { item in
                Text(ByteFormat.string(item.packedSize)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90)

            TableColumn("更新日", value: \.sortDate) { item in
                Text(item.modified.map { $0.formatted(date: .numeric, time: .shortened) } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 110, ideal: 140)
        } rows: {
            ForEach(items) { item in
                TableRow(item)
                    .itemProvider { model.itemProvider(for: item) }
            }
        }
        .contextMenu(forSelectionType: ArchiveItem.ID.self) { ids in
            let chosen = items.filter { ids.contains($0.id) }
            if chosen.count == 1, let one = chosen.first, !one.isFolder {
                Button("プレビュー") { model.preview(one) }
            }
            if !chosen.isEmpty {
                Button("取り出す…") {
                    model.selection = Set(ids)
                    model.extractSelection()
                }
            }
        } primaryAction: { ids in
            if ids.count == 1, let item = items.first(where: { ids.contains($0.id) }) {
                model.open(item)
            }
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
                ContentUnavailableView(model.isSearching ? "見つかりません" : "このフォルダは空です",
                                       systemImage: model.isSearching ? "magnifyingglass" : "folder")
            }
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
                Text("\(listing.summary.fileCount.formatted()) ファイル ・ 目次の読み込み \(String(format: "%.1f", model.loadSeconds)) 秒")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(model.selection.count) 件選択").fontWeight(.semibold)
                Text("・ \(ByteFormat.string(model.selectedSize))").foregroundStyle(.secondary)
            }
            if let free = model.desktopFreeSpace {
                Text("・ デスクトップの空き \(ByteFormat.string(UInt64(max(free, 0))))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if listing.hasLegacyNames {
                Menu {
                    Button("自動（\(listing.detectedEncoding.label)）") { model.setEncoding(nil) }
                    Divider()
                    ForEach(NameEncoding.allCases) { enc in
                        Button(enc.label) { model.setEncoding(enc) }
                    }
                } label: {
                    Text("ファイル名：\(listing.encoding.label)\(model.encodingChoice == nil ? "（自動判定）" : "")")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("ファイル名が文字化けしているときは、ここで読み方を切り替えます")
            }
        }
        .font(.callout)
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

// MARK: - 読めなかったとき

private struct FailedView: View {
    let message: String
    let fileName: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("「\(fileName)」を開けませんでした", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("もう一度読む", action: retry)
        }
    }
}
