import SwiftUI

struct ReorderDragHandle: View {
    let payload: String
    let isEnabled: Bool
    let preview: AnyView?
    let onDragBegan: () -> Void
    let onDragEnded: () -> Void

    var body: some View {
        let icon = Image(systemName: "line.3.horizontal")
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.secondary.opacity(0.85))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())

        Group {
            if isEnabled, let preview {
                icon
                    .draggable(payload) {
                        ReorderDragPreview(
                            content: preview,
                            onAppear: onDragBegan,
                            onDisappear: onDragEnded
                        )
                    }
            } else {
                icon
            }
        }
        .accessibilityLabel("Reorder")
    }
}

private struct ReorderDragPreview: View {
    let content: AnyView
    let onAppear: () -> Void
    let onDisappear: () -> Void

    var body: some View {
        content
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
    }
}

/// A vertically stacked ForEach that supports handle-based drag-and-drop reordering.
/// Place inside a ScrollView. The parent owns the working array and persists the
/// committed order via `onCommitOrder`.
struct ReorderableForEach<T: Identifiable, Content: View>: View where T.ID: Hashable {
    @Binding var items: [T]
    let isEnabled: Bool
    let onCommitOrder: (_ orderedIDs: [T.ID]) -> Void
    @ViewBuilder let content: (T, _ dragHandle: ReorderDragHandle) -> Content

    @State private var draggedID: T.ID? = nil
    @State private var targetInsertionIndex: Int? = nil
    @State private var isDropTargeted = false
    @State private var didCommitDrop = false

    private let rowSpacing: CGFloat = 12
    private let appendZoneHeight: CGFloat = 56
    private let targetExpansion: CGFloat = 12

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                content(item, dragHandle(for: item))
                    .opacity(isEnabled && draggedID == item.id ? 0.3 : 1.0)
                    .scaleEffect(isEnabled && draggedID == item.id ? 0.98 : 1.0)
                    .zIndex(draggedID == item.id ? 1 : 0)
                    .background {
                        if isEnabled {
                            rowDropTargets(for: index)
                        }
                    }
                    .overlay(alignment: .top) {
                        if isEnabled && indicatorTarget == .row(index: index, edge: .top) {
                            insertionIndicator
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if isEnabled && indicatorTarget == .row(index: index, edge: .bottom) {
                            insertionIndicator
                        }
                    }
            }

