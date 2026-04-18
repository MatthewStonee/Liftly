import SwiftUI

private struct RowFrameKey: PreferenceKey {
    static var defaultValue: [AnyHashable: CGRect] = [:]
    static func reduce(value: inout [AnyHashable: CGRect], nextValue: () -> [AnyHashable: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A vertically stacked ForEach that supports drag-to-reorder.
/// Long-press to lift a row, then drag to reorder. Wraps items in a VStack
/// with spacing 12; place inside a ScrollView.
/// Parent should disable scroll while dragging via the `isDragging` binding.
struct ReorderableForEach<T: Identifiable, Content: View>: View where T.ID: Hashable {
    @Binding var items: [T]
    @Binding var isDragging: Bool
    let onMove: (_ from: Int, _ to: Int) -> Void
    @ViewBuilder let content: (T, _ isDraggingThis: Bool) -> Content

    @State private var draggedId: T.ID? = nil
    @State private var dragOffsetY: CGFloat = 0
    @State private var dragStartIndex: Int = 0
    @State private var dragStartMidY: CGFloat = 0
    @State private var itemFrames: [AnyHashable: CGRect] = [:]
    @State private var justDropped = false
    @State private var liftHapticTrigger = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(items) { item in
                let isThisItemDragging = draggedId == item.id || justDropped
                content(item, isThisItemDragging)
                    .background(frameReader(for: item))
                    .offset(y: isThisItemDragging ? dragOffsetY : 0)
                    .scaleEffect(isThisItemDragging ? 1.03 : 1.0)
                    .opacity(isThisItemDragging ? 0.9 : (draggedId != nil ? 0.72 : 1.0))
                    .shadow(
                        color: isThisItemDragging ? .black.opacity(0.45) : .clear,
                        radius: isThisItemDragging ? 18 : 0,
                        y: isThisItemDragging ? 10 : 0
                    )
                    .zIndex(isThisItemDragging ? 100 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isThisItemDragging)
                    .animation(.easeInOut(duration: 0.2), value: draggedId != nil)
                    .simultaneousGesture(longPressGesture(for: item))
                    .simultaneousGesture(dragGesture(for: item))
            }
        }
        .coordinateSpace(name: "reorderVStack")
        .onPreferenceChange(RowFrameKey.self) { itemFrames = $0 }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1.0), trigger: liftHapticTrigger)
        .onChange(of: draggedId != nil) { _, nowDragging in
            isDragging = nowDragging
        }
    }

    private func frameReader(for item: T) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: RowFrameKey.self,
                value: [item.id as AnyHashable: geo.frame(in: .named("reorderVStack"))]
            )
        }
    }

    private func longPressGesture(for item: T) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .onEnded { _ in
                beginDrag(for: item)
            }
    }

    private func dragGesture(for item: T) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { drag in
                guard draggedId == item.id else { return }
                dragOffsetY = drag.translation.height
            }
            .onEnded { _ in
                guard draggedId == item.id else { return }
                commitDrop()
            }
    }

    private func beginDrag(for item: T) {
        guard draggedId == nil else { return }
        draggedId = item.id
        dragStartIndex = items.firstIndex(where: { $0.id == item.id }) ?? 0
        dragStartMidY = itemFrames[item.id as AnyHashable]?.midY ?? 0
        dragOffsetY = 0
        liftHapticTrigger.toggle()
    }

    private func commitDrop() {
        guard draggedId != nil else {
            resetDrag()
            return
        }

        // Briefly suppress hit-testing so the NavigationLink doesn't fire on finger lift
        justDropped = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            justDropped = false
            draggedId = nil
        }

        let currentMidY = dragStartMidY + dragOffsetY
        let newIndex = targetIndex(for: currentMidY)

        // Zero out offset in the same animation as the reorder so the item lands
        // at its new position without a visible jump.
        withAnimation(.spring(response: 0.3)) {
            dragOffsetY = 0
            if newIndex != dragStartIndex {
                var updated = items
                let item = updated.remove(at: dragStartIndex)
                updated.insert(item, at: newIndex)
                items = updated
            }
        }
        if newIndex != dragStartIndex {
            onMove(dragStartIndex, newIndex)
        }
    }

    private func targetIndex(for midY: CGFloat) -> Int {
        guard let draggedId else { return dragStartIndex }
        for (index, item) in items.enumerated() {
            guard item.id != draggedId,
                  let frame = itemFrames[item.id as AnyHashable] else { continue }
            if midY < frame.midY { return index }
        }
        return items.count - 1
    }

    private func resetDrag() {
        withAnimation(.spring(response: 0.25)) {
            dragOffsetY = 0
        }
        draggedId = nil
    }
}
