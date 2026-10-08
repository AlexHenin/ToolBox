import SwiftUI

enum Layout {
    // The only spacing values used anywhere in the app.
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24

    // Component dimensions are intentionally separate from spacing tokens.
    static let sidebarWidth: CGFloat = 184
    static let sidebarTopInset: CGFloat = xl
    static let sidebarInset: CGFloat = lg
    static let sectionTopGap: CGFloat = lg
    static let sectionBottomGap: CGFloat = md
    static let navigationRowHeight: CGFloat = 32
    static let navigationHorizontalInset: CGFloat = md
    static let headerHeight: CGFloat = 56
    static let contentInset: CGFloat = xl
    static let contentTopInset: CGFloat = xl
    static let contentSectionGap: CGFloat = xl
    static let footerHeight: CGFloat = 56
}

/// The app's only color palette. Views use semantic roles, never literal colors.
enum Palette {
    // Neutral charcoal hierarchy sampled from the supplied reference.
    static let window = Color(red: 0.094, green: 0.094, blue: 0.094)
    static let sidebar = Color(red: 0.196, green: 0.196, blue: 0.196)
    static let panel = Color(red: 0.165, green: 0.165, blue: 0.165)
    static let text = Color(red: 0.94, green: 0.94, blue: 0.94)
    static let accent = Color(red: 0.18, green: 0.45, blue: 0.84)
    static let success = Color.green
    static let audioSelection = Color(red: 0.98, green: 0.76, blue: 0.29)
    static let audioPlayhead = Color(red: 0.35, green: 0.68, blue: 1.0)

    static let stroke = text.opacity(0.09)
    static let muted = text.opacity(0.58)
    static let quiet = text.opacity(0.45)
    static let subdued = text.opacity(0.5)
    static let brightMuted = text.opacity(0.72)
    static let overlayStrong = Color.black.opacity(0.55)
    static let overlaySubtle = Color.black.opacity(0.42)
    static let accentFill = accent.opacity(0.12)
    static let selectionScrim = Color.black.opacity(0.16)
    static let audioSelectionFill = audioSelection.opacity(0.13)
    static let audioSelectionActive = audioSelection.opacity(0.95)
    static let audioSelectionOverview = audioSelection.opacity(0.2)
    static let insertion = Color.gray.opacity(0.9)
}
