import BoarAppleAI
import BoarModels
import SwiftUI

/// The answer models as a short list a lay user scans at a glance: the one in use, the others already on this iPhone
/// (tap to switch), the ones to download, and the ones too big for this iPhone tucked away; then the storage BOAR uses.
/// Knowledge packs live on the Documents screen; Hugging Face search is the toolbar's one action.
struct ModelsScreen: View {
    let controller: ModelsController

    @State private var detail: String?
    @State private var showBigger = false
    @State private var usedBytes: Int64?
    @State private var freeBytes: Int64?
    @State private var apple = AppleModelAvailability.current

    private var appleActive: Bool { controller.services.backend == .apple && apple.isAvailable }
    private var models: [CatalogAsset] { controller.answerModels }
    private var inUse: [CatalogAsset] { models.filter { $0.id == controller.activeLlm } }
    private var onPhone: [CatalogAsset] { models.filter { controller.isPresent($0) && $0.id != controller.activeLlm } }
    private var notOnPhone: [CatalogAsset] { models.filter { !controller.isPresent($0) } }
    private var available: [CatalogAsset] { notOnPhone.filter { fit($0) != .red } }
    private var tooBig: [CatalogAsset] { notOnPhone.filter { fit($0) == .red } }

    var body: some View {
        Group {
        #if os(macOS)
        // A Mac window has room for both: the list on the left, the selected model's details on the right.
        MasterDetail {
            modelList
        } detail: {
            macDetail
        }
        .onAppear { if detail == nil { detail = controller.activeLlm } }
        .navigationTitle(AppScreen.models.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    BrowseScreen(controller: controller)
                } label: {
                    Label("Find More Models", systemImage: "plus")
                }
            }
        }
        #else
        modelList
            .navigationTitle(AppScreen.models.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        BrowseScreen(controller: controller)
                    } label: {
                        Label("Find More Models", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(item: $detail) { id in
                if let asset = controller.items.first(where: { $0.id == id }) {
                    ModelDetailScreen(asset: asset, controller: controller)
                }
            }
        #endif
        }
        .onAppear(perform: controller.refresh)
        .task(id: controller.present) { await measureStorage() }
        .debugPush("models-browse") { BrowseScreen(controller: controller) }
        .debugPush("model-detail") {
            if let asset = inUse.first ?? models.first { ModelDetailScreen(asset: asset, controller: controller) }
        }
        .modelsToast(controller)
    }

    private var modelList: some View {
        #if os(macOS)
        List(selection: $detail) { listContent }
        #else
        List { listContent }
            .groupedListStyle()
        #endif
    }

    @ViewBuilder private var listContent: some View {
        if appleActive || !inUse.isEmpty {
            Section("In Use") {
                if appleActive { AppleModelRow(controller: controller, availability: apple) }
                ForEach(inUse) { row($0) }
            }
        }

        if !onPhone.isEmpty || (apple.isAvailable && !appleActive) {
            Section("On This \(Platform.deviceNoun)") {
                if apple.isAvailable && !appleActive { AppleModelRow(controller: controller, availability: apple) }
                ForEach(onPhone) { row($0) }
            }
        }

        if !available.isEmpty {
            // The list footer goes under the last section; an empty footer would still leave a gap.
            if tooBig.isEmpty && apple.isAvailable {
                Section {
                    ForEach(available) { row($0) }
                } header: {
                    Text("Available")
                } footer: {
                    listFooter
                }
            } else {
                Section("Available") {
                    ForEach(available) { row($0) }
                }
            }
        }

        if !tooBig.isEmpty || !apple.isAvailable {
            Section {
                DisclosureGroup("Needs More Memory", isExpanded: $showBigger) {
                    if !apple.isAvailable { AppleModelRow(controller: controller, availability: apple) }
                    ForEach(tooBig) { row($0) }
                }
            } footer: {
                listFooter
            }
        }

        Section("Storage") {
            StorageSummary(usedBytes: usedBytes, freeBytes: freeBytes)
        }
    }

    #if os(macOS)
    @ViewBuilder private var macDetail: some View {
        if let id = detail, let asset = controller.items.first(where: { $0.id == id }) {
            ModelDetailScreen(asset: asset, controller: controller, embedded: true)
                .id(id)
        } else {
            ContentUnavailableView("Select a Model", systemImage: Symbols.model,
                                   description: Text("Its details, and the button to use or download it, appear here."))
        }
    }
    #endif

    private var listFooter: some View {
        Text("Models run on this \(Platform.deviceNoun). BOAR uses one at a time.")
    }

    private func row(_ asset: CatalogAsset) -> some View {
        CatalogRow(asset: asset, controller: controller) { detail = asset.id }
            .tag(asset.id)
    }

    private func fit(_ asset: CatalogAsset) -> Compatibility {
        Compatibility.compute(sizeBytes: asset.sizeBytes, deviceRamBytes: controller.totalRamBytes)
    }

    private func measureStorage() async {
        apple = AppleModelAvailability.current
        // Both block (the free-space query waits on the system's cache-delete service): off the main actor.
        freeBytes = (try? await controller.services.background { _ in DeviceStorage.availableBytes() }) ?? nil
        usedBytes = try? await controller.services.background { $0.storageUsedBytes() }
    }
}
