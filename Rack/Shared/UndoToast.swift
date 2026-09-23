import SwiftUI

private struct UndoToastBanner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .frame(minHeight: 44)
                    .background(.blue.opacity(0.2), in: Capsule())
            }
            .tint(.blue)
            .accessibilityIdentifier("deletion.undo")
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
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = .zero
                    }
                }
            }
    }
}

private struct UndoToastModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPresented: Bool
    let message: String
    let generation: UUID?
    let onUndo: () -> Void
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if isPresented {
                UndoToastBanner(
                    message: message,
                    onUndo: onUndo,
                    onDismiss: onDismiss
                )
                .id(generation)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
        // Lives on the ZStack, which outlasts the banner: feedback only plays when the
        // trigger changes while the modifier is in the hierarchy.
        .sensoryFeedback(.impact, trigger: isPresented) { _, isShowing in isShowing }
    }
}

extension View {
    func undoToast(
        isPresented: Bool,
        message: String,
        generation: UUID?,
        onUndo: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(UndoToastModifier(
            isPresented: isPresented,
            message: message,
            generation: generation,
            onUndo: onUndo,
            onDismiss: onDismiss
        ))
    }

    /// Shows the Undo toast for pending deletions and presents deletion failures
    /// above this view. Apply it to the app root and to every sheet's root view, so
    /// a failure appears over the frontmost sheet instead of dismissing it.
    func deletionUndoToast(_ coordinator: DeletionCoordinator) -> some View {
        undoToast(
            isPresented: coordinator.showsToast,
            message: coordinator.toastMessage,
            generation: coordinator.generation,
            onUndo: { coordinator.undo() },
            onDismiss: { coordinator.dismissToast() }
        )
        .persistenceAlertHost(coordinator.alertCenter)
    }

    @ViewBuilder
    func deletionUndoToast(_ coordinator: DeletionCoordinator?) -> some View {
        if let coordinator {
            deletionUndoToast(coordinator)
        } else {
            self
        }
    }
}
