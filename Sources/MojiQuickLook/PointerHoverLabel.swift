import AppKit
import SwiftUI

struct PointerHoverLabel<Label: View>: View {
    @State private var isHovering = false
    private let label: (Bool) -> Label

    init(@ViewBuilder label: @escaping (Bool) -> Label) {
        self.label = label
    }

    var body: some View {
        label(isHovering)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.arrow.set()
                }
            }
    }
}
