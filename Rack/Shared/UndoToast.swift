import SwiftUI

private struct UndoToastBanner: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGSize = .zero

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
        .offset(dragOffset)
        .opacity(dragOpacity)
        .contentShape(Rectangle())
        .gesture(dismissGesture)
        .accessibilityAction(named: "Dismiss") {
            onDismiss()
        }
    }

    private var dragOpacity: Double {
        let distance = max(abs(dragOffset.width), max(0, dragOffset.height))
        return max(0.5, 1 - (distance / 180))
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let horizontalDistance = abs(value.translation.width)
                let downwardDistance = max(0, value.translation.height)

                if horizontalDistance >= downwardDistance {
                    dragOffset = CGSize(width: value.translation.width, height: 0)
                } else {
                    dragOffset = CGSize(width: 0, height: downwardDistance)
                }
            }
            .onEnded { value in
                let horizontalDistance = max(
                    abs(value.translation.width),
                    abs(value.predictedEndTranslation.width)
                )
                let downwardDistance = max(
                    value.translation.height,
                    value.predictedEndTranslation.height
                )

                if horizontalDistance >= 80 || downwardDistance >= 60 {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = .zero
                    }
                }
            }
    }
}

private struct UndoToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let onUndo: () -> Void
    @State private var isDismissed = false

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if isPresented && !isDismissed {
                UndoToastBanner(
                    message: message,
                    onUndo: onUndo,
                    onDismiss: dismiss
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .sensoryFeedback(.impact, trigger: isPresented)
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isDismissed)
        .onChange(of: isPresented) { _, presented in
            if !presented {
                isDismissed = false
            }
        }
    }

    private func dismiss() {
        isDismissed = true
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
