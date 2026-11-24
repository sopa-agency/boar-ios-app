import SwiftUI

/// A plain row of About (android `InfoRow`): a title and one line under it, no box.
struct AboutInfoRow: View {
    let title: Text
    let note: Text?

    init(_ title: LocalizedStringKey, _ note: LocalizedStringKey? = nil) {
        self.title = Text(title)
        self.note = note.map { Text($0) }
    }

    init(verbatim title: String, _ note: String?) {
        self.title = Text(verbatim: title)
        self.note = note.map { Text(verbatim: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(.boar("ui.body").weight(.medium))
                .foregroundStyle(.boar(.primary))
            if let note {
                note
                    .font(.boar("ui.subtext"))
                    .foregroundStyle(.boar(.secondary))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A section heading of About (android `AboutSection`): a small line icon and the title in the accent color.
struct AboutHeader: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.boar("ui.titleSm").weight(.semibold))
        .foregroundStyle(.boar(.link))
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }
}
