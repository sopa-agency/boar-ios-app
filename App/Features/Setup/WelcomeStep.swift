import SwiftUI

/// Step 1, editorial: an eyebrow, a large title, the library drawn as three fanned covers, and one button.
struct WelcomeStep: View {
    let flow: SetupFlow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Offline research")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.tint)
                Text("Knowledge that travels with you.")
                    .font(.largeTitle.bold())
                    .padding(.top, 8)
                Text("Pick a library once. BOAR reads it to answer your questions, even with no signal.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
                covers
                    .padding(.top, 26)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .inlineNavigationTitle()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                SetupBottomButton(title: "Get Your Library", action: next)
                Text("Downloads once, over Wi‑Fi. Nothing you ask leaves this \(Platform.deviceNoun).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.bottom, 8)
        }
    }

    /// The library as three fanned covers (decorative; VoiceOver reads them as one summary).
    private var covers: some View {
        ZStack(alignment: .topLeading) {
            LibraryCard(title: "Weather & Climate", detail: "Seasons, storms, monsoons", symbol: "cloud.rain",
                        fill: Color.orange.opacity(0.16), ink: Color.orange)
                .rotationEffect(.degrees(-3))
                .offset(x: 4, y: 0)
            LibraryCard(title: "First Aid", detail: "Burns, bleeding, fever", symbol: "cross.case",
                        fill: Color.teal.opacity(0.16), ink: Color.teal)
                .rotationEffect(.degrees(3))
                .offset(x: 44, y: 72)
            LibraryCard(title: "Encyclopedia", detail: "50,000 article intros", symbol: "book.pages",
                        fill: Color.labelColor, ink: Color.baseBackground, width: 252, height: 158)
                .rotationEffect(.degrees(-1))
                .offset(x: 14, y: 144)
        }
        .frame(maxWidth: .infinity, minHeight: 310, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your library: an encyclopedia plus topics like first aid and weather."))
    }

    private func next() {
        withAnimation { flow.next() }
    }
}
