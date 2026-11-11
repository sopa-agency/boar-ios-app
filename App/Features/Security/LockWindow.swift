#if os(iOS)
import SwiftUI
import UIKit

extension View {
    /// Shows `cover` in a window of its own above the app's while `isPresented`. An overlay in the view tree sits under
    /// every sheet and full-screen cover, so a receipt, a source or the tour stayed readable on a locked BOAR and in the
    /// app switcher's snapshot; a window above them covers those too.
    func lockWindow(isPresented: Bool, @ViewBuilder cover: () -> some View) -> some View {
        background(LockWindowAnchor(isPresented: isPresented, cover: AnyView(cover())))
    }
}

/// An invisible view that finds the app's window scene and puts the cover window on it.
private struct LockWindowAnchor: UIViewRepresentable {
    let isPresented: Bool
    let cover: AnyView

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.update(isPresented: isPresented, cover: cover, from: view)
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        private var window: UIWindow?
        private var host: UIHostingController<AnyView>?
        private var isPresented = false
        private var cover = AnyView(EmptyView())

        func update(isPresented: Bool, cover: AnyView, from anchor: UIView) {
            self.isPresented = isPresented
            self.cover = cover
            apply(from: anchor)
        }

        /// Also called when the anchor joins its window: the first update can come before it has one.
        func apply(from anchor: UIView) {
            if let host { host.rootView = cover }
            guard isPresented else {
                guard let window, !window.isHidden else { return }
                window.isHidden = true
                // The keyboard and VoiceOver go back to the app's window.
                anchor.window?.makeKey()
                return
            }
            guard let scene = anchor.window?.windowScene else { return }
            let window = self.window ?? makeWindow(scene)
            if window.isHidden || !window.isKeyWindow { window.makeKeyAndVisible() }
        }

        private func makeWindow(_ scene: UIWindowScene) -> UIWindow {
            let host = UIHostingController(rootView: cover)
            host.view.backgroundColor = .clear
            let window = UIWindow(windowScene: scene)
            window.rootViewController = host
            // Above the app's sheets and alerts.
            window.windowLevel = .alert + 1
            window.backgroundColor = .clear
            self.window = window
            self.host = host
            return window
        }

        func tearDown() {
            window?.isHidden = true
            window = nil
            host = nil
        }
    }

    final class AnchorView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.apply(from: self)
        }
    }
}
#endif
