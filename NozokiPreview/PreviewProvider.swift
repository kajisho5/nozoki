import Cocoa
import NozokiCore
import QuickLookUI
import UniformTypeIdentifiers

/// Finderでzipを選んでスペースキーを押したときに、中身の一覧を返す（デザイン①）。
/// 読むのはzipの末尾の目次だけ。ファイルの書き出しはしない
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let name = url.lastPathComponent
        let start = Date()
        let html: String
        do {
            let listing = try ArchiveListing.load(url: url)
            html = PreviewHTML.make(listing: listing, fileName: name, elapsed: Date().timeIntervalSince(start))
        } catch {
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
