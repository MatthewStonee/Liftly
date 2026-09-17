import SwiftUI

/// A sheet's primary action, meant for `safeAreaBar(edge: .bottom)` so it stays above the
/// keyboard and gets the system scroll edge effect.
///
/// While a field is focused, a button beside the action hides the keyboard, since number
/// pads have no key for that.
struct PinnedActionBar<Action: View>: View {
    let isFieldFocused: FocusState<Bool>.Binding
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 12) {
            if isFieldFocused.wrappedValue {
                Button {
                    isFieldFocused.wrappedValue = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.body.weight(.semibold))
                        .frame(width: 56)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassButtonStyle(cornerRadius: 16))
                .foregroundStyle(.primary)
                .accessibilityLabel("Hide Keyboard")
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            action()
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .animation(.easeInOut(duration: 0.2), value: isFieldFocused.wrappedValue)
    }
}
