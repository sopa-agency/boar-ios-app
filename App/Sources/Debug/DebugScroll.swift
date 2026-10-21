#if DEBUG && canImport(UIKit)
import UIKit

/// `-uiScroll`: scrolls the screen's main list by moving its scroll view, so long screens can be captured in several
/// frames without a tap or swipe. UIKit is fine here: this is audit tooling, not app UI.
@MainActor
enum DebugScroll {
    /// `value` is a number of points from the top, or "end".
    static func scroll(to value: String) {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
              let list = mainScrollView(in: window) else { return }
        let inset = list.adjustedContentInset
        let top = -inset.top
        let bottom = max(top, list.contentSize.height - list.bounds.height + inset.bottom)
        let y = value == "end" ? bottom : min(max(top + (Double(value) ?? 0), top), bottom)
        list.setContentOffset(CGPoint(x: list.contentOffset.x, y: y), animated: false)
    }

    /// The largest vertically scrollable view on screen.
    private static func mainScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func visit(_ view: UIView) {
            if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 1, !scroll.isHidden,
               scroll.bounds.width > 200 {
                if best == nil || scroll.bounds.height * scroll.bounds.width > best!.bounds.height * best!.bounds.width { best = scroll }
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return best
    }
}
#endif
