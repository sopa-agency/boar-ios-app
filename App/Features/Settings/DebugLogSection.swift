import SwiftUI
import UniformTypeIdentifiers

/// Engine Tweaks → Debug Log (android SettingsScreen DebugLogRows): the switch, the file's size, Save Log (the system's
/// save panel: the user picks where it goes) and Clear Log.
struct DebugLogSection: View {
    let bridge: SettingsBridge
    @State private var size: Int64 = 0
    @State private var exporting = false
    @State private var document: DebugLogDocument?
    @State private var status: LocalizedStringKey?

    var body: some View {
        let on = bridge.read { $0.debugLogEnabled }
        Section {
            Toggle(isOn: Binding(get: { on }, set: { v in
                DebugLog.setEnabled(v)
                bridge.touch()
                status = nil
                refresh()
            })) {
                Text("Debug Log")
            }
            .accessibilityIdentifier("debugLog.toggle")
            if on || size > 0 {
                Button("Save Log…", systemImage: "square.and.arrow.down") {
                    document = DebugLogDocument(data: DebugLog.savedContents())
                    exporting = true
                }
                .disabled(size == 0)
                Button("Clear Log", systemImage: "trash", role: .destructive) {
                    DebugLog.clear()
                    status = nil
                    refresh()
                }
                .disabled(size == 0)
            }
        } header: {
            BoarHeader {
                Text("Debug Log")
            }
        } footer: {
            BoarFooter {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keeps a file on this \(Platform.deviceNoun) of how BOAR uses it: memory, battery, temperature, model loads, answer speed, downloads and crashes. Never what you ask or what BOAR answers. Nothing is sent: save the file and share it yourself. Uses a little battery.")
                    if on || size > 0 {
                        Text("Log: \(size.formatted(.byteCount(style: .file))) (up to 4 MB, the oldest part is dropped)")
                    }
                    if let status {
                        Text(status)
                    }
                }
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .log, defaultFilename: Self.filename) { result in
            switch result {
            case .success: status = "Log saved"
            case .failure: status = "Couldn't save the log"
            }
            document = nil
        }
        .task(id: on) {
            // The size grows while the log is on: read it again every few seconds while the screen is open.
            while !Task.isCancelled {
                refresh()
                guard on else { break }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func refresh() {
        size = DebugLog.file.sizeBytes()
    }

    private static var filename: String {
        "boar-debug-\(Date().formatted(.iso8601.year().month().day())).log"
    }
}

/// The saved log for the save panel.
struct DebugLogDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.log, .plainText]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
