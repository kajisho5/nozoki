import Foundation
import FSKit
import ZipPeekCore

/// 圧縮ファイルを、Finder からドライブのように見せる（読み取り専用）。
/// `mount -t zippeek <圧縮ファイル> <つなぐ場所>` で呼ばれる。中身は開かれたときに、そのファイルだけ取り出す
@main
struct ZipPeekMountExtension: UnaryFileSystemExtension {
    typealias FileSystem = FSUnaryFileSystem & FSUnaryFileSystemOperations

    var fileSystem: FSUnaryFileSystem & FSUnaryFileSystemOperations {
        ArchiveFileSystem()
    }
}

@objc
final class ArchiveFileSystem: FSUnaryFileSystem & FSUnaryFileSystemOperations {
    private var resource: FSPathURLResource?

    override init() {}

    func probeResource(resource: FSResource, replyHandler: @escaping (FSProbeResult?, (any Error)?) -> Void) {
        guard let r = resource as? FSPathURLResource else { return replyHandler(nil, POSIXError(.ENODEV)) }
        guard ArchiveKind.isArchive(r.url) else { return replyHandler(FSProbeResult.notRecognized, nil) }
        let name = ArchiveKind.baseName(of: r.url)
        replyHandler(FSProbeResult.usable(name: name, containerID: FSContainerIdentifier(uuid: UUID())), nil)
    }

    func loadResource(resource: FSResource, options: FSTaskOptions, replyHandler: @escaping (FSVolume?, (any Error)?) -> Void) {
        guard let r = resource as? FSPathURLResource else { return replyHandler(nil, POSIXError(.EINVAL)) }
        // 書き込み用の初期化（フォーマット）はしない
        if options.taskOptions.contains(where: { $0.contains("-f") }) { return replyHandler(nil, POSIXError(.ENOTSUP)) }
        let scoped = r.url.startAccessingSecurityScopedResource()
        do {
            let volume = try ArchiveVolume(archive: r.url)
            self.resource = r
            containerStatus = .ready
            replyHandler(volume, nil)
        } catch {
            if scoped { r.url.stopAccessingSecurityScopedResource() }
            replyHandler(nil, error)
        }
    }

    func unloadResource(resource: FSResource, options: FSTaskOptions, replyHandler reply: @escaping ((any Error)?) -> Void) {
        (resource as? FSPathURLResource)?.url.stopAccessingSecurityScopedResource()
        self.resource = nil
        reply(nil)
    }
}
