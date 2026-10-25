import AppKit
import Observation
import ZipPeekCore

/// アプリの設定（Macの標準の設定保存 UserDefaults に保存する）。パスワードは保存しない
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    enum ArchiveDropAction: String, CaseIterable { case extract, browse }
    enum ExtractDestination: String, CaseIterable { case sameFolder, ask }
    enum Appearance: String, CaseIterable { case system, light, dark }
    enum DropStyle: String, CaseIterable { case window, compactGlass }

    private let d = UserDefaults.standard

    /// 圧縮ファイルを渡されたとき（標準：すぐ解凍）
    var onArchiveDrop: ArchiveDropAction { didSet { d.set(onArchiveDrop.rawValue, forKey: "onArchiveDrop") } }
    var extractTo: ExtractDestination { didSet { d.set(extractTo.rawValue, forKey: "extractTo") } }
    /// 中身が複数ならフォルダにまとめる
    var groupIntoFolder: Bool { didSet { d.set(groupIntoFolder, forKey: "groupIntoFolder") } }
    var revealWhenDone: Bool { didSet { d.set(revealWhenDone, forKey: "revealWhenDone") } }
    /// 解凍したら元の圧縮ファイルをゴミ箱へ（完全には消さない）
    var trashAfterExtract: Bool { didSet { d.set(trashAfterExtract, forKey: "trashAfterExtract") } }
    /// 圧縮のたびに設定シートを出す
    var askBeforeCompress: Bool { didSet { d.set(askBeforeCompress, forKey: "askBeforeCompress") } }
    /// 圧縮の標準設定（パスワードは含めない）
    var compressDefaults: CompressOptions {
        didSet { if let data = try? JSONEncoder().encode(compressDefaults) { d.set(data, forKey: "compressDefaults") } }
    }
    var appearance: Appearance { didSet { d.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }
    var dropStyle: DropStyle { didSet { d.set(dropStyle.rawValue, forKey: "dropStyle") } }
    var hasSeenWelcome: Bool { didSet { d.set(hasSeenWelcome, forKey: "hasSeenWelcome") } }

    private init() {
        onArchiveDrop = ArchiveDropAction(rawValue: d.string(forKey: "onArchiveDrop") ?? "") ?? .extract
        extractTo = ExtractDestination(rawValue: d.string(forKey: "extractTo") ?? "") ?? .sameFolder
        groupIntoFolder = d.object(forKey: "groupIntoFolder") as? Bool ?? true
        revealWhenDone = d.object(forKey: "revealWhenDone") as? Bool ?? true
        trashAfterExtract = d.object(forKey: "trashAfterExtract") as? Bool ?? false
        askBeforeCompress = d.object(forKey: "askBeforeCompress") as? Bool ?? true
        if let data = d.data(forKey: "compressDefaults"), let o = try? JSONDecoder().decode(CompressOptions.self, from: data) {
            compressDefaults = o
        } else {
            compressDefaults = CompressOptions()
        }
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        dropStyle = DropStyle(rawValue: d.string(forKey: "dropStyle") ?? "") ?? .window
        hasSeenWelcome = d.bool(forKey: "hasSeenWelcome")
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
