import SwiftUI

/// A drop is valid only for the drag that began in this exact sibling collection.
struct ReorderDropSession<ID: Hashable> {
    let activeID: ID
    let initialIDs: [ID]

    func acceptedOrder(payloadID: ID, currentIDs: [ID], rawIndex: Int) -> [ID]? {
        guard payloadID == activeID, currentIDs == initialIDs,
              let sourceIndex = initialIDs.firstIndex(of: activeID) else { return nil }
        let boundedIndex = min(max(rawIndex, 0), initialIDs.count)
        let destinationIndex = boundedIndex > sourceIndex ? boundedIndex - 1 : boundedIndex
        var result = initialIDs
        result.remove(at: sourceIndex)
        result.insert(activeID, at: destinationIndex)
        return result
    }
}

struct ReorderDragState<ID: Hashable> {
    private(set) var session: ReorderDropSession<ID>?

    mutating func begin(id: ID, collection: [ID]) {
        session = ReorderDropSession(activeID: id, initialIDs: collection)
    }

    mutating func cancel() {
        session = nil
    }

    mutating func accept(payloadID: ID, collection: [ID], rawIndex: Int) -> [ID]? {
        defer { session = nil }
        return session?.acceptedOrder(payloadID: payloadID, currentIDs: collection, rawIndex: rawIndex)
    }
}

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
        .accessibilityLabel("Drag to reorder")
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

/// A vertically stacked ForEach that saves only an accepted drop or VoiceOver move.
/// Place inside a ScrollView; the parent persists through `onCommitOrder`.
struct ReorderableForEach<T: Identifiable, Content: View>: View where T.ID: Hashable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let items: [T]
    let isEnabled: Bool
    let onCommitOrder: (_ orderedIDs: [T.ID]) -> Void
    @ViewBuilder let content: (T, _ dragHandle: ReorderDragHandle) -> Content

    @State private var draggedID: T.ID? = nil
    @State private var dragState = ReorderDragState<T.ID>()
    @State private var targetInsertionIndex: Int? = nil
    @State private var isDropTargeted = false
    @State private var dragStartFeedbackTrigger = 0
    @State private var insertionFeedbackTrigger = 0
    @State private var commitFeedbackTrigger = 0
    @State private var reorderExitFeedbackTrigger = 0

    private let rowSpacing: CGFloat = 12
    private let appendZoneHeight: CGFloat = 56
    private let targetExpansion: CGFloat = 12

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                content(item, dragHandle(for: item))
                    .opacity(isEnabled && draggedID == item.id ? 0.3 : 1.0)
                    .scaleEffect(!reduceMotion && isEnabled && draggedID == item.id ? 0.98 : 1.0)
                    .zIndex(draggedID == item.id ? 1 : 0)
                    .accessibilityActions {
                        if isEnabled {
                            Button("Move Up") { moveByOne(item.id, offset: -1) }
                            Button("Move Down") { moveByOne(item.id, offset: 1) }
                        }
                    }
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
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.84), value: targetInsertionIndex)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isDropTargeted)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.45), trigger: dragStartFeedbackTrigger)
        .sensoryFeedback(.selection, trigger: insertionFeedbackTrigger)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: commitFeedbackTrigger)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.35), trigger: reorderExitFeedbackTrigger)
        .onChange(of: isEnabled) { wasEnabled, enabled in
            if !enabled {
                if wasEnabled {
                    reorderExitFeedbackTrigger += 1
                }
                resetDragState()
            }
        }
        .onChange(of: itemTokens) { _, newIDs in
            if let session = dragState.session, session.initialIDs != newIDs {
                resetDragState()
            }
        }
        .onDisappear(perform: resetDragState)
    }

    private var displayItems: [T] {
        items
    }

    private var itemTokens: [T.ID] {
        displayItems.map(\.id)
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
    @State private var lastFeedbackTarget: IndicatorTarget? = nil

    private var appendDropZone: some View {
        dropTarget(
            at: displayItems.count,
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
        dragState.begin(id: id, collection: items.map(\.id))

        if let currentIndex = displayItems.firstIndex(where: { $0.id == id }) {
            targetInsertionIndex = currentIndex
            indicatorTarget = .row(index: currentIndex, edge: .top)
            lastFeedbackTarget = indicatorTarget
        }

        dragStartFeedbackTrigger += 1
    }

    private func endDrag(for id: T.ID) {
        guard draggedID == id else { return }
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
            triggerInsertionFeedbackIfNeeded(for: indicatorTarget)
        } else if targetInsertionIndex == index {
            isDropTargeted = false
        }
    }

    private func handleDrop(_ payloads: [String], at rawIndex: Int) -> Bool {
        guard isEnabled else { return false }

        guard let payloadToken = payloads.first,
              let session = dragState.session,
              payloadToken == dragToken(for: session.activeID),
              let accepted = dragState.accept(
                payloadID: session.activeID,
                collection: items.map(\.id),
                rawIndex: rawIndex
              ) else {
            resetDragState()
            return false
        }
        if accepted != items.map(\.id) {
            onCommitOrder(accepted)
            commitFeedbackTrigger += 1
        }
        resetDragState()
        return true
    }

    private func moveByOne(_ id: T.ID, offset: Int) {
        guard isEnabled, let source = items.firstIndex(where: { $0.id == id }) else { return }
        let target = source + offset
        guard items.indices.contains(target) else { return }
        var ordered = items.map(\.id)
        ordered.swapAt(source, target)
        onCommitOrder(ordered)
        commitFeedbackTrigger += 1
    }

    private func triggerInsertionFeedbackIfNeeded(for target: IndicatorTarget) {
        guard lastFeedbackTarget != target else { return }
        lastFeedbackTarget = target
        insertionFeedbackTrigger += 1
    }

    private func resetDragState() {
        draggedID = nil
        dragState.cancel()
        targetInsertionIndex = nil
        isDropTargeted = false
        indicatorTarget = nil
        lastFeedbackTarget = nil
    }
}
