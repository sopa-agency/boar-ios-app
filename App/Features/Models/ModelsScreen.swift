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
    /// The sorted order while the screen is open: a download that starts, fails or ends doesn't move its row away from
    /// the user's finger (android ModelsScreen). Sorted again when the sort, the filter or the set of models changes.
    @State private var order: [String] = []

    private var appleActive: Bool { controller.services.backend == .apple && apple.isAvailable }
    private var models: [CatalogAsset] { controller.answerModels }
    private var inUse: [CatalogAsset] { models.filter { $0.id == controller.activeLlm } }
    /// Smart's order on the device: the last used first (android `ModelOrder`).
    private var onPhone: [CatalogAsset] {
        ModelOrder.apply(models, sort: .smart, filter: .onPhone, facts: controller.orderFacts).filter { $0.id != controller.activeLlm }
    }
    /// The default view (Smart, All) keeps the sections; any other sort or filter is one list in that order.
    private var sectioned: Bool { controller.sort == .smart && controller.filter == .all }
    private var catalogModels: [CatalogAsset] { controller.items.filter { $0.kind == .llm } }
    private var ordered: [CatalogAsset] {
        let shown = ModelOrder.apply(catalogModels, sort: controller.sort, filter: controller.filter, facts: controller.orderFacts)
        return shown.enumerated().sorted { a, b in
            (order.firstIndex(of: a.element.id) ?? .max, a.offset) < (order.firstIndex(of: b.element.id) ?? .max, b.offset)
        }.map(\.element)
    }
    private var orderKey: String { "\(controller.sort.rawValue)|\(controller.filter.rawValue)|\(catalogModels.count)" }
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
            ToolbarItem(placement: .primaryAction) {
                orderMenu
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
                ToolbarItem(placement: .primaryAction) {
                    orderMenu
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
        .onChange(of: orderKey, initial: true) {
            order = ModelOrder.apply(catalogModels, sort: controller.sort, filter: controller.filter, facts: controller.orderFacts).map(\.id)
        }
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
        List { listContent.boarListRows() }
            .groupedListStyle()
            .boarList()
        #endif
    }

    /// Sort and Show (android ModelsScreen's two chip rows) in one menu, as iOS lists do it.
    private var orderMenu: some View {
        @Bindable var controller = controller
        return Menu {
            Picker(selection: $controller.sort) {
                ForEach(ModelOrder.Sort.allCases, id: \.self) { Self.title($0).tag($0) }
            } label: {
                Text("Sort")
            }
            .pickerStyle(.inline)
            Picker(selection: $controller.filter) {
                ForEach(ModelOrder.Filter.allCases, id: \.self) { Self.title($0).tag($0) }
            } label: {
                Text("Show")
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort and Filter", systemImage: sectioned ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityIdentifier("models.order")
    }

    private static func title(_ sort: ModelOrder.Sort) -> Text {
        switch sort {
        case .smart: Text("Smart")
        case .lastUsed: Text("Last Used")
        case .added: Text("Recently Added")
        }
    }

    private static func title(_ filter: ModelOrder.Filter) -> Text {
        switch filter {
        case .all: Text("All")
        case .onPhone: Text("On This \(Platform.deviceNoun)")
        case .downloading: Text("Downloading")
        case .mine: Text("Added by You")
        }
    }

    @ViewBuilder private var listContent: some View {
        if sectioned {
            sections
        } else {
            Section {
                // Apple's model is built in: it's on this device, never downloading, never added by the user.
                if apple.isAvailable && (controller.filter == .all || controller.filter == .onPhone) {
                    AppleModelRow(controller: controller, availability: apple)
                }
                if ordered.isEmpty {
                    Text("No models here. Pick All to see every model.")
                        .foregroundStyle(.secondary)
                }
                ForEach(ordered) { row($0) }
            } header: {
                Text("\(Self.title(controller.sort)) · \(Self.title(controller.filter))")
            } footer: {
                listFooter
            }
        }

        Section("Storage") {
            StorageSummary(usedBytes: usedBytes, freeBytes: freeBytes)
        }
    }

    @ViewBuilder private var sections: some View {
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

    }

    #if os(macOS)
    @ViewBuilder private var macDetail: some View {
        if let id = detail, let asset = controller.items.first(where: { $0.id == id }) {
            ModelDetailScreen(asset: asset, controller: controller, embedded: true)
                .id(id)
        } else {
            ContentUnavailableView("Select a Model", icon: Symbols.model,
                                   description: Text("Its details, and the button to use or download it, appear here."))
        }
    }
    #endif

    private var listFooter: some View {
        BoarFooter {
            Text("Models run on this \(Platform.deviceNoun). BOAR uses one at a time.")
        }
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
