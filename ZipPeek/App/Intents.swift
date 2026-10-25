import AppIntents
import Foundation
import UniformTypeIdentifiers
import ZipPeekCore

// ショートカット App から使える操作（圧縮・解凍・中身の一覧・壊れていないかの確認）。
// どれも窓を開かずに動く

/// 圧縮の形式（ショートカットで選ぶ）
enum IntentFormat: String, AppEnum {
    case zip, sevenZip, tarGz, tarXz, tarBz2, dmg

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Archive Format"
    static let caseDisplayRepresentations: [IntentFormat: DisplayRepresentation] = [
        .zip: "zip", .sevenZip: "7z", .tarGz: "tar.gz", .tarXz: "tar.xz", .tarBz2: "tar.bz2", .dmg: "dmg",
    ]

    var format: CompressOptions.Format {
        switch self {
        case .zip: .zip
        case .sevenZip: .sevenZip
        case .tarGz: .tarGz
        case .tarXz: .tarXz
        case .tarBz2: .tarBz2
        case .dmg: .dmg
        }
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noFile, engine, message(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noFile: "ZipPeek couldn’t find the file. Pass a file from Finder or another action."
        case .engine: "The compression engine (7-Zip) is missing. Please reinstall the app."
        case .message(let m): "\(m)"
        }
    }
}

/// ショートカットから渡されたファイルの場所。場所が無い（データだけの）ときは一時フォルダに書き出す
private func localURL(_ file: IntentFile) throws -> URL {
    if let url = file.fileURL { return url }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ZipPeek/\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(file.filename.isEmpty ? "file" : file.filename)
    try file.data.write(to: url)
    return url
}

struct CompressFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Compress Files"
    static let description = IntentDescription("Compresses files and folders into one archive next to the first item.")

    @Parameter(title: "Files", supportedContentTypes: [.item])
    var files: [IntentFile]

    @Parameter(title: "Format", default: .zip)
    var format: IntentFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Compress \(\.$files) as \(\.$format)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let inputs = try files.map(localURL)
        guard !inputs.isEmpty else { throw IntentError.noFile }
        var options = await MainActor.run { Preferences.shared.compressDefaults }
        options.format = format.format
        options.password = ""
        if !options.format.supportsSplit { options.splitSize = nil }
        let engine = ArchiveOperations(sevenZip: SevenZip.bundled())
        let made: [URL]
        do { made = try engine.compress(inputs, options: options) } catch { throw IntentError.message(error.localizedDescription) }
        guard let first = made.first else { throw IntentError.noFile }
        return .result(value: IntentFile(fileURL: first))
    }
}

struct ExtractArchiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Extract Archive"
    static let description = IntentDescription("Extracts an archive next to it and returns what was extracted.")

    @Parameter(title: "Archive", supportedContentTypes: [.item])
    var archive: IntentFile

    static var parameterSummary: some ParameterSummary { Summary("Extract \(\.$archive)") }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let url = try localURL(archive)
        let engine = ArchiveOperations(sevenZip: SevenZip.bundled())
        let folder = url.deletingLastPathComponent()
        let group = await MainActor.run { Preferences.shared.groupIntoFolder }
        let made: [URL]
        do {
            made = try engine.extractAll(url, into: folder, password: nil, groupIntoFolder: group)
        } catch { throw IntentError.message(error.localizedDescription) }
        return .result(value: made.map { IntentFile(fileURL: $0) })
    }
}

struct ListArchiveContentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Contents of Archive"
    static let description = IntentDescription("Lists the files inside an archive without extracting it.")

    @Parameter(title: "Archive", supportedContentTypes: [.item])
    var archive: IntentFile

    static var parameterSummary: some ParameterSummary { Summary("Get contents of \(\.$archive)") }

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let url = try localURL(archive)
        let listing: ArchiveListing
        do {
            if ArchiveKind.isZip(url), let l = try? ArchiveListing.load(url: url) {
                listing = l
            } else if LibArchive.handles(url) {
                listing = ArchiveListing.build(raw: try LibArchive.entries(url))
            } else {
                guard let sevenZip = SevenZip.bundled() else { throw IntentError.engine }
                listing = ArchiveListing.build(raw: try sevenZip.list(url, password: nil))
            }
        } catch let e as IntentError { throw e } catch { throw IntentError.message(error.localizedDescription) }
        return .result(value: listing.allFiles.map(\.path))
    }
}

struct CheckArchiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Archive for Damage"
    static let description = IntentDescription("Reads every file in the archive and reports whether it’s damaged. Nothing is extracted.")

    @Parameter(title: "Archive", supportedContentTypes: [.item])
    var archive: IntentFile

    static var parameterSummary: some ParameterSummary { Summary("Check \(\.$archive) for damage") }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let url = try localURL(archive)
        guard let sevenZip = SevenZip.bundled() else { throw IntentError.engine }
        do { return .result(value: try ArchiveTest.run(url, password: nil, sevenZip: sevenZip).ok) }
        catch { throw IntentError.message(error.localizedDescription) }
    }
}

struct ZipPeekShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CompressFilesIntent(), phrases: ["Compress files with \(.applicationName)"],
                    shortTitle: "Compress Files", systemImageName: "archivebox")
        AppShortcut(intent: ExtractArchiveIntent(), phrases: ["Extract an archive with \(.applicationName)"],
                    shortTitle: "Extract Archive", systemImageName: "arrow.down.doc")
        AppShortcut(intent: ListArchiveContentsIntent(), phrases: ["Look inside an archive with \(.applicationName)"],
                    shortTitle: "Get Contents", systemImageName: "list.bullet.rectangle")
        AppShortcut(intent: CheckArchiveIntent(), phrases: ["Check an archive with \(.applicationName)"],
                    shortTitle: "Check for Damage", systemImageName: "checkmark.shield")
    }
}
