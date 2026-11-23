import BoarModels
import SwiftUI

/// The sheet behind the header's second line (android `ConnectionSheet`, adam Nov 13): the connection is only an
/// indicator (BOAR answers the same offline), then the answer model: the ones on this device, a tap to answer with
/// another, and the Model Catalog. The Models screen's own controller does the switch, so it stops a running answer first
/// and loads the model, exactly as "Use" does there.
struct ConnectionSheet: View {
    let online: Bool
    let busy: Bool
    let models: ModelsController?
    let onCatalog: () -> Void
    let onClose: () -> Void

    /// The answer models on this device, the active one first (the Models screen's order).
    private var installed: [CatalogAsset] {
        (models?.answerModels ?? []).filter { models?.isPresent($0) == true }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ConnectionDot(online: online, size: 8, ring: 1.5)
                            Text(online ? "Online, but we don't need it." : "Offline, as intended.")
                                .boarText("ui.titleSm")
                                .foregroundStyle(.boar(.heading))
                        }
                        // Short paragraphs with bold marks, as Android's `boldMarks`.
                        Text(online
                             ? "BOAR works the same with or without signal.\n\nThe connection is only for **downloading models or packs**, **searching Hugging Face** and sharing evaluation results, if you turn that on."
                             : "BOAR doesn't need the internet.\n\nYour library is **on this device**, so ask away.")
                            .boarText("ui.body")
                            .foregroundStyle(.boar(.secondary))
                        Text("The dot only shows the connection. BOAR answers the same offline.")
                            .boarText("ui.caption")
                            .foregroundStyle(.boar(.muted))
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    if installed.isEmpty {
                        Text("No answer model on this device yet.")
                            .foregroundStyle(.boar(.muted))
                    }
                    ForEach(installed) { asset in
                        row(asset)
                    }
                    if busy {
                        Text("Wait for the answer to finish to change the model.")
                            .boarText("ui.caption")
                            .foregroundStyle(.boar(.warning))
                    }
                } header: {
                    Text("Answer model")
                }
                Section {
                    Button(action: onCatalog) {
                        HStack {
                            Text("Open the Model Catalog")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").imageScale(.small)
                        }
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(.boar(.link))
                }
            }
            .groupedListStyle()
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetCloseButton(action: onClose) }
            }
        }
        .presentationDetents([.medium, .large])
        .macSheetSize()
    }

    /// The active model is checked; a tap on another switches to it (not while an answer is being written).
    private func row(_ asset: CatalogAsset) -> some View {
        let active = asset.id == models?.activeLlm
        let disabled = active || busy || models?.activating != nil
        return Button {
            models?.use(asset)
            onClose()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .opacity(active ? 1 : 0)
                    .foregroundStyle(.boar(.success))
                    .accessibilityHidden(true)
                Text(verbatim: asset.friendlyName)
                    .fontWeight(active ? .bold : .regular)
                    .foregroundStyle(active ? .boar(.success) : .boar(.primary))
                    .opacity(busy && !active ? 0.5 : 1)
                Spacer(minLength: 0)
                Text(verbatim: FeatureFormat.megabytes(asset.sizeBytes))
                    .boarText("ui.caption")
                    .foregroundStyle(.boar(.muted))
            }
        }
        .disabled(disabled)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
