import SwiftUI

#if os(iOS)
extension View {
    func titleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View {
        self.navigationBarTitleDisplayMode(mode)
    }
}
#else
enum TitleDisplayModeStub {
    case automatic, inline, large
}

enum UIKeyboardType {
    case decimalPad, numberPad, emailAddress, asciiCapable, URL, default_
}

extension View {
    func titleDisplayMode(_ mode: TitleDisplayModeStub) -> some View { self }
    func keyboardType(_ type: UIKeyboardType) -> some View { self }
    func fullScreenCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        self.sheet(isPresented: isPresented, content: content)
    }
}
#endif

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let content: () -> Content

    init(cornerRadius: CGFloat = 20, padding: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

struct GlassButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 14) {
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GlassButton: View {
    let title: String
    let icon: String?
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .fontWeight(.semibold)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(GlassButtonStyle())
        .foregroundStyle(role == .destructive ? .red : .primary)
    }
}

struct PrimaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .fontWeight(.bold)
                }
                Text(title)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            )
        }
        .foregroundStyle(.white)
    }
}

struct StatBadge: View {
    enum Style { case standard, hero }
    enum Surface { case glass, embedded }

    let value: String
    let label: String
    var style: Style = .standard
    var surface: Surface = .glass

    @ViewBuilder
    var body: some View {
        switch surface {
        case .glass:
            content
                .glassEffect(.regular, in: .rect(cornerRadius: style == .hero ? 14 : 12))
        case .embedded:
            content
                .background(
                    Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: style == .hero ? 14 : 12)
                )
        }
    }

    private var content: some View {
        VStack(
            alignment: style == .hero ? .leading : .center,
            spacing: style == .hero ? 4 : 2
        ) {
            Text(value)
                .font(style == .hero ? .title2.bold() : .title3.bold())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: style == .hero ? .leading : .center)
        .padding(style == .hero ? 16 : 10)
    }
}

struct SetRepsBadge: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = 20) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(.regular, in: .circle)
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
