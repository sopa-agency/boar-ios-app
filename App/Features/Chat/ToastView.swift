import SwiftUI

/// Toast.tsx: a short message under the navigation bar, announced to VoiceOver and gone after 1.8 s.
struct ToastView: View {
    @Binding var message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.subheadline)
                .padding()
                .glassOrMaterial(in: .capsule)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: message) {
                    AccessibilityNotification.Announcement(message).post()
                    try? await Task.sleep(for: .seconds(1.8))
                    withAnimation { self.message = nil }
                }
        }
    }
}
