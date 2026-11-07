import BoarAppleAI
import SwiftUI

/// Apple's on-device model, in the same row shape as the catalog: tapping it switches to it when this iPhone has
/// Apple Intelligence (iPhone 13: not eligible, so it sits under "Needs More Memory").
struct AppleModelRow: View {
    let controller: ModelsController
    let availability: AppleModelAvailability

    private var active: Bool { controller.services.backend == .apple && availability.isAvailable }
    private var loading: Bool { controller.activating == "apple" }

    var body: some View {
        HStack {
            Button(action: controller.useApple) {
                HStack(spacing: 12) {
                    ModelIconTile(symbol: "apple.intelligence", dimmed: !availability.isAvailable)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple Intelligence")
                            .font(.boar("ui.titleSm"))
                            .foregroundStyle(.boar(availability.isAvailable ? .heading : .muted))
                        Group {
                            if loading {
                                Text("Loading…")
                            } else if availability.isAvailable {
                                Text("Built into \(Platform.systemName), nothing to download")
                            } else {
                                Text("Needs Apple Intelligence")
                            }
                        }
                        .font(.boar("ui.subtext"))
                        .foregroundStyle(.boar(loading ? .success : .secondary))
                        Text("Apple's on-device model · built in")
                            .font(.boar("mono.xs"))
                            .foregroundStyle(.boar(.dim))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!availability.isAvailable || active || controller.activating != nil)

            if loading {
                ProgressView()
            } else if active {
                Image(systemName: Symbols.active)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("In use")
            }
        }
    }
}
