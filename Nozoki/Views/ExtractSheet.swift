import NozokiCore
import SwiftUI

/// 取り出し中シート（デザイン③）
struct ExtractSheet: View {
    @Bindable var model: ArchiveModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let e = model.extraction
            VStack(alignment: .leading, spacing: 12) {
                Text(e?.isForPreview == true ? "プレビューの準備中" : "取り出し中")
                    .font(.headline)
                if let e {
                    Text(e.fileTotal > 1 ? "\(e.currentName)（\(e.fileNumber) / \(e.fileTotal) 件目）" : e.currentName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ProgressView(value: e.fraction)
                    HStack {
                        Text("\(ByteFormat.string(e.doneBytes)) / \(ByteFormat.string(e.totalBytes))")
                            .monospacedDigit()
                        Spacer()
                        Text(Self.remainingText(e.remainingSeconds))
                            .foregroundStyle(.secondary)
                    }
                    if !e.isForPreview {
                        Text("保存先：\(e.destinationLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                HStack {
                    Spacer()
                    Button("中止", role: .cancel) { model.cancelExtraction() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: 400)
        }
    }

    static func remainingText(_ seconds: Double?) -> String {
        guard let s = seconds else { return "残り時間を計算中…" }
        if s < 60 { return "残り 約 \(max(1, Int(s.rounded()))) 秒" }
        if s < 3600 { return "残り 約 \(Int((s / 60).rounded())) 分" }
        return String(format: "残り 約 %.1f 時間", s / 3600)
    }
}
