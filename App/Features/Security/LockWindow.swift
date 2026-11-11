#if os(iOS)
import SwiftUI
import UIKit

extension View {
    /// Shows `cover` in a window of its own above the app's while `isPresented`. An overlay in the view tree sits under
    /// every sheet and full-screen cover, so a receipt, a source or the tour stayed readable on a locked BOAR and in the
    /// app switcher's snapshot; a window above them covers those too. `takesFocus` (the lock screen) ends editing and
    /// becomes the key window; the app switcher's cover only shows, so pulling down Control Center keeps the composer's
    /// focus.
    func lockWindow(isPresented: Bool, takesFocus: Bool, @ViewBuilder cover: () -> some View) -> some View {
        background(LockWindowAnchor(isPresented: isPresented, takesFocus: takesFocus, cover: AnyView(cover())))
    }
}

/// An invisible view that finds the app's window scene and puts the cover window on it.
private struct LockWindowAnchor: UIViewRepresentable {
    let isPresented: Bool
    let takesFocus: Bool
    let cover: AnyView

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.update(isPresented: isPresented, takesFocus: takesFocus, cover: cover, from: view)
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        private var window: UIWindow?
        private var host: UIHostingController<AnyView>?
        private var isPresented = false
        private var takesFocus = false
        private var cover = AnyView(EmptyView())

        func update(isPresented: Bool, takesFocus: Bool, cover: AnyView, from anchor: UIView) {
            self.isPresented = isPresented
            self.takesFocus = takesFocus
            self.cover = cover
            apply(from: anchor)
        }

        /// Also called when the anchor joins its window: the first update can come before it has one.
        func apply(from anchor: UIView) {
            guard isPresented else {
                guard let window, !window.isHidden else { return }
                let wasKey = window.isKeyWindow
                window.isHidden = true
                // The keyboard and VoiceOver go back to the app's window.
                if wasKey { anchor.window?.makeKey() }
                return
            }
            guard let scene = anchor.window?.windowScene else { return }
            let window = self.window ?? makeWindow(scene)
            host?.rootView = cover
            if takesFocus {
                // The keyboard has a window above this one: put it away, or it and its suggestions stay over the lock.
                anchor.window?.endEditing(true)
                if !window.isKeyWindow { window.makeKeyAndVisible() }
            } else {
                window.isHidden = false
            }
        }

        private func makeWindow(_ scene: UIWindowScene) -> UIWindow {
            let host = UIHostingController(rootView: cover)
            host.view.backgroundColor = .clear
            // VoiceOver stays on the cover instead of reading the chat under it.
            host.view.accessibilityViewIsModal = true
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
