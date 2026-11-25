import SwiftUI

/// Toast.tsx: a short message under the navigation bar, announced to VoiceOver and gone after 1.8 s.
struct ToastView: View {
    @Binding var message: String?
    /// How long it stays; the profile's longer notes ask for more (android Toasts.Toast(millis)).
    var seconds: Double = 1.8

    var body: some View {
        if let message {
            Text(message)
                .font(.subheadline)
                .padding()
                .glassOrMaterial(in: .capsule)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: message) {
                    AccessibilityNotification.Announcement(message).post()
                    try? await Task.sleep(for: .seconds(seconds))
                    // Taken off the screen before its time (held behind another banner): it shows again, whole, after.
                    guard !Task.isCancelled else { return }
                    withAnimation { self.message = nil }
                }
        }
    }
}
