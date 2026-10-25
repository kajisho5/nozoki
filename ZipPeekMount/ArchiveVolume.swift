import Darwin
import Foundation
import FSKit
import ZipPeekCore

/// ドライブの中の1項目（ファイルかフォルダ）
final class ArchiveFSItem: FSItem {
    let id: UInt64
    let name: String
    let isDirectory: Bool
    let size: UInt64
    let modified: Date?
    /// 圧縮ファイルの中での道筋（ルートは ""）
    let path: String
    let source: ArchiveItem?
    weak var parent: ArchiveFSItem?
    var children: [String: ArchiveFSItem] = [:]
    var orderedChildren: [ArchiveFSItem] = []
    /// 取り出したもの（開かれたときに作る）
    var cached: URL?

    init(id: UInt64, name: String, isDirectory: Bool, size: UInt64, modified: Date?, path: String, source: ArchiveItem?) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.path = path
        self.source = source
        super.init()
    }
}

/// 圧縮ファイル1つ分のドライブ（読み取り専用）
final class ArchiveVolume: FSVolume, FSVolume.ReadWriteOperations, FSVolume.OpenCloseOperations {
    let archive: URL
    let listing: ArchiveListing
    let root: ArchiveFSItem
    private var items: [UInt64: ArchiveFSItem] = [:]
    private let lock = NSLock()
    private let cacheFolder: URL

    init(archive: URL) throws {
        self.archive = archive
        // 目次だけ読む（zip は自前で、それ以外は OS の libarchive で）
        if ArchiveKind.isZip(archive), let l = try? ArchiveListing.load(url: archive) {
            listing = l
        } else {
            listing = ArchiveListing.build(raw: try LibArchive.entries(archive))
        }
        cacheFolder = FileManager.default.temporaryDirectory.appendingPathComponent("mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        root = ArchiveFSItem(id: FSItem.Identifier.rootDirectory.rawValue, name: "", isDirectory: true, size: 0,
                             modified: nil, path: "", source: nil)
        super.init(volumeID: FSVolume.Identifier(uuid: UUID()),
                   volumeName: FSFileName(string: ArchiveKind.baseName(of: archive)))
        items[root.id] = root
        var next: UInt64 = 100
        func build(_ dir: ArchiveFSItem) {
            for item in listing.items(in: dir.path) {
                let child = ArchiveFSItem(id: next, name: item.name, isDirectory: item.isFolder,
                                          size: item.isFolder ? 0 : item.size, modified: item.modified,
                                          path: item.path, source: item)
                next += 1
                child.parent = dir
                dir.children[item.name] = child
                dir.orderedChildren.append(child)
                items[child.id] = child
                if item.isFolder { build(child) }
            }
        }
        build(root)
    }

    deinit { try? FileManager.default.removeItem(at: cacheFolder) }

    // MARK: 属性

    private func attributes(of item: ArchiveFSItem) -> FSItem.Attributes {
        let a = FSItem.Attributes()
        a.type = item.isDirectory ? .directory : .file
        a.mode = item.isDirectory ? UInt32(S_IFDIR | 0o555) : UInt32(S_IFREG | 0o444)
        a.linkCount = item.isDirectory ? 2 : 1
        a.uid = getuid()
        a.gid = getgid()
        a.size = item.size
        a.allocSize = item.size
        a.fileID = FSItem.Identifier(rawValue: item.id) ?? .invalid
        a.parentID = item.parent.flatMap { FSItem.Identifier(rawValue: $0.id) } ?? .parentOfRoot
        let t = item.modified ?? (try? archive.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        var ts = timespec()
        ts.tv_sec = Int(t.timeIntervalSince1970)
        a.modifyTime = ts
        a.changeTime = ts
        a.accessTime = ts
        a.birthTime = ts
        return a
    }

    /// 中身を取り出して、読める場所を返す（同じファイルは1回だけ）
    private func materialize(_ item: ArchiveFSItem) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        if let c = item.cached { return c }
        guard let source = item.source else { throw POSIXError(.EISDIR) }
        let dest = cacheFolder.appendingPathComponent(String(item.id), isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let out: URL
        if listing.source == .zip, let index = source.entryIndex, !source.isEncrypted {
            let job = Extractor.Job(entryIndex: index, name: source.name, size: source.size, isEncrypted: false, relativePath: source.name)
            guard let w = try Extractor(zipURL: archive).extract([job], into: dest).first else { throw POSIXError(.EIO) }
            out = w
        } else {
            try LibArchive.extract(archive, to: dest, only: [ArchiveListing.normalize(source.archivePath ?? source.path)])
            out = dest.appendingPathComponent(ArchiveListing.normalize(source.archivePath ?? source.path))
        }
        item.cached = out
        return out
    }
}

extension ArchiveVolume: FSVolume.Operations {
    var supportedVolumeCapabilities: FSVolume.SupportedCapabilities {
        let c = FSVolume.SupportedCapabilities()
        c.supportsPersistentObjectIDs = true
        c.supports64BitObjectIDs = true
        c.supportsFastStatFS = true
        c.doesNotSupportSettingFilePermissions = true
        c.doesNotSupportImmutableFiles = true
        c.caseFormat = .sensitive
        return c
    }

