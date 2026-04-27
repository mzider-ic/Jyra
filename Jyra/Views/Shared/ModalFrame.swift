import SwiftUI

extension View {
    /// Sizes a sheet modal relative to the presenting screen.
    /// `widthFraction` is the target share of the screen's usable width (default 0.5).
    /// `heightFraction` caps the height as a share of usable height (default 0.8).
    func adaptiveModal(
        widthFraction: CGFloat = 0.5,
        heightFraction: CGFloat = 0.8,
        minWidth: CGFloat = 440,
        minHeight: CGFloat = 360
    ) -> some View {
        modifier(AdaptiveModalModifier(
            widthFraction: widthFraction,
            heightFraction: heightFraction,
            minWidth: minWidth,
            minHeight: minHeight
        ))
    }
}

private struct AdaptiveModalModifier: ViewModifier {
    let widthFraction: CGFloat
    let heightFraction: CGFloat
    let minWidth: CGFloat
    let minHeight: CGFloat

    // Recomputed each time the modifier is applied so it always reflects the
    // current screen (important on multi-monitor setups).
    private var screenFrame: CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    func body(content: Content) -> some View {
        let targetWidth  = max(minWidth,  screenFrame.width  * widthFraction)
        let targetHeight = max(minHeight, screenFrame.height * heightFraction)
        content
            .frame(
                minWidth:  minWidth,
                idealWidth:  targetWidth,
                maxWidth:  targetWidth,
                minHeight: minHeight,
                maxHeight: targetHeight
            )
    }
}
