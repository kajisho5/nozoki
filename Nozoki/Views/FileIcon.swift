import AppKit
import NozokiCore
import SwiftUI
import UniformTypeIdentifiers

/// 種類ごとのアイコン。macOSのFinderと同じアイコンを使う
enum FileIcon {
    private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(for item: ArchiveItem) -> NSImage {
        let key = item.isFolder ? "/folder" : item.fileExtension
        if let cached = cache[key] { return cached }
        let image: NSImage
        if item.isFolder {
            image = NSWorkspace.shared.icon(for: .folder)
        } else {
            image = NSWorkspace.shared.icon(for: contentType(for: item.fileExtension))
        }
        cache[key] = image
        return image
    }

    static func contentType(for ext: String) -> UTType {
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .data }
        return type
    }
}

struct FileIconView: View {
    let item: ArchiveItem

    var body: some View {
        Image(nsImage: FileIcon.image(for: item))
            .resizable()
            .interpolation(.high)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}
