import SwiftUI

extension View {
    /// macOS 26以降は Liquid Glass、それより前は従来の半透明（すりガラス風）
    @ViewBuilder
    func zpGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08)))
        }
    }
}

/// 浮かぶガラスの粒（A4の上の帯や作業中の表示に使う）
struct GlassCapsule<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .zpGlass(in: Capsule())
    }
}
