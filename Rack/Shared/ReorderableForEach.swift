import SwiftUI

/// A vertical stack that people reorder with the system interaction: touch and hold a row
/// to lift it, drag it into the gap that opens, and release. The system never changes the
/// data mid-drag, so a completed move reaches `onCommitOrder` once, with every item's ID in
/// the new order. VoiceOver gets Move Up and Move Down instead. Place inside a ScrollView;
/// the parent persists the order.
struct ReorderableForEach<T: Identifiable, Content: View>: View where T.ID: Sendable {
    let items: [T]
    let isEnabled: Bool
    let onCommitOrder: (_ orderedIDs: [T.ID]) -> Void
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        VStack(spacing: 12) {
            // Identify views by `T.ID`: the container reports moves with those IDs.
            ForEach(items) { item in
                // Keep glass rendering inside the row that the system lifts.
                GlassEffectContainer(spacing: 12) {
                    content(item)
                }
                .compositingGroup()
                // Lifts the row with the corners of `glassBackground()`.
                .contentShape(.dragPreview, .rect(cornerRadius: 20))
                .accessibilityActions {
                    if isEnabled {
                        Button("Move Up") { moveByOne(item.id, offset: -1) }
                        Button("Move Down") { moveByOne(item.id, offset: 1) }
                    }
                }
            }
            .reorderable()
        }
        .reorderContainer(for: T.self, isEnabled: isEnabled) { difference in
            let destination: T.ID?
            switch difference.destination.position {
            case .before(let id): destination = id
            case .end: destination = nil
            }
            commit(SiblingOrder.moving(difference.sources, before: destination, in: items.map(\.id)))
        }
    }

    private func moveByOne(_ id: T.ID, offset: Int) {
        guard let source = items.firstIndex(where: { $0.id == id }),
              items.indices.contains(source + offset) else { return }
        var ordered = items.map(\.id)
        ordered.swapAt(source, source + offset)
        commit(ordered)
    }

    private func commit(_ orderedIDs: [T.ID]?) {
        guard isEnabled, let orderedIDs, orderedIDs != items.map(\.id) else { return }
        onCommitOrder(orderedIDs)
    }
}
