import Foundation
import ZIPFoundation

public enum ExtractError: Error, LocalizedError, Equatable {
    case encrypted(String)
    case openFailed
    case entryMissing(String)
    case cancelled
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .encrypted(let name): return "「\(name)」はパスワード付きのため、今の版では取り出せません。"
        case .openFailed: return "zipを開けませんでした。壊れている可能性があります。"
        case .entryMissing(let name): return "「\(name)」がzipの中に見つかりませんでした。"
        case .cancelled: return "取り出しを中止しました。"
        case .writeFailed(let name): return "「\(name)」を書き出せませんでした。保存先の空き容量と書き込み権限を確認してください。"
        }
    }
}

/// 選んだファイルだけをzipから取り出す
public struct Extractor: Sendable {
    public struct Job: Sendable {
        public let entryIndex: Int
        public let name: String
        public let size: UInt64
        public let isEncrypted: Bool
        /// 保存先フォルダからの相対パス（安全な形に直してから使う）
        public let relativePath: String

        public init(entryIndex: Int, name: String, size: UInt64, isEncrypted: Bool, relativePath: String) {
            self.entryIndex = entryIndex
            self.name = name
            self.size = size
            self.isEncrypted = isEncrypted
            self.relativePath = relativePath
        }
    }

    public struct Progress: Sendable {
        public let doneBytes: UInt64
        public let totalBytes: UInt64
        public let fileNumber: Int
        public let fileTotal: Int
        public let currentName: String
    }

    public let zipURL: URL

    public init(zipURL: URL) { self.zipURL = zipURL }

    /// 取り出す。書き出したファイルのURLを返す。
    /// 同じ名前があれば「名前 2.拡張子」のようにずらす。途中で止めた場合、書きかけのファイルは残さない
    @discardableResult
    public func extract(_ jobs: [Job], into destination: URL,
                        onProgress: @Sendable (Progress) -> Void = { _ in },
                        isCancelled: @Sendable () -> Bool = { false }) throws -> [URL] {
        if let locked = jobs.first(where: { $0.isEncrypted }) { throw ExtractError.encrypted(locked.name) }
        let archive: Archive
        do { archive = try Archive(url: zipURL, accessMode: .read) } catch { throw ExtractError.openFailed }

        // 目次の番号で対象を引けるように、必要な番号まで順に読む
        let wanted = Set(jobs.map(\.entryIndex))
        let maxIndex = wanted.max() ?? -1
        var found: [Int: Entry] = [:]
        var i = 0
        for entry in archive {
            if i > maxIndex { break }
            if wanted.contains(i) { found[i] = entry }
            i += 1
        }

        let fm = FileManager.default
        let total = jobs.reduce(UInt64(0)) { $0 + $1.size }
        var done: UInt64 = 0
        var written: [URL] = []

        for (n, job) in jobs.enumerated() {
            if isCancelled() { throw ExtractError.cancelled }
            guard let entry = found[job.entryIndex] else { throw ExtractError.entryMissing(job.name) }
            let target = Self.uniqueURL(destination.appendingPathComponent(Self.safeRelativePath(job.relativePath)))
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let partial = target.deletingLastPathComponent()
                .appendingPathComponent(".\(target.lastPathComponent).nozoki-partial")
            try? fm.removeItem(at: partial)
            guard fm.createFile(atPath: partial.path, contents: nil),
                  let out = try? FileHandle(forWritingTo: partial) else {
                throw ExtractError.writeFailed(job.name)
            }
            onProgress(Progress(doneBytes: done, totalBytes: total, fileNumber: n + 1, fileTotal: jobs.count, currentName: job.name))
            var lastReport = Date()
            do {
                _ = try archive.extract(entry, bufferSize: 1 << 20, skipCRC32: false) { chunk in
                    if isCancelled() { throw ExtractError.cancelled }
                    try out.write(contentsOf: chunk)
                    done += UInt64(chunk.count)
                    if Date().timeIntervalSince(lastReport) > 0.1 {
                        lastReport = Date()
                        onProgress(Progress(doneBytes: done, totalBytes: total, fileNumber: n + 1,
                                            fileTotal: jobs.count, currentName: job.name))
                    }
                }
                try out.close()
                if let date = entry.fileAttributes[.modificationDate] as? Date {
                    try? fm.setAttributes([.modificationDate: date], ofItemAtPath: partial.path)
                }
                try fm.moveItem(at: partial, to: target)
                written.append(target)
            } catch {
                try? out.close()
                try? fm.removeItem(at: partial)
                if let e = error as? ExtractError { throw e }
                throw ExtractError.writeFailed(job.name)
            }
        }
        onProgress(Progress(doneBytes: total, totalBytes: total, fileNumber: jobs.count, fileTotal: jobs.count, currentName: ""))
        return written
    }

    /// 「..」などで保存先の外に出ないよう、パスを安全な形に直す
    static func safeRelativePath(_ p: String) -> String {
        let parts = p.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .filter { $0 != "." && $0 != ".." && !$0.isEmpty }
            .map { $0.replacingOccurrences(of: ":", with: "-") }
        return parts.isEmpty ? "名称未設定" : parts.joined(separator: "/")
    }

    /// 同名があれば「名前 2.拡張子」「名前 3.拡張子」…
    static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
