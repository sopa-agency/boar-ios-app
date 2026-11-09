import SwiftUI

extension View {
    /// The catalog's confirmations as a VoiceOver announcement and a short overlay.
    func modelsToast(_ controller: ModelsController) -> some View {
        overlay(alignment: .bottom) {
            if let message = controller.toast {
                Text(message)
                    .font(.boar("ui.subtext"))
                    .foregroundStyle(.boar(.primary))
                    .padding()
                    .glassOrMaterial(in: .capsule)
                    .padding(.bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        AccessibilityNotification.Announcement(message).post()
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { controller.toast = nil }
                    }
            }
        }
    }
}
