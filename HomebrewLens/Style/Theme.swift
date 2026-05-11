import SwiftUI

enum AppTheme {
    static let cornerRadius: CGFloat = 10
    static let compactCornerRadius: CGFloat = 7
    static let sidebarWidth: CGFloat = 300
    static let inspectorWidth: CGFloat = 340
    static let subtleStroke = Color.secondary.opacity(0.18)
    static let mutedFill = Color.secondary.opacity(0.08)
    static let warningFill = Color.orange.opacity(0.12)
    static let cellPadding = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)

    static let formulaColor = Color.blue
    static let caskColor = Color.teal
    static let requestedColor = Color.green
    static let dependencyOnlyColor = Color.secondary
    static let externalTapColor = Color.purple
    static let outdatedColor = Color.orange
    static let cleanupColor = Color.mint
    static let dependencyColor = Color.blue.opacity(0.65)
    static let dependentColor = Color.orange.opacity(0.65)
    static let dangerColor = Color.red
    static let successColor = Color.green
    static let leavesColor = Color.green
}

// MARK: - View Modifiers

struct NativePanel: ViewModifier {
    var subtle: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(subtle ? 12 : 16)
            .background(panelBackground)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.subtleStroke)
            }
    }

    @ViewBuilder
    private var panelBackground: some View {
        if subtle {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        } else {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

struct GradientPanel: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.12), tint.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
    }
}

struct StatCard: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.14), tint.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
    }
}

struct SectionHeader: ViewModifier {
    let systemImage: String
    let tint: Color

    func body(content: Content) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
                .fontWeight(.semibold)
            content
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

extension View {
    func nativePanel(subtle: Bool = false) -> some View {
        modifier(NativePanel(subtle: subtle))
    }

    func gradientPanel(tint: Color) -> some View {
        modifier(GradientPanel(tint: tint))
    }

    func statCard(tint: Color) -> some View {
        modifier(StatCard(tint: tint))
    }

    func sectionHeader(systemImage: String, tint: Color = .secondary) -> some View {
        modifier(SectionHeader(systemImage: systemImage, tint: tint))
    }
}
