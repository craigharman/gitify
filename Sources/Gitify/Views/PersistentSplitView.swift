import SwiftUI

/// A two-pane split whose divider position is saved to UserDefaults and restored.
///
/// Replaces `HSplitView`/`VSplitView`, which don't persist their divider and reset it to the
/// panes' ideal sizes whenever the split is recreated (switching sections) or a pane is added
/// or removed. The first pane has a fixed, stored size; the second takes the rest.
struct PersistentSplitView<First: View, Second: View>: View {
    enum Axis { case horizontal, vertical }

    let axis: Axis
    let firstMin: CGFloat
    let secondMin: CGFloat
    /// When false the second pane and divider are hidden and the first pane fills the split.
    /// The view tree stays the same so the first pane's state survives toggling.
    let showsSecond: Bool
    let first: First
    let second: Second

    @AppStorage private var storedSize: Double
    /// The size while a drag is in progress (written to `storedSize` when it ends).
    @State private var dragSize: CGFloat?
    @State private var dragStart: CGFloat?

    private static var dividerHitWidth: CGFloat { 6 }

    init(_ axis: Axis,
         autosaveKey: String,
         firstIdeal: CGFloat,
         firstMin: CGFloat,
         secondMin: CGFloat,
         showsSecond: Bool = true,
         @ViewBuilder first: () -> First,
         @ViewBuilder second: () -> Second) {
        self.axis = axis
        self.firstMin = firstMin
        self.secondMin = secondMin
        self.showsSecond = showsSecond
        self.first = first()
        self.second = second()
        _storedSize = AppStorage(wrappedValue: Double(firstIdeal), "split.\(autosaveKey)")
    }

    var body: some View {
        GeometryReader { geo in
            let total = axis == .horizontal ? geo.size.width : geo.size.height
            let size = clamp(dragSize ?? CGFloat(storedSize), total: total)
            let layout = axis == .horizontal
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))

            layout {
                // One unconditional `first` so its identity (and state) survives toggling `showsSecond`.
                first
                    .frame(width: showsSecond && axis == .horizontal ? size : nil,
                           height: showsSecond && axis == .vertical ? size : nil)
                    .frame(maxWidth: showsSecond ? nil : .infinity,
                           maxHeight: showsSecond ? nil : .infinity)
                if showsSecond {
                    divider(currentSize: size, total: total)
                    second.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func divider(currentSize: CGFloat, total: CGFloat) -> some View {
        Divider()
            .overlay {
                // Wider invisible hit area centred on the 1pt line.
                Color.clear
                    .frame(width: axis == .horizontal ? Self.dividerHitWidth : nil,
                           height: axis == .vertical ? Self.dividerHitWidth : nil)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        // Global space: the divider moves with the drag, so local translation would jitter.
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStart ?? currentSize
                                dragStart = start
                                let delta = axis == .horizontal ? value.translation.width : value.translation.height
                                dragSize = clamp(start + delta, total: total)
                            }
                            .onEnded { _ in
                                if let dragSize { storedSize = Double(dragSize) }
                                dragSize = nil
                                dragStart = nil
                            }
                    )
            }
    }

    private func clamp(_ value: CGFloat, total: CGFloat) -> CGFloat {
        let upper = total - secondMin - 1
        return max(firstMin, min(value, upper))
    }
}
