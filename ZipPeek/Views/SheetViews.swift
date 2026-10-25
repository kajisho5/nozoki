import AppKit
import SwiftUI
import ZipPeekCore

/// 圧縮の設定（デザイン⑥）
struct CompressSheetView: View {
    let inputs: [URL]
    let onFinish: (CompressOptions?) -> Void

    @State private var options = Preferences.shared.compressDefaults
    @State private var splitChoice: SplitChoice = .none
    @State private var customSplitMB: Double = 1000
    @State private var dontAskAgain = false

    enum SplitChoice: Hashable { case none, gb2, dvd, custom }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(inputs.count == 1 ? tr("「\(inputs[0].lastPathComponent)」を圧縮", "Compress “\(inputs[0].lastPathComponent)”")
                                       : tr("\(inputs.count) 個の項目を圧縮", "Compress \(inputs.count) items"))
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Text(tr("保存先：", "Save to: ") + ArchiveModel.displayPath(inputs[0].deletingLastPathComponent())
                     + "/" + ArchiveOperations.archiveName(for: inputs, options: options))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }

            Form {
                Picker(tr("形式", "Format"), selection: $options.format) {
                    Text("zip").tag(CompressOptions.Format.zip)
                    Text("7z").tag(CompressOptions.Format.sevenZip)
                }
                .pickerStyle(.segmented)

                Picker(tr("圧縮率", "Compression"), selection: $options.level) {
                    Text(tr("速さ優先", "Faster")).tag(CompressOptions.Level.fast)
                    Text(tr("標準", "Normal")).tag(CompressOptions.Level.normal)
                    Text(tr("最小サイズ", "Smallest")).tag(CompressOptions.Level.max)
                }
                .pickerStyle(.segmented)

                SecureField(tr("パスワード", "Password"), text: $options.password,
                            prompt: Text(tr("付けない場合は空のまま", "Leave empty for none")))
                if options.format == .zip && !options.password.isEmpty {
                    Picker(tr("暗号", "Encryption"), selection: $options.zipCipher) {
                        Text(tr("AES-256（強い・推奨）", "AES-256 (strong, recommended)")).tag(CompressOptions.ZipCipher.aes256)
                        Text(tr("ZipCrypto（Windows標準で開ける・弱い）", "ZipCrypto (opens on stock Windows, weak)")).tag(CompressOptions.ZipCipher.zipCrypto)
                    }
                }
                if options.format == .sevenZip && !options.password.isEmpty {
                    Text(tr("7zでは、ファイル名も見えなくなります。", "With 7z, file names are hidden too."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Picker(tr("分割", "Split"), selection: $splitChoice) {
                    Text(tr("分割しない", "Don’t split")).tag(SplitChoice.none)
                    Text("2 GB").tag(SplitChoice.gb2)
                    Text(tr("4.7 GB（DVD）", "4.7 GB (DVD)")).tag(SplitChoice.dvd)
                    Text(tr("大きさを指定", "Custom size")).tag(SplitChoice.custom)
                }
                .disabled(options.format == .zip && options.windowsNames)
                if splitChoice == .custom {
                    HStack {
                        TextField("MB", value: $customSplitMB, format: .number).frame(width: 90)
                        Text("MB")
                    }
                }

                if options.format == .zip {
                    Toggle(isOn: $options.windowsNames) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tr("Windowsで文字化けしない名前にする", "Use Japanese Windows–friendly names"))
                            Text(tr("日本語の名前をShift_JISで書きます（分割とは同時に使えません）",
                                    "Writes Japanese names in Shift_JIS (can’t be combined with splitting)"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(tr("Mac専用の隠しファイル（.DS_Storeなど）を入れない", "Leave out Mac-only hidden files (.DS_Store etc.)"),
                       isOn: $options.excludeMacFiles)
                Toggle(tr("次回から聞かずに、この設定で圧縮する", "Don’t ask next time; use these settings"), isOn: $dontAskAgain)
            }
            .formStyle(.grouped)

            HStack {
                if dontAskAgain {
                    Text(tr("optionキーを押しながらドラッグすると、また表示されます", "Hold Option while dropping to see this again"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("キャンセル", "Cancel"), role: .cancel) { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(tr("圧縮", "Compress")) { finish() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .padding(.top, 14)
        .frame(width: 500)
        .onAppear {
            switch options.splitSize {
            case nil: splitChoice = .none
            case 2_000_000_000: splitChoice = .gb2
            case 4_700_000_000: splitChoice = .dvd
            case let s?: splitChoice = .custom; customSplitMB = Double(s) / 1_000_000
            }
        }
    }

    private func finish() {
        var o = options
        switch splitChoice {
        case .none: o.splitSize = nil
        case .gb2: o.splitSize = 2_000_000_000
        case .dvd: o.splitSize = 4_700_000_000
        case .custom: o.splitSize = UInt64(max(1, customSplitMB) * 1_000_000)
        }
        if o.format != .zip { o.windowsNames = false }
        // 標準設定として覚える（パスワードは覚えない）
        var saved = o
        saved.password = ""
        Preferences.shared.compressDefaults = saved
        if dontAskAgain { Preferences.shared.askBeforeCompress = false }
        onFinish(o)
    }
}

/// パスワード入力（デザイン⑦）
struct PasswordView: View {
    let fileName: String
    let wasWrong: Bool
    let onFinish: (String?) -> Void
    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(Color.accentColor)
            Text(wasWrong ? tr("パスワードが違います", "Incorrect password") : tr("パスワードが必要です", "Password required"))
                .font(.headline)
                .foregroundStyle(wasWrong ? Color.orange : Color.primary)
            Text("「\(fileName)」").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            SecureField(tr("パスワード", "Password"), text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { onFinish(password) }
            HStack {
                Text(tr("パスワードは保存しません", "Passwords are never saved")).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(tr("やめる", "Cancel"), role: .cancel) { onFinish(nil) }.keyboardShortcut(.cancelAction)
                Button(tr("OK", "OK")) { onFinish(password) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .padding(.top, 10)
        .frame(width: 360)
        .onAppear { focused = true }
    }
}
