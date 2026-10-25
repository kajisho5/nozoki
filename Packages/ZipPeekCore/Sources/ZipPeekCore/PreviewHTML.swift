import Foundation

/// のぞき窓（Finderのスペースキー）に出す一覧のHTMLを作る。
/// クイックルックの中ではスクリプトが動かない前提で、開閉は <details> だけで実現する
public enum PreviewHTML {
    /// 表示する行の上限。これを超えたら残り件数だけ書く
    public static let rowLimit = 3_000

    public static func make(listing: ArchiveListing, fileName: String, elapsed: TimeInterval? = nil) -> String {
        let s = listing.summary
        var rows = 0
        var body = ""

        func render(_ folderPath: String, depth: Int) {
            for item in listing.items(in: folderPath) {
                if rows >= rowLimit { return }
                rows += 1
                if item.isFolder {
                    let open = depth == 0 ? " open" : ""
                    body += "<details\(open)><summary>\(row(item, depth: depth))</summary>"
                    render(item.path, depth: depth + 1)
                    body += "</details>"
                } else {
                    body += "<div class=\"f\">\(row(item, depth: depth))</div>"
                }
            }
        }
        render("", depth: 0)

        let remaining = s.fileCount + s.folderCount - rows
        let more = remaining > 0
            ? "<p class=\"more\">" + tr("ほか \(remaining.formatted()) 件。すべて見るには ZipPeek で開いてください。", "\(remaining.formatted()) more items. Open in ZipPeek to see everything.") + "</p>" : ""
        let notice = listing.encoding == .shiftJIS && listing.hasLegacyNames
            ? "<div class=\"notice\"><span>i</span>" + tr("Windowsで作られたzipのため、ファイル名を日本語（Shift_JIS）として読み替えています", "File names were made on Japanese Windows and are shown as Shift_JIS") + "</div>" : ""
        let locked = s.encryptedCount > 0
            ? "<div class=\"notice warn\"><span>!</span>" + tr("パスワード付きのファイルが \(s.encryptedCount) 件あります", "\(s.encryptedCount) password-protected files") + "</div>" : ""
        let timing = elapsed.map { tr(String(format: " ／ 目次の読み込み %.1f 秒", $0), String(format: " / read in %.1f s", $0)) } ?? ""
        let empty = s.fileCount == 0 ? "<p class=\"more\">" + tr("このzipは空です。", "This archive is empty.") + "</p>" : ""

        return """
        <!doctype html><html lang="\(L10n.isJapanese ? "ja" : "en")"><head><meta charset="utf-8">
        <title>\(esc(fileName))</title>
        <style>\(css)</style></head><body>
        <header>
          <h1>\(tr("\(s.fileCount.formatted()) ファイル", "\(s.fileCount.formatted()) files"))<small>・ \(tr("\(s.folderCount.formatted()) フォルダ", "\(s.folderCount.formatted()) folders"))</small></h1>
          <p class="sub">\(tr("展開後", "Expanded")) \(ByteFormat.string(s.totalSize))\(s.packedSize > 0 ? " " + tr("／ 圧縮後", "/ packed") + " " + ByteFormat.string(s.packedSize) : "")\(timing)</p>
        </header>
        <div class="head"><span>\(tr("名前", "Name"))</span><span>\(tr("サイズ", "Size"))</span><span>\(tr("圧縮後", "Packed"))</span><span>\(tr("更新日", "Modified"))</span></div>
        <main>\(body)\(empty)\(more)</main>
        \(notice)\(locked)
        <footer>\(tr("取り出すには ZipPeek で開いてください", "Open in ZipPeek to extract files"))</footer>
        </body></html>
        """
    }