    var volumeStatistics: FSStatFSResult {
        let r = FSStatFSResult(fileSystemTypeName: "zippeek")
        let total = listing.summary.totalSize
        r.blockSize = 4096
        r.ioSize = 65536
        r.totalBlocks = (total + 4095) / 4096
        r.usedBlocks = r.totalBlocks
        r.availableBlocks = 0
        r.freeBlocks = 0
        r.totalBytes = total
        r.usedBytes = total
        r.totalFiles = UInt64(listing.summary.fileCount + listing.summary.folderCount)
        r.freeFiles = 0
        return r
    }

    var maximumLinkCount: Int { 1 }
    var maximumNameLength: Int { 255 }
    var restrictsOwnershipChanges: Bool { true }
    var truncatesLongNames: Bool { false }

    func activate(options: FSTaskOptions, replyHandler reply: @escaping (FSItem?, (any Error)?) -> Void) {
        reply(root, nil)
    }

    func deactivate(options: FSDeactivateOptions = [], replyHandler reply: @escaping ((any Error)?) -> Void) {
        reply(nil)
    }

    func mount(options: FSTaskOptions, replyHandler reply: @escaping ((any Error)?) -> Void) { reply(nil) }

    func unmount(replyHandler reply: @escaping () -> Void) {
        try? FileManager.default.removeItem(at: cacheFolder)
        reply()
    }

    func synchronize(flags: FSSyncFlags, replyHandler reply: @escaping ((any Error)?) -> Void) { reply(nil) }

    func getAttributes(_ desiredAttributes: FSItem.GetAttributesRequest, of item: FSItem,
                       replyHandler reply: @escaping (FSItem.Attributes?, (any Error)?) -> Void) {
        guard let i = item as? ArchiveFSItem else { return reply(nil, POSIXError(.EINVAL)) }
        reply(attributes(of: i), nil)
    }

    func setAttributes(_ newAttributes: FSItem.SetAttributesRequest, on item: FSItem,
                       replyHandler reply: @escaping (FSItem.Attributes?, (any Error)?) -> Void) {
        reply(nil, POSIXError(.EROFS))
    }

    func lookupItem(named name: FSFileName, inDirectory directory: FSItem,
                    replyHandler reply: @escaping (FSItem?, FSFileName?, (any Error)?) -> Void) {
        guard let dir = directory as? ArchiveFSItem, let n = name.string else { return reply(nil, nil, POSIXError(.EINVAL)) }
        // Finder の名前は濁点が分かれた形のこともあるので、まとめた形でも探す
        guard let child = dir.children[n] ?? dir.children[n.precomposedStringWithCanonicalMapping]
                ?? dir.children.first(where: { $0.key.precomposedStringWithCanonicalMapping == n.precomposedStringWithCanonicalMapping })?.value
        else { return reply(nil, nil, POSIXError(.ENOENT)) }
        reply(child, FSFileName(string: child.name), nil)
    }

    func reclaimItem(_ item: FSItem, replyHandler reply: @escaping ((any Error)?) -> Void) { reply(nil) }

    func readSymbolicLink(_ item: FSItem, replyHandler reply: @escaping (FSFileName?, (any Error)?) -> Void) {
        reply(nil, POSIXError(.EINVAL))
    }

