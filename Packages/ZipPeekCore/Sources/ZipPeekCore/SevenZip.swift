import Foundation

/// 圧縮の設定
public struct CompressOptions: Sendable, Equatable, Codable {
    public enum Format: String, Sendable, Codable, CaseIterable {
        case zip, sevenZip, tarGz, tarXz, tarBz2, tarZst, tar, dmg

        /// 画面に出す名前（拡張子そのまま）
        public var label: String {
            switch self {
            case .zip: "zip"
            case .sevenZip: "7z"
            case .tarGz: "tar.gz"
            case .tarXz: "tar.xz"
            case .tarBz2: "tar.bz2"
            case .tarZst: "tar.zst"
            case .tar: "tar"
            case .dmg: "dmg"
            }
        }
        public var fileExtension: String { label }
        /// パスワード・分割が使えるか（zip と 7z だけ）
        public var supportsPassword: Bool { self == .zip || self == .sevenZip }
        public var supportsSplit: Bool { self == .zip || self == .sevenZip }
        /// Mac・Linux 向けの形式か（Windows でもたいてい開けるが、標準で開けるのは zip）
        public var isTar: Bool { [.tarGz, .tarXz, .tarBz2, .tarZst, .tar].contains(self) }
    }
    public enum Level: String, Sendable, Codable, CaseIterable { case fast, normal, max }
    public enum ZipCipher: String, Sendable, Codable, CaseIterable { case aes256, zipCrypto }

    public var format: Format = .zip
    public var level: Level = .normal
    /// 保存はしない（その作業の間だけ持つ）
    public var password: String = ""
    public var zipCipher: ZipCipher = .aes256
    /// 1つの大きさ（バイト）。nil は分割しない
    public var splitSize: UInt64?
    /// 日本語の名前をShift_JISで書く（zipのみ。分割とは同時に使えない）
    public var windowsNames: Bool = false
    /// .DS_Store・__MACOSX・._ ファイルを入れない
    public var excludeMacFiles: Bool = true

    public init() {}

    public var fileExtension: String { format.fileExtension }

    enum CodingKeys: String, CodingKey { case format, level, zipCipher, splitSize, windowsNames, excludeMacFiles }
}

public enum SevenZipError: Error, Equatable, LocalizedError {
    case notFound
    case needsPassword
    case wrongPassword
    case cancelled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: return tr("圧縮・解凍の部品（7-Zip）が見つかりません。アプリを入れ直してください。",
                                  "The compression engine (7-Zip) is missing. Please reinstall the app.")
        case .needsPassword: return tr("パスワードが必要です。", "A password is required.")
        case .wrongPassword: return tr("パスワードが違います。", "The password is incorrect.")
        case .cancelled: return tr("中止しました。", "Cancelled.")
        case .failed(let detail): return tr("うまくいきませんでした。", "Something went wrong.") + "\n" + detail
        }
    }
}

/// 同梱の 7-Zip（7zz）を呼ぶ係
public struct SevenZip: Sendable {
    public let executable: URL

    public init(executable: URL) { self.executable = executable }

