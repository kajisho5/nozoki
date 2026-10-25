import Foundation

/// 圧縮ファイルが壊れていないかを、書き出さずに確かめる（7-Zip の「テスト」）
public enum ArchiveTest {
    public struct Result: Sendable, Equatable {
        public let ok: Bool
        /// 壊れていたときの 7-Zip の説明（最後の数行）
        public let detail: String
    }

    public static func run(_ archive: URL, password: String?, sevenZip: SevenZip,
                           onProgress: @escaping @Sendable (Double) -> Void = { _ in },
                           isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> Result {
        do {
            let out = try sevenZip.run(["t", "-sccUTF-8", "-bsp1", "-bso0", "-bse2", "-p" + (password ?? ""),
                                        ArchiveKind.firstVolume(of: archive).standardizedFileURL.path],
                                       password: password, onProgress: onProgress, isCancelled: isCancelled)
            // 終了コード 1（警告）も「一部読めない」なので壊れている扱いにする
            return Result(ok: out.status == 0, detail: out.status == 0 ? "" : lastLines(out.stderr + out.stdout))
        } catch SevenZipError.failed(let detail) {
            return Result(ok: false, detail: detail)
        }
    }

    static func lastLines(_ s: String) -> String {
        s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.suffix(4).joined(separator: "\n")
    }
}
