import SwiftUI

enum LauncherTheme {
    static let panelTop = Color(red: 0.115, green: 0.125, blue: 0.14).opacity(0.82)
    static let panelBottom = Color(red: 0.075, green: 0.082, blue: 0.095).opacity(0.9)
    static let selection = Color(red: 0.29, green: 0.35, blue: 0.43).opacity(0.72)
    static let subtleSelection = Color.white.opacity(0.055)
    static let primary = Color.white.opacity(0.91)
    static let secondary = Color.white.opacity(0.48)
    static let hairline = Color.white.opacity(0.075)
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(LauncherTheme.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LauncherTheme.hairline))
    }
}

struct PanelCloseButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("关闭", systemImage: "xmark")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(LauncherTheme.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.065), in: Capsule())
                .overlay(Capsule().stroke(LauncherTheme.hairline))
        }
        .buttonStyle(.plain)
        .help("\(title)（Esc 或 ⌘W）")
    }
}
