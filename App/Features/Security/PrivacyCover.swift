import SwiftUI

/// Hides the content in the app switcher's snapshot while the app lock is on.
struct PrivacyCover: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .ignoresSafeArea()
    }
}
