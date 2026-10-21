import BoarAnswer
import BoarModels
import SwiftUI

/// A past chat: its title and when it was last used. A sealed title shows as "Locked Chat".
struct SessionRow: View {
    let session: ChatSession

    var body: some View {
        VStack(alignment: .leading) {
            if session.title == AesTextCipher.locked {
                Label("Locked Chat", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            } else {
                Text(session.title)
                    .lineLimit(1)
            }
            Text(Date(timeIntervalSince1970: Double(session.updatedAt) / 1000), format: .relative(presentation: .named))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