            if isEnabled {
                appendDropZone
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: targetInsertionIndex)
        .animation(.easeInOut(duration: 0.18), value: isDropTargeted)
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                resetDragState()
            }
        }
        .onChange(of: itemTokens) { _, _ in
            if let targetInsertionIndex, targetInsertionIndex > items.count {
                self.targetInsertionIndex = items.count
                indicatorTarget = .append
            } else if targetInsertionIndex == nil {
                indicatorTarget = nil
            }
        }
    }

    private var itemTokens: [String] {
        items.map { dragToken(for: $0.id) }
    }

    private enum RowEdge: Equatable {
        case top
        case bottom
    }

    private enum IndicatorTarget: Equatable {
        case row(index: Int, edge: RowEdge)
        case append
    }

    @State private var indicatorTarget: IndicatorTarget? = nil

    private var appendDropZone: some View {
        dropTarget(
            at: items.count,
            height: appendZoneHeight,
            indicatorTarget: .append
        )
        .overlay {
            if isEnabled && indicatorTarget == .append {
                insertionIndicator
            }
        }
    }

    private func rowDropTargets(for index: Int) -> some View {
        GeometryReader { geometry in
            ZStack {
                dropTarget(
                    at: index,
                    height: max((geometry.size.height / 2) + targetExpansion, 44),
                    indicatorTarget: .row(index: index, edge: .top)
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: -targetExpansion)

                dropTarget(
                    at: index + 1,
                    height: max((geometry.size.height / 2) + targetExpansion, 44),
                    indicatorTarget: .row(index: index, edge: .bottom)
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: targetExpansion)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func dropTarget(
        at index: Int,
        height: CGFloat,
        indicatorTarget: IndicatorTarget
    ) -> some View {
        return Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: max(height, 1))
            .contentShape(Rectangle())
            .dropDestination(
                for: String.self,
                action: { payloads, _ in
                    handleDrop(payloads, at: index)
                },
                isTargeted: { targeted in
                    updateDropTarget(
                        at: index,
                        indicatorTarget: indicatorTarget,
                        isTargeted: targeted
                    )
                }
            )
    }

    private var insertionIndicator: some View {
        Capsule()
            .fill(Color.blue)
            .frame(height: 4)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.blue.opacity(0.12))
                    .padding(.horizontal, 4)
            )
            .allowsHitTesting(false)
    }

    private func dragHandle(for item: T) -> ReorderDragHandle {
        ReorderDragHandle(
            payload: dragToken(for: item.id),
            isEnabled: isEnabled,
            preview: isEnabled ? previewContent(for: item) : nil,
            onDragBegan: {
                beginDrag(for: item.id)
            },
            onDragEnded: {
                endDrag(for: item.id)
            }
        )
    }

    private func previewHandle(for item: T) -> ReorderDragHandle {
        ReorderDragHandle(
            payload: dragToken(for: item.id),
            isEnabled: false,
            preview: nil,
            onDragBegan: {},
            onDragEnded: {}
        )
    }

    private func previewContent(for item: T) -> AnyView {
        AnyView(
            content(item, previewHandle(for: item))
                .scaleEffect(1.01)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                .allowsHitTesting(false)
        )
    }

    private func dragToken(for id: T.ID) -> String {
        String(reflecting: id)
    }

    private func beginDrag(for id: T.ID) {
        guard isEnabled else { return }
        draggedID = id
        didCommitDrop = false

        if let currentIndex = items.firstIndex(where: { $0.id == id }) {
            targetInsertionIndex = currentIndex
            indicatorTarget = .row(index: currentIndex, edge: .top)
        }
    }

    private func endDrag(for id: T.ID) {
        guard draggedID == id else { return }

        if !didCommitDrop, let targetInsertionIndex {
            _ = moveItem(with: id, to: targetInsertionIndex)
        }

        resetDragState()
    }

    private func updateDropTarget(
        at index: Int,
        indicatorTarget: IndicatorTarget,
        isTargeted targeted: Bool
    ) {
        guard isEnabled else { return }

        if targeted {
            targetInsertionIndex = index
            isDropTargeted = true
            self.indicatorTarget = indicatorTarget
        } else if targetInsertionIndex == index {
            isDropTargeted = false
        }
    }

    private func handleDrop(_ payloads: [String], at rawIndex: Int) -> Bool {
        guard isEnabled else { return false }

        guard let payloadToken = payloads.first,
              let draggedID = items.first(where: { dragToken(for: $0.id) == payloadToken })?.id else {
            resetDragState()
            return false
        }

        didCommitDrop = true
        let didMove = moveItem(with: draggedID, to: rawIndex)

        if didMove {
            resetDragState()
        }

        return didMove
    }

    private func moveItem(with id: T.ID, to rawIndex: Int) -> Bool {
        guard let sourceIndex = items.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let boundedRawIndex = min(max(rawIndex, 0), items.count)
        let destinationIndex = boundedRawIndex > sourceIndex ? boundedRawIndex - 1 : boundedRawIndex

        guard destinationIndex != sourceIndex else {
            return true
        }

        var reordered = items
        let movedItem = reordered.remove(at: sourceIndex)
        reordered.insert(movedItem, at: min(max(destinationIndex, 0), reordered.count))

        items = reordered
        onCommitOrder(reordered.map(\.id))
        return true
    }

    private func resetDragState() {
        draggedID = nil
        targetInsertionIndex = nil
        isDropTargeted = false
        indicatorTarget = nil
        didCommitDrop = false
    }
}