    func createItem(named name: FSFileName, type: FSItem.ItemType, inDirectory directory: FSItem,
                    attributes newAttributes: FSItem.SetAttributesRequest,
                    replyHandler reply: @escaping (FSItem?, FSFileName?, (any Error)?) -> Void) {
        reply(nil, nil, POSIXError(.EROFS))
    }

    func createSymbolicLink(named name: FSFileName, inDirectory directory: FSItem, attributes newAttributes: FSItem.SetAttributesRequest,
                            linkContents contents: FSFileName,
                            replyHandler reply: @escaping (FSItem?, FSFileName?, (any Error)?) -> Void) {
        reply(nil, nil, POSIXError(.EROFS))
    }

    func createLink(to item: FSItem, named name: FSFileName, inDirectory directory: FSItem,
                    replyHandler reply: @escaping (FSFileName?, (any Error)?) -> Void) {
        reply(nil, POSIXError(.EROFS))
    }

    func removeItem(_ item: FSItem, named name: FSFileName, fromDirectory directory: FSItem,
                    replyHandler reply: @escaping ((any Error)?) -> Void) {
        reply(POSIXError(.EROFS))
    }

    func renameItem(_ item: FSItem, inDirectory sourceDirectory: FSItem, named sourceName: FSFileName, to destinationName: FSFileName,
                    inDirectory destinationDirectory: FSItem, overItem: FSItem?,
                    replyHandler reply: @escaping (FSFileName?, (any Error)?) -> Void) {
        reply(nil, POSIXError(.EROFS))
    }

    func enumerateDirectory(_ directory: FSItem, startingAt cookie: FSDirectoryCookie, verifier: FSDirectoryVerifier,
                            attributes: FSItem.GetAttributesRequest?, packer: FSDirectoryEntryPacker,
                            replyHandler reply: @escaping (FSDirectoryVerifier, (any Error)?) -> Void) {
        guard let dir = directory as? ArchiveFSItem, dir.isDirectory else { return reply(FSDirectoryVerifier(0), POSIXError(.ENOTDIR)) }
        let start = Int(cookie.rawValue)
        guard start < dir.orderedChildren.count else { return reply(FSDirectoryVerifier(1), nil) }
        for (i, child) in dir.orderedChildren.enumerated() where i >= start {
            let ok = packer.packEntry(name: FSFileName(string: child.name), itemType: child.isDirectory ? .directory : .file,
                                      itemID: FSItem.Identifier(rawValue: child.id) ?? .invalid,
                                      nextCookie: FSDirectoryCookie(UInt64(i + 1)),
                                      attributes: attributes == nil ? nil : self.attributes(of: child))
            if !ok { break }
        }
        reply(FSDirectoryVerifier(1), nil)
    }
}

extension ArchiveVolume {
    func read(from item: FSItem, at offset: off_t, length: Int, into buffer: FSMutableFileDataBuffer,
              replyHandler reply: @escaping (Int, (any Error)?) -> Void) {
        guard let i = item as? ArchiveFSItem, !i.isDirectory else { return reply(0, POSIXError(.EISDIR)) }
        if offset >= off_t(i.size) { return reply(0, nil) }
        do {
            let file = try materialize(i)
            let fd = Darwin.open(file.path, O_RDONLY)
            guard fd >= 0 else { return reply(0, POSIXError(.EIO)) }
            defer { close(fd) }
            var got = 0
            buffer.withUnsafeMutableBytes { raw in got = pread(fd, raw.baseAddress, min(length, raw.count), offset) }
            reply(max(got, 0), got < 0 ? POSIXError(.EIO) : nil)
        } catch {
            reply(0, error)
        }
    }

    func write(contents: Data, to item: FSItem, at offset: off_t, replyHandler reply: @escaping (Int, (any Error)?) -> Void) {
        reply(0, POSIXError(.EROFS))
    }

    func openItem(_ item: FSItem, modes: FSVolume.OpenModes, replyHandler reply: @escaping ((any Error)?) -> Void) {
        if modes.contains(.write) { return reply(POSIXError(.EROFS)) }
        reply(nil)
    }

    func closeItem(_ item: FSItem, modes: FSVolume.OpenModes, replyHandler reply: @escaping ((any Error)?) -> Void) {
        reply(nil)
    }
}