    /// アプリに同梱した 7zz を探す
    public static func bundled() -> SevenZip? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "7zz"),
           FileManager.default.fileExists(atPath: url.path) {
            return SevenZip(executable: url)
        }
        if let env = ProcessInfo.processInfo.environment["ZIPPEEK_7ZZ"],
           FileManager.default.isExecutableFile(atPath: env) {
            return SevenZip(executable: URL(fileURLWithPath: env))
        }
        return nil
    }

    // MARK: - 一覧

    public func list(_ archive: URL, password: String?) throws -> [RawEntry] {
        let out = try run(["l", "-slt", "-ba", "-sccUTF-8", "-p" + (password ?? ""), archive.standardizedFileURL.path],
                          password: password)
        return Self.parseList(out.stdout)
    }

    /// `7zz l -slt` の出力を読む
    public static func parseList(_ text: String) -> [RawEntry] {
        var result: [RawEntry] = []
        var cur: [String: String] = [:]
        func flush() {
            guard let path = cur["Path"], !path.isEmpty else { cur = [:]; return }
            let isDir = cur["Folder"] == "+" || (cur["Attributes"]?.hasPrefix("D") ?? false)
            result.append(RawEntry(
                path: path, isDirectory: isDir,
                size: UInt64(cur["Size"] ?? "") ?? 0,
                packedSize: UInt64(cur["Packed Size"] ?? "") ?? 0,
                modified: parseDate(cur["Modified"] ?? ""),
                isEncrypted: cur["Encrypted"] == "+",
                entryIndex: nil, archivePath: path))
            cur = [:]
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if l.isEmpty { flush(); continue }
            guard let eq = l.range(of: " = ") else {
                if l.hasSuffix(" =") { cur[String(l.dropLast(2))] = "" }
                continue
            }
            let key = String(l[..<eq.lowerBound])
            if key == "Path", cur["Path"] != nil { flush() }
            cur[key] = String(l[eq.upperBound...])
        }
        flush()
        return result
    }

    static func parseDate(_ s: String) -> Date? {
        // 例: 2026-10-25 19:23:08.4552120
        let head = String(s.prefix(19))
        guard head.count == 19 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: head)
    }

    // MARK: - 解凍

    /// 全部または一部を destination に解凍する（destination は空のフォルダを渡す）
    public func extract(_ archive: URL, to destination: URL, password: String?, only paths: [String]? = nil,
                        onProgress: @escaping @Sendable (Double) -> Void = { _ in },
                        isCancelled: @escaping @Sendable () -> Bool = { false }) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var args = ["x", "-y", "-sccUTF-8", "-bsp1", "-bso0", "-bse2", "-o" + destination.path,
                    "-p" + (password ?? "")]
        var listFile: URL?
        if let paths, !paths.isEmpty {
            let lf = FileManager.default.temporaryDirectory.appendingPathComponent("zippeek-\(UUID().uuidString).txt")
            try paths.joined(separator: "\n").write(to: lf, atomically: true, encoding: .utf8)
            listFile = lf
            args += ["-spd", "-scsUTF-8"]
            // 「--」を付けると @リスト がファイル名扱いになるので付けない（パスは必ず / から始まる）
            args += [archive.standardizedFileURL.path, "@" + lf.path]
        } else {
            args += [archive.standardizedFileURL.path]
        }
        defer { if let lf = listFile { try? FileManager.default.removeItem(at: lf) } }
        _ = try run(args, password: password, onProgress: onProgress, isCancelled: isCancelled)
    }

    // MARK: - 圧縮

    /// inputs をまとめて output に圧縮する。分割のときは output.001 … ができる
    public func compress(_ inputs: [URL], to output: URL, options: CompressOptions,
                         onProgress: @escaping @Sendable (Double) -> Void = { _ in },
                         isCancelled: @escaping @Sendable () -> Bool = { false }) throws {
        guard let first = inputs.first else { return }
        var args = ["a", "-t" + (options.format == .zip ? "zip" : "7z"), "-sccUTF-8", "-bsp1", "-bso0", "-bse2"]
        switch options.level {
        case .fast: args.append("-mx=1")
        case .normal: args.append("-mx=5")
        case .max: args.append("-mx=9")
        }
        if !options.password.isEmpty {
            args.append("-p" + options.password)
            if options.format == .zip {
                args.append(options.zipCipher == .aes256 ? "-mem=AES256" : "-mem=ZipCrypto")
            } else {
                args.append("-mhe=on") // 7zはファイル名も隠す
            }
        }
        if let split = options.splitSize, split > 0, !options.windowsNames {
            args.append("-v\(split)b")
        }
        if options.excludeMacFiles {
            args += ["-xr!.DS_Store", "-xr!__MACOSX", "-xr!._*", "-xr!.Spotlight-V100", "-xr!.Trashes", "-xr!.fseventsd"]
        }
        // 同じフォルダにあるものは名前だけで渡し、中のフォルダ構造を素直に保つ
        let parent = first.deletingLastPathComponent().standardizedFileURL
        let sameParent = inputs.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL == parent }
        let names = sameParent ? inputs.map(\.lastPathComponent) : inputs.map(\.path)
        args += ["--", output.path] + names
        _ = try run(args, password: nil, cwd: sameParent ? parent : nil, onProgress: onProgress, isCancelled: isCancelled)
    }

    // MARK: - 実行

    public struct Output: Sendable {
        public let stdout: String
        public let stderr: String
        public let status: Int32
    }

    @discardableResult
    public func run(_ args: [String], password: String?, cwd: URL? = nil,
                    onProgress: @escaping @Sendable (Double) -> Void = { _ in },
                    isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> Output {
        // サンドボックスの中では「実行できるか」の問い合わせだけ断られることがあるので、有無だけ確かめて実際に起動してみる
        guard FileManager.default.fileExists(atPath: executable.path) else { throw SevenZipError.notFound }
        let p = Process()
        p.executableURL = executable
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        // 日本語の名前を正しく扱わせるため、文字コードをUTF-8に固定する
        #if os(macOS)
        env["LC_ALL"] = "en_US.UTF-8"
        #else
        env["LC_ALL"] = "C.UTF-8"
        #endif
        p.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice

        let collector = OutputCollector(onProgress: onProgress)
        outPipe.fileHandleForReading.readabilityHandler = { h in collector.appendOut(h.availableData) }
        errPipe.fileHandleForReading.readabilityHandler = { h in collector.appendErr(h.availableData) }

        try p.run()
        var cancelled = false
        while p.isRunning {
            if isCancelled() {
                cancelled = true
                p.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.08)
        }
        p.waitUntilExit()
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        collector.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
        collector.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
        let out = collector.result(status: p.terminationStatus)

        if cancelled || out.status == 255 { throw SevenZipError.cancelled }
        let err = out.stderr + "\n" + out.stdout
        if err.contains("Wrong password") || err.contains("Cannot open encrypted archive") {
            throw (password ?? "").isEmpty ? SevenZipError.needsPassword : SevenZipError.wrongPassword
        }
        // 0 = 成功、1 = 警告（一部のファイルを読めなかった等。結果は使える）
        guard out.status == 0 || out.status == 1 else {
            let detail = out.stderr.split(separator: "\n").filter { !String($0).trimmingCharacters(in: CharacterSet.whitespaces).isEmpty }
                .suffix(4).joined(separator: "\n")
            throw SevenZipError.failed(detail.isEmpty ? "(7-Zip exit \(out.status))" : detail)
        }
        onProgress(1)
        return out
    }

    /// 進み具合の表示（例: " 45% 3 - clip.bin"）から割合を取り出す
    public static func parseProgress(_ chunk: String) -> Double? {
        var last: Double?
        var digits = ""
        for ch in chunk {
            if ch.isNumber { digits.append(ch) }
            else {
                if ch == "%", let v = Double(digits), v <= 100 { last = v / 100 }
                digits = ""
            }
        }
        return last
    }
}

/// 別の作業列から書き込まれる出力をまとめる
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

    func appendOut(_ d: Data) {
        guard !d.isEmpty else { return }
        lock.lock(); out.append(d); lock.unlock()
        if let s = String(data: d, encoding: .utf8), let v = SevenZip.parseProgress(s) { onProgress(v) }
    }

    func appendErr(_ d: Data) {
        guard !d.isEmpty else { return }
        lock.lock(); err.append(d); lock.unlock()
    }

    func result(status: Int32) -> SevenZip.Output {
        lock.lock(); defer { lock.unlock() }
        return SevenZip.Output(stdout: String(decoding: out, as: UTF8.self),
                               stderr: String(decoding: err, as: UTF8.self), status: status)
    }
}
