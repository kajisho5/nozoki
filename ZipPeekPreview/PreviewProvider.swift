import Cocoa
import ZipPeekCore
import QuickLookUI
import UniformTypeIdentifiers

/// Finderで圧縮ファイルを選んでスペースキーを押したときに、中身の一覧を返す（デザイン①）。
/// zip は末尾の目次だけを自前で読む。7z・rar・tar などは、アプリに同梱の 7-Zip に一覧だけを頼む。
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
                guard let sevenZip = Self.sevenZip() else {
                    let exe = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/7zz").path
                    NSLog("ZipPeekPreview: 7zz not usable. bundle=%@ exists=%d exec=%d aux=%@", Bundle.main.bundlePath,
                          FileManager.default.fileExists(atPath: exe) ? 1 : 0, FileManager.default.isExecutableFile(atPath: exe) ? 1 : 0,
                          Bundle.main.url(forAuxiliaryExecutable: "7zz")?.path ?? "nil")
                    // 原因を調べられるよう、確かめた場所と結果も表示する
                    let fm = FileManager.default
                    let detail = "\(exe) exists=\(fm.fileExists(atPath: exe)) readable=\(fm.isReadableFile(atPath: exe)) exec=\(fm.isExecutableFile(atPath: exe))"
                    throw NSError(domain: "ZipPeekPreview", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: (SevenZipError.notFound.errorDescription ?? "") + "\n" + detail])
                }
                listing = ArchiveListing.build(raw: try sevenZip.list(url, password: nil))
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

    /// この部品の中に置いた 7zz（ZipPeekPreview.appex/Contents/MacOS/7zz）。
    /// サンドボックスの中からはアプリ本体の 7zz を使えないので、部品専用に「サンドボックスを受け継ぐ」署名をしたものを使う
    static func sevenZip() -> SevenZip? { SevenZip.bundled() }
}
