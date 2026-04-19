import SwiftUI

/// Row-level swipe-to-delete for custom layouts where SwiftUI's
/// `.swipeActions` is a no-op (ScrollView + LazyVStack).
/// Short left-swipe reveals a red Delete affordance; a long (full) swipe
/// commits the delete directly.
struct SwipeToDelete<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var committing = false

    private let actionWidth: CGFloat = 88
    private let fullSwipeThreshold: CGFloat = 180

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAffordance
                .opacity(offset < -0.5 ? 1 : 0)

            content
                .background(TL.Palette.bg)
                .contentShape(Rectangle())
                .offset(x: offset)
                .simultaneousGesture(drag)
        }
        .clipped()
    }

    private var deleteAffordance: some View {
        Button(action: commit) {
            HStack {
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Delete")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.6)
                }
                .foregroundStyle(.white)
                .frame(width: max(actionWidth, -offset))
                .frame(maxHeight: .infinity)
                .background(Color.red)
            }
        }
        .buttonStyle(.plain)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                let dx = value.translation.width
                // Lock out vertical-dominant drags so ScrollView keeps the scroll.
                if abs(value.translation.height) > abs(dx) { return }
                if dx < 0 {
                    offset = max(dx, -600)
                } else if offset < 0 {
                    offset = min(0, -actionWidth + dx)
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                if abs(value.translation.height) > abs(dx) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { offset = 0 }
                    return
                }
                if dx < -fullSwipeThreshold {
                    withAnimation(.easeOut(duration: 0.22)) { offset = -1200 }
                    commit()
                } else if dx < -actionWidth * 0.5 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        offset = -actionWidth
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        offset = 0
                    }
                }
            }
    }

    private func commit() {
        guard !committing else { return }
        committing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onDelete()
        }
    }
}
