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
                Text(inputs.count == 1 ? String(localized: "Compress “\(inputs[0].lastPathComponent)”")
                                       : String(localized: "Compress \(inputs.count) items"))
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Text(String(localized: "Save to: ") + ArchiveModel.displayPath(inputs[0].deletingLastPathComponent())
                     + "/" + ArchiveOperations.archiveName(for: inputs, options: options))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }

            Form {
                Picker(String(localized: "Format"), selection: $options.format) {
                    Text(verbatim: "zip").tag(CompressOptions.Format.zip)
                    Text(verbatim: "7z").tag(CompressOptions.Format.sevenZip)
                }
                .pickerStyle(.segmented)

                Picker(String(localized: "Compression Level"), selection: $options.level) {
                    Text(String(localized: "Faster")).tag(CompressOptions.Level.fast)
                    Text(String(localized: "Normal")).tag(CompressOptions.Level.normal)
                    Text(String(localized: "Smallest")).tag(CompressOptions.Level.max)
                }
                .pickerStyle(.segmented)

                SecureField(String(localized: "Password"), text: $options.password,
                            prompt: Text(String(localized: "Leave empty for none")))
                if options.format == .zip && !options.password.isEmpty {
                    Picker(String(localized: "Encryption"), selection: $options.zipCipher) {
                        Text(String(localized: "AES-256 (strong, recommended)")).tag(CompressOptions.ZipCipher.aes256)
                        Text(String(localized: "ZipCrypto (opens on stock Windows, weak)")).tag(CompressOptions.ZipCipher.zipCrypto)
                    }
                }
                if options.format == .sevenZip && !options.password.isEmpty {
                    Text(String(localized: "With 7z, file names are hidden too."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Picker(String(localized: "Split"), selection: $splitChoice) {
                    Text(String(localized: "Don’t split")).tag(SplitChoice.none)
                    Text(verbatim: "2 GB").tag(SplitChoice.gb2)
                    Text(String(localized: "4.7 GB (DVD)")).tag(SplitChoice.dvd)
                    Text(String(localized: "Custom size")).tag(SplitChoice.custom)
                }
                .disabled(options.format == .zip && options.windowsNames)
                if splitChoice == .custom {
                    HStack {
                        TextField(String(localized: "Size of each part"), value: $customSplitMB, format: .number)
                        Text(verbatim: "MB").foregroundStyle(.secondary)
                    }
                }

                if options.format == .zip {
                    Toggle(isOn: $options.windowsNames) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(localized: "Use Japanese Windows–friendly names"))
                            Text(String(localized: "Writes Japanese names in Shift_JIS (can’t be combined with splitting)"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(String(localized: "Leave out Mac-only hidden files (.DS_Store etc.)"),
                       isOn: $options.excludeMacFiles)
                Toggle(String(localized: "Don’t ask next time; use these settings"), isOn: $dontAskAgain)
            }
            .formStyle(.grouped)

            HStack {
                if dontAskAgain {
                    Text(String(localized: "Hold Option while dropping to see this again"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Compress")) { finish() }
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
            // 間違いは色だけでなく記号と文言でも示す
            Image(systemName: wasWrong ? "exclamationmark.lock.fill" : "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(wasWrong ? Color.orange : Color.accentColor)
                .accessibilityHidden(true)
            Text(wasWrong ? String(localized: "Incorrect password. Try again.") : String(localized: "Password Required"))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(String(localized: "“\(fileName)”")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            SecureField(String(localized: "Password"), text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { if !password.isEmpty { onFinish(password) } }
            HStack {
                Text(String(localized: "Passwords are never saved")).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { onFinish(nil) }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Continue")) { onFinish(password) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)
            }
        }
        .padding(22)
        .padding(.top, 10)
        .frame(width: 360)
        .onAppear { focused = true }
    }
}
