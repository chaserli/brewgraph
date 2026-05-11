import SwiftUI

private struct CardWithAccentBar: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.10), Color.primary.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint.opacity(0.6))
                    .frame(width: 3)
                    .padding(.vertical, 12)
                    .padding(.leading, 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.18))
            }
    }
}

private struct AttentionBackground: ViewModifier {
    let tint: Color
    let active: Bool

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [tint.opacity(active ? 0.16 : 0.08), Color.primary.opacity(0.025)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint.opacity(0.5))
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .padding(.leading, 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(active ? 0.28 : 0.12))
            }
    }
}

extension View {
    func cardWithAccentBar(tint: Color) -> some View {
        modifier(CardWithAccentBar(tint: tint))
    }

    func attentionBackground(tint: Color, active: Bool) -> some View {
        modifier(AttentionBackground(tint: tint, active: active))
    }
}
