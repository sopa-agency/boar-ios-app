import SwiftUI

/// "New avatar unlocked: X" over every screen, with Equip (android `FreshTruffle` through the app's toast: top,
/// 6 s with an action). One at a time, oldest first; announced to VoiceOver.
///
/// Held back while it couldn't be seen (`hidden`: the lock on top, BOAR not in front): avatars counted at
/// `didBecomeActive` arrive under the lock, and the 6 s would run out before a slow unlock. Removed from the screen,
/// its timer stops and the avatar waits.
struct FreshAvatarBanner: View {
    let vault: TruffleVault
    let hidden: Bool
    @ScaledMetric(relativeTo: .subheadline) private var side = 36
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSize
    #endif

    var body: some View {
        if !hidden, let id = vault.fresh.first {
            let message = String(localized: "New avatar unlocked: \(AvatarCopy.name(id))")
            HStack(spacing: 10) {
                TruffleArt.image(id)?
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .clipShape(.rect(cornerRadius: 8))
                    .accessibilityHidden(true)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.boar(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Equip") {
                    vault.equip(id)
                    withAnimation { vault.shown(id) }
                }
                .buttonStyle(.boarProminent)
                .accessibilityIdentifier("vault.fresh.equip")
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .glassOrMaterial(in: .rect(cornerRadius: 18))
            .padding(.horizontal, 16)
            #if os(iOS)
            // Below the navigation bar, as Android's toast sits below the header: over it, it hid Back and the title.
            // The bar is 44 pt (50 on iPad), 32 on an iPhone held sideways.
            .padding(.top, verticalSize == .compact ? 40 : 52)
            #else
            .padding(.top, 8)
            #endif
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: id) {
                AccessibilityNotification.Announcement(message).post()
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                withAnimation { vault.shown(id) }
            }
        }
    }
}