    /// 読めなかったときに出す画面
    public static func errorPage(fileName: String, message: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><title>\(esc(fileName))</title>
        <style>\(css)</style></head><body>
        <header><h1>\(tr("中身を表示できません", "Can't show the contents"))</h1><p class="sub">\(esc(message))</p></header>
        <footer>\(tr("ZipPeek で開くと、詳しい理由を確認できます", "Open in ZipPeek for details"))</footer>
        </body></html>
        """
    }

    static func row(_ item: ArchiveItem, depth: Int) -> String {
        let indent = depth * 18
        let icon = item.isFolder ? "<i class=\"ic dir\"></i>" : "<i class=\"ic \(kind(item.fileExtension))\"></i>"
        let date = item.modified.map { dateFormatter.string(from: $0) } ?? ""
        let lock = item.isEncrypted ? "<em>" + tr("鍵付き", "Locked") + "</em>" : ""
        return """
        <span class="n" style="padding-left:\(indent)px">\(icon)<b>\(esc(item.name))</b>\(lock)</span>\
        <span class="s">\(ByteFormat.string(item.size))</span>\
        <span class="p">\(item.packedSize > 0 ? ByteFormat.string(item.packedSize) : "–")</span>\
        <span class="d">\(date)</span>
        """
    }

    /// 種類ごとのアイコン色
    public static func kind(_ ext: String) -> String {
        switch ext {
        case "mov", "mp4", "m4v", "mxf", "avi", "mkv", "mts", "m2ts", "braw", "r3d", "webm": return "vid"
        case "wav", "aif", "aiff", "mp3", "m4a", "flac", "aac", "ogg": return "aud"
        case "jpg", "jpeg", "png", "heic", "gif", "tif", "tiff", "psd", "webp", "dng", "cr3", "arw", "svg": return "img"
        case "pdf": return "pdf"
        case "zip", "7z", "rar", "gz", "tar", "dmg": return "arc"
        default: return "doc"
        }
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    static func esc(_ s: String) -> String {
        var r = ""
        r.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            case "\"": r += "&quot;"
            default: r.append(c)
            }
        }
        return r
    }

    static let css = """
    :root{--bg:#ffffff;--fg:#1d2420;--mut:#6b746f;--line:#e3e7e4;--hov:#f3f6f4;--acc:#2f5bea;--note:#e6ecff;--notefg:#1f3fa8;--warn:#fbeedd;--warnfg:#8a4a0e}
    @media (prefers-color-scheme:dark){:root{--bg:#1e1f22;--fg:#e8e8ea;--mut:#8d9096;--line:#34363a;--hov:#26272b;--acc:#7c9bff;--note:#1b2340;--notefg:#c3d0ff;--warn:#3a2a17;--warnfg:#f0c08a}}
    *{box-sizing:border-box}
    body{margin:0;padding:20px 24px;background:var(--bg);color:var(--fg);font:13px/1.5 -apple-system,"Hiragino Sans",sans-serif}
    h1{font-size:22px;margin:0;font-weight:700}h1 small{font-size:14px;font-weight:400;color:var(--mut);margin-left:8px}
    .sub{margin:2px 0 14px;color:var(--mut)}
    .head,summary,.f{display:grid;grid-template-columns:minmax(0,1fr) 90px 90px 92px;gap:8px;align-items:center}
    .head{font-size:12px;font-weight:600;color:var(--mut);border-top:1px solid var(--line);border-bottom:1px solid var(--line);padding:6px 4px}
    .head span:not(:first-child),.s,.p,.d{text-align:right;font-variant-numeric:tabular-nums}
    summary,.f{padding:4px;border-radius:5px;list-style:none;cursor:default}
    summary::-webkit-details-marker{display:none}
    summary:hover,.f:hover{background:var(--hov)}
    .n{display:flex;align-items:center;gap:7px;min-width:0}.n b{font-weight:400;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    summary .n::before{content:"";border:4px solid transparent;border-left:6px solid var(--mut);margin-right:-2px}
    details[open]>summary .n::before{transform:rotate(90deg) translateX(2px)}
    .f .n{padding-left:12px}
    .p,.d{color:var(--mut)}
    .ic{width:14px;height:16px;border-radius:2px;flex:none;background:#9aa0a6}
    .ic.dir{width:18px;height:13px;background:#5aa9e6}.vid{background:#8f6fd6}.aud{background:#e07a5f}.img{background:#4fb38a}.pdf{background:#e0a43a}.arc{background:#7d8a96}
    em{font-style:normal;font-size:10px;color:var(--warnfg);border:1px solid currentColor;border-radius:8px;padding:0 6px;flex:none}
    .more{color:var(--mut);margin:12px 4px}
    .notice{margin-top:14px;padding:9px 12px;border-radius:8px;background:var(--note);color:var(--notefg);display:flex;gap:10px;align-items:center}
    .notice span{width:16px;height:16px;border-radius:50%;background:var(--acc);color:#fff;font-size:11px;font-weight:700;display:grid;place-items:center;flex:none}
    .notice.warn{background:var(--warn);color:var(--warnfg)}.notice.warn span{background:var(--warnfg)}
    footer{margin-top:16px;text-align:center;color:var(--mut);font-size:12px}
    """
}
