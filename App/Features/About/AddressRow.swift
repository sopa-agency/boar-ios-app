import SwiftUI

/// An address to type or paste (android AboutScreen `CopyRow`), never opened from here: a tap or a press and hold copies
/// `copy` (the address itself by default), and the row says Copied for a moment. `label` sits above the address and `note`
/// under it; a team row (`handle`) puts the name left and the @handle right.
struct AddressRow: View {
    let label: String?
    let text: String
    let note: LocalizedStringKey?
    let copy: String
    @State private var copied = false
    /// The last copy: an earlier copy's timer leaves "Copied" to the newer one.
    @State private var copies = 0

    init(_ text: String, label: String? = nil, note: LocalizedStringKey? = nil, copy: String? = nil) {
        self.text = text
        self.label = label
        self.note = note
        self.copy = copy ?? text
    }

    var body: some View {
        Button(action: copyAddress) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let label {
                        Text(verbatim: label)
                            .font(.boar("ui.body").weight(.medium))
                            .foregroundStyle(.boar(.primary))
                    }
                    Text(verbatim: text)
                        .boarText("mono.sm")
                        .foregroundStyle(label == nil ? .boar(.link) : .boar(.secondary))
                    if let note {
                        Text(note)
                            .font(.boar("ui.subtext"))
                            .foregroundStyle(.boar(.muted))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .boarText("mono.xs")
                        .foregroundStyle(.boar(.success))
                } else {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.boar(.dim))
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Copy \(copy)"))
        .simultaneousGesture(LongPressGesture().onEnded { _ in copyAddress() })
    }

    private func copyAddress() {
        Platform.copy(copy)
        withAnimation { copied = true }
        copies += 1
        let mine = copies
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if mine == copies { withAnimation { copied = false } }
        }
    }
}

/// A core team member (android `TeamRow`): the name left, the @handle right; tap or hold copies x.com/<handle>.
struct TeamRow: View {
    let name: String
    let handle: String
    @State private var copied = false
    @State private var copies = 0

    var body: some View {
        let address = "x.com/\(handle)"
        Button {
            copyAddress(address)
        } label: {
            HStack {
                Text(verbatim: name)
                    .font(.boar("ui.body"))
                    .foregroundStyle(.boar(.primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .boarText("mono.xs")
                        .foregroundStyle(.boar(.success))
                } else {
                    Text(verbatim: "@\(handle)")
                        .boarText("mono.sm")
                        .foregroundStyle(.boar(.secondary))
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.boar(.dim))
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(name) @\(handle)"))
        .accessibilityHint(Text("Copy \(address)"))
        .simultaneousGesture(LongPressGesture().onEnded { _ in copyAddress(address) })
    }

    private func copyAddress(_ address: String) {
        Platform.copy(address)
        withAnimation { copied = true }
        copies += 1
        let mine = copies
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if mine == copies { withAnimation { copied = false } }
        }
    }
}
