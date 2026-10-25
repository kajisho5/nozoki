import Cocoa
import ZipPeekCore
import QuickLookUI
import UniformTypeIdentifiers

/// Finderで圧縮ファイルを選んでスペースキーを押したときに、中身の一覧を返す（デザイン①）。
/// zip は末尾の目次だけを自前で読む。7z・rar・tar などは macOS の libarchive で目次だけを読む。
/// どちらもファイルの書き出しはしない
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let name = url.lastPathComponent
        let start = Date()
        let html: String
        do {
            let listing: ArchiveListing
            if ArchiveKind.isZip(url) {
                listing = try ArchiveListing.load(url: url)
            } else {
                // サンドボックスの中では 7zz を起動できないので、macOS の libarchive で目次だけ読む
                listing = ArchiveListing.build(raw: try LibArchiveList.entries(url))
            }
            html = PreviewHTML.make(listing: listing, fileName: name, elapsed: Date().timeIntervalSince(start))
        } catch {
            NSLog("ZipPeekPreview: %@", String(describing: error))
            html = PreviewHTML.errorPage(fileName: name, message: error.localizedDescription)
        }
        let data = Data(html.utf8)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 820, height: 620)) { _ in
            data
        }
        reply.stringEncoding = .utf8
        reply.title = name
        return reply
    }

}
