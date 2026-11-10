import BoarCore
import BoarRemote
import SwiftUI

/// Settings → Advanced, with "Mac on Your Network" chosen: the server's address, its optional API key, and a check that
/// shows which model answers.
struct RemoteServerSection: View {
    let settings: AppSettings
    let onChange: () -> Void
    @State private var address = ""
    @State private var apiKey = ""
    @State private var checking = false
    @State private var status: Result<RemoteServerStatus, RemoteServerError>?

    var body: some View {
        Section {
            TextField("Address", text: $address, prompt: Text(verbatim: "mac-mini.local:8080"))
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .onSubmit(save)
            SecureField("API Key (optional)", text: $apiKey)
                .onSubmit(save)
            Button(action: check) {
                HStack {
                    Label("Check Connection", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    if checking { ProgressView() }
                }
            }
            .disabled(checking || RemoteServer.parse(address) == nil)
            if let status {
                switch status {
                case .success(let s):
                    Label {
                        Text(verbatim: s.contextTokens.map { "\(s.modelName) · \($0.formatted()) tokens" } ?? s.modelName)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.boar(.success))
                    }
                case .failure(let e):
                    Label {
                        Text(verbatim: e.description)
                    } icon: {
                        Image(icon: Symbols.error).foregroundStyle(.boar(.danger))
                    }
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            BoarHeader {
                Text("Mac on Your Network")
            }
        } footer: {
            BoarFooter {
                Text("Answers are written by llama-server on that Mac; search, your library and your chats stay on this \(Platform.deviceNoun). Both need the same Wi-Fi network.")
            }
        }
        .onAppear {
            address = RemoteConfig.address(settings)
            apiKey = RemoteConfig.apiKey ?? ""
            #if DEBUG
            if DebugLaunch.remote != nil { check() }
            #endif
        }
    }

    private func save() {
        RemoteConfig.setAddress(address, settings)
        RemoteConfig.setApiKey(apiKey)
        onChange()
    }

    private func check() {
        save()
        guard let server = RemoteConfig.server(settings) else { return }
        checking = true
        Task {
            do {
                status = .success(try await server.probe())
            } catch let e as RemoteServerError {
                status = .failure(e)
            } catch {
                status = .failure(.unreachable(error.localizedDescription))
            }
            checking = false
        }
    }
}
