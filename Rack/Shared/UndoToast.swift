import SwiftUI

private struct UndoToastBanner: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Button {
                onUndo()
            } label: {
                Text("Undo")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.blue.opacity(0.2), in: Capsule())
            }
            .tint(.blue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassBackground(cornerRadius: 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }
}

private struct UndoToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let onUndo: () -> Void

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if isPresented {
                UndoToastBanner(message: message, onUndo: onUndo)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .sensoryFeedback(.impact, trigger: isPresented)
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
    }
}

extension View {
    func undoToast(
        isPresented: Binding<Bool>,
        message: String,
        onUndo: @escaping () -> Void
    ) -> some View {
        modifier(UndoToastModifier(isPresented: isPresented, message: message, onUndo: onUndo))
    }
}
